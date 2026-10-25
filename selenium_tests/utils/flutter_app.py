"""Flutter Web page helper for black-box Selenium testing.

The SmartBloodLink site is a Flutter Web application: the UI is painted into a
single graphics surface, so no label exists in the DOM until Flutter's
accessibility (semantics) tree is switched on.  This module wraps everything a
test needs:

* ``open()``            - load the app and build the semantics tree
* ``text()``            - every visible label on screen (``body.innerText``)
* ``find() / click()``  - locate and tap a widget by its visible text
* ``select()``          - tap a chip/toggle and verify it became selected
* ``type_into()``       - focus a text field and verify what was typed
* ``screenshot()``      - capture evidence for the test plan

Interaction model (learned from the live app, see README):
1. Native ``element.click()`` is unusable - Flutter nodes have
   ``pointer-events: none``.  Clicks are sent as *trusted* CDP mouse events at
   the widget's viewport coordinates.
2. A fixed bottom navigation bar (~76 px) and the app bar (~56 px) overlay the
   scene, so a target is scrolled into the safe middle band before it is
   tapped; otherwise the click silently lands on the navigation bar.
3. Flutter rebuilds the semantics tree on every navigation, so nodes are always
   re-queried - never cached between actions.
"""

from __future__ import annotations

import io
import re
import time
from dataclasses import dataclass
from typing import Iterable, Optional, Sequence

from PIL import Image
from selenium.webdriver.common.action_chains import ActionChains

from .constants import (
    CLICK_TIMEOUT,
    ENGINE_TIMEOUT,
    POST_CLICK_PAUSE,
    SEMANTICS_TIMEOUT,
    TEXT_TIMEOUT,
)

SAFE_TOP = 56          # bottom edge of the app bar
SAFE_BOTTOM_MARGIN = 76  # top edge of the fixed bottom navigation
NAV_RE = re.compile(r"Tab \d of \d$")

# Sample point inside a chip/toggle (left of the centred caption).
SAMPLE_DX = 40
SELECTED_SATURATION = 60  # max(rgb) - min(rgb) above this = filled/selected


class FlutterLocatorError(AssertionError):
    """Raised when an expected widget never appears on screen."""


@dataclass(frozen=True)
class Node:
    """A semantics node (one tappable / readable widget) in the current frame.

    ``text`` is what the widget prints (``innerText``) and falls back to its
    ``aria-label``: Flutter exposes some widgets - notably the demo shortcut
    chips on the login screen - only through ``aria-label``.
    """

    idx: int
    x: float
    y: float
    w: float
    h: float
    role: Optional[str]
    text: str
    label: str = ""

    @property
    def cx(self) -> float:
        return self.x + self.w / 2

    @property
    def cy(self) -> float:
        return self.y + self.h / 2

    @property
    def matches_text(self) -> str:
        """Everything this widget can be identified by (text + aria-label)."""
        if self.label and self.label not in self.text:
            return f"{self.text}\n{self.label}"
        return self.text

    @property
    def is_nav_tab(self) -> bool:
        return self.role == "button" and bool(NAV_RE.search(self.text))

    @property
    def rect(self) -> tuple[float, float, float, float]:
        return (self.x, self.y, self.w, self.h)

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"Node(idx={self.idx}, box={self.rect}, role={self.role!r}, text={self.text!r})"


class FlutterApp:
    """Session-scoped driver wrapper with a test-friendly API."""

    def __init__(self, driver, base_url: str):
        self.driver = driver
        self.base_url = base_url
        self._last_screenshot: Optional[Image.Image] = None
        self._img_scale: float = 1.0  # CSS px → screenshot px (set per capture)

    # ------------------------------------------------------------------ setup
    def open(self) -> None:
        """Load the app (fresh route state) and make the UI readable."""
        self.driver.get(self.base_url)
        self.wait_for_engine()
        self.enable_semantics()

    def wait_for_engine(self, timeout: int = ENGINE_TIMEOUT) -> None:
        """Block until Flutter has mounted its view and rendered a first frame."""
        end = time.time() + timeout
        while time.time() < end:
            ready = self.driver.execute_script(
                "return !!(document.querySelector('flutter-view')"
                " || document.querySelector('flt-glass-pane'));"
            )
            if ready:
                return
            time.sleep(0.5)
        raise FlutterLocatorError(
            f"Flutter engine did not mount within {timeout}s at {self.driver.current_url}"
        )

    def enable_semantics(self, timeout: int = SEMANTICS_TIMEOUT) -> None:
        """Build Flutter's accessibility tree (the only source of DOM text)."""
        end = time.time() + timeout
        while time.time() < end:
            count = self.driver.execute_script(
                "return document.querySelectorAll('flt-semantics').length;"
            )
            if count:
                # One extra beat: the first nodes arrive before their content.
                if self.driver.execute_script(
                    "const t = (document.body.innerText || '').trim();"
                    " if (t.length) return true;"
                    " return Array.from(document.querySelectorAll('flt-semantics'))"
                    "   .some(n => (n.getAttribute('aria-label') || '').trim());"
                ):
                    return
            self.driver.execute_script(
                "const p = document.querySelector('flt-semantics-placeholder');"
                " if (p) p.click();"
            )
            time.sleep(1)
        raise FlutterLocatorError(
            "Flutter semantics tree could not be enabled (app is unreadable to tests)"
        )

    def reload(self) -> None:
        """Reload and rebuild the semantics tree in place."""
        self.driver.refresh()
        self.wait_for_engine()
        self.enable_semantics()

    # ---------------------------------------------------------------- reading
    def text(self) -> str:
        """All labels of the current frame.

        Combines ``body.innerText`` with the ``aria-label`` of every semantics
        node, because Flutter publishes some widgets (the demo shortcut chips)
        only through ``aria-label``.
        """
        return self.driver.execute_script(
            """
            const printed = document.body.innerText || '';
            const labels = Array.from(document.querySelectorAll('flt-semantics'))
                .map(n => (n.getAttribute('aria-label') || '').trim())
                .filter(l => l && !printed.includes(l));
            return labels.length ? printed + '\\n' + labels.join('\\n') : printed;
            """
        )

    def input_values(self) -> list[str]:
        """Values of the (hidden) inputs Flutter keeps in sync with text fields."""
        return self.driver.execute_script(
            "return Array.from(document.querySelectorAll('input, textarea'))"
            ".map(el => el.value || '');"
        )

    def active_input_value(self) -> str:
        return self.driver.execute_script(
            "const a = document.activeElement;"
            " return (a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA'))"
            " ? (a.value || '') : '';"
        )

    def viewport(self) -> tuple[int, int]:
        w, h = self.driver.execute_script(
            "return [window.innerWidth, window.innerHeight];"
        )
        return int(w), int(h)

    def nodes(self) -> list[Node]:
        raw = self.driver.execute_script(
            """
            return Array.from(document.querySelectorAll('flt-semantics')).map((n, i) => {
                const r = n.getBoundingClientRect();
                const printed = (n.innerText || '').trim();
                const labelled = (n.getAttribute('aria-label') || '').trim();
                return {idx: i, x: r.x, y: r.y, w: r.width, h: r.height,
                        role: n.getAttribute('role'),
                        text: printed || labelled,
                        label: labelled};
            });
            """
        )
        return [Node(**item) for item in raw]

    def find(self, target: str, nodes: Optional[Sequence[Node]] = None) -> list[Node]:
        """Nodes whose visible text (or aria-label) contains ``target``.

        Exact / leading matches win, then the smallest widget (leaf) - the root
        node always contains the whole screen text and must never be clicked.
        """
        needle = target.strip()
        pool = list(nodes) if nodes is not None else self.nodes()
        matches = [
            n for n in pool
            if n.w > 0 and n.h > 0 and needle in n.matches_text
        ]

        def rank(node: Node) -> tuple[int, str, float]:
            exact = 0 if (
                node.text == needle
                or node.text.startswith(needle)
                or node.label == needle
                or node.label.startswith(needle)
            ) else 1
            return (exact, node.label or node.text, node.w * node.h)

        matches.sort(key=rank)
        return matches

    # --------------------------------------------------------------- waiting
    def wait_text(self, needle: str, timeout: int = TEXT_TIMEOUT) -> bool:
        end = time.time() + timeout
        while time.time() < end:
            if needle in self.text():
                return True
            time.sleep(0.4)
        return False

    def require_text(self, needle: str, timeout: int = TEXT_TIMEOUT,
                     where: str = "", scroll: bool = True) -> str:
        """Assert a label is on screen, scrolling the current screen if needed.

        Flutter only exposes *visible* widgets to tests, so long screens (login
        shortcuts, hospital dashboard) need a scroll before their lower sections
        exist for the assertions.  Scrolling never navigates away.
        """
        if self.wait_text(needle, timeout):
            return needle
        if scroll and self.scroll_for_text(needle, max_steps=6):
            return needle
        raise FlutterLocatorError(
            f"Expected {needle!r} {where} was not visible. Screen now shows:\n"
            f"{self.text()[:600]}"
        )

    def require_all(self, needles: Iterable[str], where: str = "",
                    scan: bool = True) -> None:
        """Assert several labels belong to the current screen.

        Labels below the fold are only registered by Flutter once they are
        scrolled into view, so when something is missing the screen is scanned
        top-to-bottom and the assertion is checked against the union of every
        frame (this proves the labels are all part of *this* screen).
        """
        needles = list(needles)
        current = self.text()
        missing = [n for n in needles if n not in current]
        scanned = bool(missing) and scan
        if scanned:
            union = self.scan_text()
            missing = [n for n in missing if n not in union]
        if missing:
            raise FlutterLocatorError(
                f"Missing {missing} {where}. Screen shows:\n{current[:600]}"
            )
        if scanned:
            self.scroll_to_top()  # leave the screen where a reader expects it

    def wait_text_absent(self, needle: str, timeout: int = TEXT_TIMEOUT) -> bool:
        end = time.time() + timeout
        while time.time() < end:
            if needle not in self.text():
                return True
            time.sleep(0.4)
        return False

    def scroll_for_text(self, needle: str, max_steps: int = 10) -> bool:
        """Scroll the current screen until ``needle`` is rendered.

        Flutter only feeds *visible* widgets into the semantics tree, so a
        section below the fold (e.g. the demo shortcut card on the login
        screen) does not exist for tests until it is scrolled into view.
        """
        for _ in range(max_steps):
            if needle in self.text():
                return True
            _, vh = self.viewport()
            self.wheel(280, x=700, y=vh - 120)
            time.sleep(0.7)
        return needle in self.text()

    def scan_text(self, max_steps: int = 8) -> str:
        """Union of every label reachable by scrolling the current screen.

        Used when an assertion spans a screen taller than the viewport (a long
        form, the hospital dashboard): no single frame contains them all.
        """
        chunks = [self.text()]
        for _ in range(max_steps):
            _, vh = self.viewport()
            self.wheel(280, x=700, y=vh - 120)
            time.sleep(0.7)
            current = self.text()
            if current == chunks[-1]:  # bottom of the screen reached
                break
            chunks.append(current)
        return "\n".join(chunks)

    def scroll_to_top(self, max_steps: int = 10) -> None:
        """Return the current screen to its top (evidence screenshots)."""
        for _ in range(max_steps):
            before = self.text()
            self.wheel(-320, x=700, y=200)
            time.sleep(0.5)
            if self.text() == before:
                return

    def require_url_contains(self, fragment: str) -> None:
        if fragment not in self.driver.current_url:
            raise FlutterLocatorError(
                f"Expected URL containing {fragment!r}, got {self.driver.current_url!r}"
            )

    def require_title(self, expected: str) -> None:
        actual = self.driver.title
        if actual != expected:
            raise FlutterLocatorError(f"Expected page title {expected!r}, got {actual!r}")

    # -------------------------------------------------------------- interacting
    def _cdp(self, event: dict) -> None:
        self.driver.execute_cdp_cmd("Input.dispatchMouseEvent", event)

    def _mouse_move(self, x: float, y: float) -> None:
        self._cdp({"type": "mouseMoved", "x": int(x), "y": int(y)})

    def _mouse_click(self, x: float, y: float) -> None:
        x, y = int(x), int(y)
        self._cdp({"type": "mouseMoved", "x": x, "y": y})
        time.sleep(0.12)
        self._cdp({"type": "mousePressed", "x": x, "y": y, "button": "left", "clickCount": 1})
        self._cdp({"type": "mouseReleased", "x": x, "y": y, "button": "left", "clickCount": 1})

    def wheel(self, delta_y: float, x: float = 700, y: float = 400) -> None:
        """Scroll the Flutter scene (DOM scrolling does not reach it)."""
        _, vh = self.viewport()
        self._cdp(
            {
                "type": "mouseWheel",
                "x": int(max(10, min(x, 1400))),
                "y": int(max(60, min(y, vh - 40))),
                "deltaX": 0,
                "deltaY": int(delta_y),
                "pointerType": "mouse",
            }
        )

    def _node_by_idx(self, idx: int) -> Optional[Node]:
        for node in self.nodes():
            if node.idx == idx:
                return node
        return None

    def _prepare(self, node: Node, tries: int = 12) -> Optional[Node]:
        """Scroll a widget into the safe band so the tap cannot hit an overlay."""
        if node.is_nav_tab:
            _, vh = self.viewport()
            return node if 0 <= node.y and node.y + node.h <= vh else None
        for _ in range(tries):
            _, vh = self.viewport()
            if node.y >= SAFE_TOP and node.y + node.h <= vh - SAFE_BOTTOM_MARGIN:
                return node
            if node.y + node.h > vh - SAFE_BOTTOM_MARGIN:
                delta = min(400, node.y + node.h - (vh - SAFE_BOTTOM_MARGIN) + 60)
            elif node.y < SAFE_TOP:
                delta = max(-400, node.y - SAFE_TOP - 60)
            else:
                delta = 0
            before = node.y
            self.wheel(delta, x=node.cx, y=max(70, min(vh - 100, node.cy)))
            time.sleep(0.9)
            fresh = self._node_by_idx(node.idx)
            if fresh is None:
                return None
            if abs(fresh.y - before) < 1.0:  # screen cannot scroll further
                node = fresh
                break
            node = fresh
        _, vh = self.viewport()
        return node if 0 <= node.y and node.y + node.h <= vh else None

    def click_node(self, node: Node, wait: float = POST_CLICK_PAUSE) -> None:
        self._mouse_click(node.cx, node.cy)
        time.sleep(wait)

    def click(self, target: str, timeout: int = CLICK_TIMEOUT,
               wait: float = POST_CLICK_PAUSE) -> Node:
        """Tap the widget whose visible text contains ``target``."""
        end = time.time() + timeout
        last_seen: Optional[Node] = None
        while time.time() < end:
            for candidate in self.find(target):
                last_seen = candidate
                prepared = self._prepare(candidate)
                if prepared is not None:
                    self.click_node(prepared, wait)
                    return prepared
            time.sleep(0.4)
        raise FlutterLocatorError(
            f"Could not tap {target!r} within {timeout}s"
            + (f" (found at {last_seen.rect} but it stayed under an overlay)"
               if last_seen else " (widget not found on screen)")
        )

    def try_click(self, target: str, **kwargs) -> bool:
        try:
            self.click(target, **kwargs)
            return True
        except FlutterLocatorError:
            return False

    def click_widget(self, node: Node, wait: float = POST_CLICK_PAUSE) -> Node:
        """Scroll ``node`` clear of the fixed overlays, then tap it."""
        prepared = self._prepare(node)
        if prepared is None:
            raise FlutterLocatorError(
                f"Widget {node!r} could not be brought into a tappable position"
            )
        self.click_node(prepared, wait)
        return prepared

    def click_nav_tab(self, label: str) -> None:
        """Tap a bottom-navigation tab such as ``Tracking``."""
        matches = [n for n in self.nodes() if n.is_nav_tab and n.text.startswith(label)]
        if not matches:
            raise FlutterLocatorError(
                f"Bottom navigation tab {label!r} not present. Tabs: "
                f"{[n.text for n in self.nodes() if n.is_nav_tab]}"
            )
        self.click_node(matches[0])

    def nav_tab_labels(self) -> list[str]:
        return [n.text for n in self.nodes() if n.is_nav_tab]

    def press_keys(self, keys: str) -> None:
        """Send keystrokes to the focused Flutter text field."""
        ActionChains(self.driver).send_keys(keys).perform()
        time.sleep(1.0)

    # ----------------------------------------------------------- field helpers
    def _empty_node_below(self, label: Node, span: float = 90) -> Optional[Node]:
        best: Optional[Node] = None
        bottom = label.y + label.h
        for node in self.nodes():
            if node.idx == label.idx or node.text:
                continue
            if node.w > 300 and bottom - 6 <= node.y <= bottom + span:
                if best is None or node.y < best.y:
                    best = node
        return best

    def type_into(self, label: str, value: str, timeout: int = CLICK_TIMEOUT) -> str:
        """Focus the text field under ``label``, type ``value``, return its content.

        The app is never submitted: only the field contents are changed.
        """
        end = time.time() + timeout
        last_error = ""
        while time.time() < end:
            matches = self.find(label)
            if not matches:
                time.sleep(0.4)
                continue
            field = self._empty_node_below(matches[0])
            if field is None:
                last_error = f"no input area found under {label!r}"
                time.sleep(0.4)
                continue
            prepared = self._prepare(field)
            if prepared is None:
                last_error = f"input area under {label!r} stayed under an overlay"
                time.sleep(0.4)
                continue
            self.click_node(prepared, wait=1.4)
            self._mouse_move(prepared.cx, prepared.cy)  # keep hover over the field
            self.press_keys(value)
            content = self.active_input_value() or " ".join(self.input_values())
            if value in content:
                return content
            last_error = f"typed text not present in field (content={content!r})"
            time.sleep(0.4)
        raise FlutterLocatorError(f"Could not type {value!r} into {label!r}: {last_error}")

    # ------------------------------------------------------ visual (pixel) API
    def _screenshot(self) -> Image.Image:
        """Capture the viewport and record its CSS-to-image pixel scale.

        Headed Chrome on a display-scaled Windows machine (125%/150%) returns
        screenshots larger than the CSS viewport; every coordinate we sample is
        a CSS pixel, so it must be multiplied by this scale first.
        """
        img = Image.open(io.BytesIO(self.driver.get_screenshot_as_png())).convert("RGB")
        css_width = self.driver.execute_script(
            "return window.innerWidth || document.documentElement.clientWidth || 0;"
        )
        self._img_scale = (img.width / css_width) if css_width else 1.0
        self._last_screenshot = img
        return img

    def _average_color(self, img: Image.Image, x: float, y: float,
                       size: int = 8) -> tuple[int, int, int]:
        s = self._img_scale
        left, top = round(x * s), round(y * s)
        span = max(2, round(size * s))
        box = img.crop((left, top, left + span, top + span))
        # BOX resampling of a 1x1 reduction == mean colour of the region.
        return tuple(box.resize((1, 1), Image.Resampling.BOX).getpixel((0, 0)))

    def color_at(self, x: float, y: float, size: int = 8) -> tuple[int, int, int]:
        """Average colour of a small region of the rendered UI."""
        return self._average_color(self._screenshot(), x, y, size)

    @staticmethod
    def saturation(color: Sequence[int]) -> int:
        return max(color) - min(color)

    def node_color(self, node: Node, dx: float = SAMPLE_DX,
                   dy: Optional[float] = None) -> tuple[int, int, int]:
        y = node.cy if dy is None else node.y + dy
        return self.color_at(node.x + dx, y)

    def is_selected(self, node: Node) -> bool:
        """True when a chip/toggle renders its filled (selected) state.

        Flutter does not expose ``selected`` through ARIA, so the decision is
        made on the rendered colour: a selected chip is filled (saturated), an
        unselected one is pale/white.
        """
        return self.saturation(self.node_color(node)) > SELECTED_SATURATION

    def selected_state(self, target: str) -> bool:
        """Colour-based selection state of a single chip/toggle."""
        return self.selected_states([target])[target]

    def selected_states(self, targets: Sequence[str]) -> dict[str, bool]:
        """Selection state of several chips from ONE screenshot (fast).

        Flutter does not expose ``selected`` through ARIA, so the decision is
        made on the rendered colour: a selected chip has a filled (saturated)
        background, an unselected one is pale/white.
        """
        wanted = list(dict.fromkeys(targets))
        resolved: dict[str, Node] = {}
        for target in wanted:
            matches = self.find(target)
            if not matches:
                raise FlutterLocatorError(f"Widget {target!r} not found for selection check")
            prepared = self._prepare(matches[0])
            if prepared is None:
                raise FlutterLocatorError(
                    f"Widget {target!r} is never visible - cannot sample its state"
                )
            resolved[target] = prepared
        # Coordinates may have shifted while scrolling: re-read, capture, sample.
        fresh: dict[str, Node] = {}
        for target in wanted:
            matches = self.find(target)
            if matches:
                fresh[target] = matches[0]
        img = self._screenshot()
        _, vh = self.viewport()
        result: dict[str, bool] = {}
        for target, node in fresh.items():
            if node.y < 0 or node.y + node.h > vh:
                raise FlutterLocatorError(
                    f"Widget {target!r} left the viewport before it could be sampled"
                )
            color = self._average_color(img, node.x + SAMPLE_DX, node.cy)
            result[target] = self.saturation(color) > SELECTED_SATURATION
        missing = [t for t in wanted if t not in result]
        if missing:
            raise FlutterLocatorError(f"Widgets disappeared before sampling: {missing}")
        return result

    def select(self, target: str, timeout: int = CLICK_TIMEOUT) -> None:
        """Tap a chip/toggle and assert that it is now shown as selected."""
        end = time.time() + timeout
        while time.time() < end:
            if not self.try_click(target, timeout=2, wait=1.2):
                time.sleep(0.4)
                continue
            if self.selected_state(target):
                return
            time.sleep(0.4)
        raise FlutterLocatorError(f"{target!r} did not become selected after tapping it")

    def deselect(self, target: str, timeout: int = CLICK_TIMEOUT) -> None:
        """Tap a chip/toggle that is selected and assert it turned unselected."""
        end = time.time() + timeout
        while time.time() < end:
            if not self.try_click(target, timeout=2, wait=1.2):
                time.sleep(0.4)
                continue
            if not self.selected_state(target):
                return
            time.sleep(0.4)
        raise FlutterLocatorError(f"{target!r} stayed selected after tapping it")

    # ------------------------------------------------------------- screenshots
    def screenshot(self, path) -> str:
        from pathlib import Path

        target = Path(path)
        target.parent.mkdir(parents=True, exist_ok=True)
        self.driver.save_screenshot(str(target))
        return str(target)
