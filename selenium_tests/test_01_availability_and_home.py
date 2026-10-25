"""Module 01 - Site availability and the patient home screen.

Test cases 01-03 of the SmartBloodLink black-box plan.
"""

from __future__ import annotations

import pytest

from utils.constants import APP_TITLE, BASE_URL
from utils.session import ensure_patient_home

pytestmark = [pytest.mark.smoke, pytest.mark.read_only, pytest.mark.navigation]


def test_website_availability_and_title(app):
    """ID 01 | Module 01

    Expected: URL begins with the target HTTPS URL; page title equals
    "Smart BloodLink".
    Procedure: Open the website and assert final URL and title.
    Screenshot: 17
    """
    ensure_patient_home(app)
    assert app.driver.current_url.startswith(BASE_URL), (
        f"Final URL {app.driver.current_url!r} does not start with {BASE_URL!r}"
    )
    app.require_title(APP_TITLE)


def test_patient_portal_dashboard_rendered(app):
    """ID 02 | Module 01

    Expected: visible text includes "Patient Portal", "Patient",
    "Need Blood Urgently?", "Create Emergency Request" and "Live Request
    Status".
    Procedure: wait for the Flutter UI, then verify each visible label.
    Screenshot: 18
    """
    ensure_patient_home(app)
    app.require_all(
        [
            "Patient Portal",
            "Patient",
            "Need Blood Urgently?",
            "Create Emergency Request",
            "Live Request Status",
        ],
        where="on the patient dashboard",
    )


def test_navigation_tabs_present(app):
    """ID 03 | Module 01

    Expected: five accessible navigation tabs - Home Tab 1 of 5, Request Tab 2
    of 5, Tracking Tab 3 of 5, History Tab 4 of 5, Blood Banks Tab 5 of 5.
    Procedure: verify all five navigation tabs are present and accessible.
    Screenshot: 18
    """
    ensure_patient_home(app)
    expected = [
        "Home Tab 1 of 5",
        "Request Tab 2 of 5",
        "Tracking Tab 3 of 5",
        "History Tab 4 of 5",
        "Blood Banks Tab 5 of 5",
    ]
    actual = app.nav_tab_labels()
    assert actual == expected, f"Navigation tabs were {actual}, expected {expected}"
