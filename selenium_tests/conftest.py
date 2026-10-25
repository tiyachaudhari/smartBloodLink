"""pytest fixtures for the SmartBloodLink black-box Selenium suite."""

from __future__ import annotations

import pytest
from selenium import webdriver
from selenium.webdriver.chrome.options import Options

from utils.constants import (
    BASE_URL,
    HEADLESS,
    SCREENSHOT_DIR,
    SCREENSHOT_MAP,
    WINDOW_SIZE,
)
from utils.flutter_app import FlutterApp
from utils.session import ensure_patient_home


def _build_driver() -> webdriver.Chrome:
    options = Options()
    if HEADLESS:
        options.add_argument("--headless=new")
    options.add_argument(f"--window-size={WINDOW_SIZE}")
    options.add_argument("--disable-gpu")
    options.add_argument("--disable-dev-shm-usage")
    # Windows display scaling (125%/150%) makes headed Chrome capture its
    # screenshots at the device pixel ratio while all node coordinates / CDP
    # input are in CSS pixels - force a 1:1 mapping for consistent behaviour.
    options.add_argument("--force-device-scale-factor=1")
    # Deterministic rendering for colour-based assertions (chip selection).
    options.add_argument("--force-color-profile=srgb")
    options.add_argument("--hide-scrollbars")
    driver = webdriver.Chrome(options=options)
    driver.set_page_load_timeout(60)
    return driver


@pytest.hookimpl(hookwrapper=True)
def pytest_runtest_makereport(item, call):
    """Expose pass/fail state to fixtures so screenshots can be labelled."""
    outcome = yield
    report = outcome.get_result()
    setattr(item, f"rep_{report.when}", report)


@pytest.fixture(scope="session")
def driver():
    """One browser for the whole run (fast, and the app is a single page)."""
    drv = _build_driver()
    yield drv
    drv.quit()


@pytest.fixture
def app(driver) -> FlutterApp:
    """A freshly loaded app, semantics enabled, parked on the patient home."""
    application = FlutterApp(driver, BASE_URL)
    application.open()
    ensure_patient_home(application)
    return application


@pytest.fixture(autouse=True)
def evidence(request, driver, app):
    """Save the documented screenshot for every test (plus one on failure)."""
    yield
    name = request.node.name
    number = SCREENSHOT_MAP.get(request.function.__name__)
    SCREENSHOT_DIR.mkdir(parents=True, exist_ok=True)
    failed = getattr(request.node, "rep_call", None) is not None and request.node.rep_call.failed
    suffix = "_FAIL" if failed else ""
    if number is not None:
        app.screenshot(SCREENSHOT_DIR / f"{name}_ss{number}{suffix}.png")
    elif failed:
        app.screenshot(SCREENSHOT_DIR / f"{name}_FAILED.png")
