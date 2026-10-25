"""Module 02 - Tab navigation, screen titles and the tracking OTP.

Test cases 04-07 and 25 of the SmartBloodLink black-box plan.
"""

from __future__ import annotations

import re

import pytest

from utils.session import ensure_patient_home

pytestmark = [pytest.mark.navigation, pytest.mark.read_only]

# Heading variants accepted for the tracking screen: the plan names
# "Live Tracking" (empty state) while an active emergency shows "Tracking:
# <request id>" - both are the same live-tracking view.
TRACKING_HEADINGS = ("Live Tracking", "Tracking:")


def _tracking_heading(app) -> str:
    text = app.text()
    for heading in TRACKING_HEADINGS:
        if heading in text:
            return heading
    raise AssertionError(
        f"Neither {TRACKING_HEADINGS} found on the tracking screen. Screen shows:\n"
        f"{text[:500]}"
    )


def test_navigate_to_request_tab(app):
    """ID 04 | Module 02

    Expected: the Request tab shows "New Blood Request" plus Blood Group,
    Units and Urgency controls.
    Procedure: select the Request tab and assert the heading/controls.
    Screenshot: 20
    """
    ensure_patient_home(app)
    app.click_nav_tab("Request")
    app.require_all(
        [
            "New Blood Request",
            "Required Blood Group",
            "Units Required",
            "Urgency Level",
        ],
        where="on the New Blood Request screen",
    )


def test_navigate_to_tracking_tab(app):
    """ID 05 | Module 02

    Expected: the Tracking view shows "Live Tracking" and "Ambulance
    Assigned".
    Procedure: select the Tracking tab and verify the labels.
    Screenshot: 19
    """
    ensure_patient_home(app)
    app.click_nav_tab("Tracking")
    heading = _tracking_heading(app)
    app.require_text("Ambulance Assigned", where=f"on the {heading!r} screen")


def test_navigate_to_blood_banks_tab(app):
    """ID 06 | Module 02

    Expected: the Blood Banks view shows "City Blood Availability Map" and
    "Filter by Blood Group".
    Procedure: select the Blood Banks tab and verify the map/filter labels.
    Screenshot: 22
    """
    ensure_patient_home(app)
    app.click_nav_tab("Blood Banks")
    app.require_all(
        ["City Blood Availability Map", "Filter by Blood Group"],
        where="on the blood banks screen",
    )


def test_navigate_back_to_home_tab(app):
    """ID 07 | Module 02

    Expected: the Home tab restores the Patient Portal home.
    Procedure: leave Home, return to it and verify the home content.
    Screenshot: 18
    """
    ensure_patient_home(app)
    app.click_nav_tab("Tracking")
    app.require_text("Ambulance Assigned", where="after leaving the home tab")
    app.click_nav_tab("Home")
    app.require_all(
        ["Patient Portal", "Need Blood Urgently?", "Create Emergency Request"],
        where="after returning to the home tab",
    )


def test_tracking_delivery_otp_visible(app):
    """ID 25 | Module 02

    Expected: the tracking screen displays a delivery confirmation OTP section
    with a code area.
    Procedure: open the tracking screen and verify the OTP label and code area.
    Screenshot: 19
    """
    ensure_patient_home(app)
    app.click_nav_tab("Tracking")
    app.require_text(
        "DELIVERY CONFIRMATION OTP", where="on the tracking screen"
    )
    # The code area renders a 6-digit confirmation code below the label.
    otp_digits = re.findall(r"(?<!\d)\d{6}(?!\d)", app.text())
    assert otp_digits, (
        "No 6-digit delivery OTP was rendered under the OTP section. Screen shows:\n"
        + app.text()[:500]
    )
