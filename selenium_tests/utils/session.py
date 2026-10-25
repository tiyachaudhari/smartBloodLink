"""Demo-session helpers: reach the login screen and switch roles.

The app boots straight into a simulated Patient session (demo mode).  Every
role is reachable from the login screen's "1-Tap Demo Logins" shortcut chips,
and any session can be left through Profile -> Sign Out.
"""

from __future__ import annotations

from .flutter_app import FlutterApp, FlutterLocatorError

LOGIN_MARKER = "1-Tap Demo Logins"
# "Sign In" alone is too generic, so the login screen is recognised by its
# headline (always at the top) or by the shortcut card itself.
LOGIN_SENTINELS = ("Welcome to Smart BloodLink", LOGIN_MARKER)

# Text that proves each role's portal is on screen.
ROLE_MARKERS: dict[str, str] = {
    "Patient": "Patient Portal",
    "Donor": "Donor Portal",
    "Hospital": "Blood Bank Portal",
    "Ambulance": "AMBULANCE",
    "Admin": "ADMIN",
}

DEMO_ROLES = ("Patient", "Donor", "Hospital", "Ambulance", "Admin")


def on_login_screen(app: FlutterApp) -> bool:
    return any(sentinel in app.text() for sentinel in LOGIN_SENTINELS)


def open_login(app: FlutterApp) -> None:
    """Navigate Profile -> Sign Out so the demo shortcut chips are visible."""
    if on_login_screen(app):
        app.scroll_for_text(LOGIN_MARKER)
        return
    app.click("User Profile")
    app.require_text("My Profile", where="after opening the profile")
    app.click("Sign Out")
    if not app.wait_text("Sign In"):
        raise FlutterLocatorError(
            f"Login screen did not appear after Sign Out. Screen shows:\n{app.text()[:400]}"
        )
    # The shortcut card sits below the fold and only enters the semantics tree
    # once it has been scrolled into view.
    app.scroll_for_text(LOGIN_MARKER)
    if not app.wait_text(LOGIN_MARKER, timeout=5):
        raise FlutterLocatorError(
            f"{LOGIN_MARKER!r} section not offered on the login screen. "
            f"Screen shows:\n{app.text()[:400]}"
        )


def login_as(app: FlutterApp, role: str, timeout: int = 30) -> None:
    """Use the explicit 1-tap demo shortcut for ``role``."""
    if role not in DEMO_ROLES:
        raise ValueError(f"Unknown demo role: {role!r}")
    open_login(app)
    app.require_text(role, where="on the login screen demo shortcuts")
    app.click(role, wait=2.5)
    marker = ROLE_MARKERS.get(role)
    if marker and not app.wait_text(marker, timeout):
        raise FlutterLocatorError(
            f"{role} demo login did not reach a screen showing {marker!r}. "
            f"Screen shows:\n{app.text()[:400]}"
        )
    if on_login_screen(app):
        raise FlutterLocatorError(f"{role} demo shortcut left the app on the login screen")


def ensure_patient_home(app: FlutterApp) -> None:
    """Default test starting point: the Patient portal home screen."""
    if on_login_screen(app):
        login_as(app, "Patient")
        return
    if "Need Blood Urgently?" not in app.text():
        try:
            app.click_nav_tab("Home")
        except FlutterLocatorError:
            pass
        app.require_text("Need Blood Urgently?", where="on the patient home screen")
