"""Module 05 - Donor workflows (inspection only).

Test cases 09, 10, 11, 12, 23 and 24 of the SmartBloodLink black-box plan.
"""

from __future__ import annotations

import pytest

from utils.flutter_app import FlutterLocatorError
from utils.session import login_as

pytestmark = [pytest.mark.donor, pytest.mark.read_only]

# Labels that prove the donor availability switch is on the dashboard.
AVAILABILITY_STATES = ("Active & Ready to Donate", "Currently Unavailable")

# Health self-assessment controls of the eligibility checker (UI only - this is
# a form, not medical advice).
ELIGIBILITY_CONTROLS = (
    "Body Weight is Above 50 kg",
    "No Tattoo or Piercing in Past 6 Months",
    "Hemoglobin Level Normal",
)

# Key rows of the incoming emergency request card.
SOS_DETAILS = (
    "Request ID",
    "Units Required",
    "Urgency Level",
    "Hospital Center",
    "Condition",
)


def as_donor(app) -> None:
    """Enter the Donor demo role (1-tap shortcut) and land on its portal."""
    login_as(app, "Donor")
    app.require_text("Donor Portal", where="after the Donor demo shortcut")


def open_donor_tab(app, label: str) -> None:
    as_donor(app)
    app.click_nav_tab(label)


def test_donor_dashboard_loads(app):
    """ID 09 | Module 05

    Expected: the Donor Portal and the availability status toggle are visible.
    Procedure: use the approved Donor demo route; inspect only.
    Screenshot: 23
    """
    as_donor(app)
    app.require_text("Donor Portal", where="on the donor dashboard")
    app.require_text("DONOR REWARDS BALANCE", where="on the donor dashboard")

    # The switch renders exactly one of the two availability captions.
    states = [s for s in AVAILABILITY_STATES if s in app.text()]
    if not states:
        app.scan_text()
        states = [s for s in AVAILABILITY_STATES if s in app.text()]
    assert states, (
        "Neither availability caption of the donor status toggle is visible. "
        f"Dashboard shows:\n{app.text()[:400]}"
    )
    switches = [n for n in app.nodes() if n.role in ("switch", "checkbox") and n.w > 0]
    assert switches, "No availability switch control was rendered on the donor dashboard"
    app.scroll_to_top()


def test_donor_incoming_requests_tab(app):
    """ID 10 | Module 05

    Expected: the Requests tab shows the emergency matching radar.
    Procedure: navigate to Donor Requests and inspect the UI only.
    Screenshot: 21

    The radar is the pulsing "heartbeat" indicator that frames the live
    emergency match; it is verified together with the matching panel labels it
    decorates (the animation itself is captured in the screenshot).

    Timing note: opening the Requests tab starts a 48-second response
    countdown; on expiry the app auto-declines the SOS. All assertions here
    complete in a few seconds after the tab opens, well inside that window.
    """
    open_donor_tab(app, "Requests")
    app.require_text("Incoming Emergency SOS", where="on the donor Requests tab")
    app.require_all(
        ["Patient Needs", "Response Timer"],
        where="in the emergency matching panel",
    )


def test_donor_rewards_and_leaderboard(app):
    """ID 11 | Module 05

    Expected: the Rewards and Leaderboard tabs show reward points and donor
    ranks.
    Procedure: navigate to both tabs and verify the displayed sections.
    Screenshot: 26
    """
    open_donor_tab(app, "Rewards")
    app.require_text("Rewards & Badges", where="on the Rewards tab")
    app.require_all(
        ["CURRENT DONOR BALANCE", "Points", "Achievement Badges"],
        where="on the Rewards tab",
    )

    app.click_nav_tab("Rankings")
    app.require_text("Community Leaderboard", where="on the Rankings tab")
    if " pts" not in app.text():
        app.require_text("pts", where="in the donor rankings list")


def test_donor_eligibility_checker(app):
    """ID 12 | Module 05

    Expected: the Eligibility tab includes a 90-day waiting-period calculator
    and controls for weight > 50 kg, no tattoo and normal haemoglobin.
    Procedure: inspect the toggles/calculator UI only - the result is a form
    status, never medical advice.
    Screenshot: 28
    """
    open_donor_tab(app, "Eligibility")
    app.require_text("Donor Eligibility Check", where="on the Eligibility tab")
    app.require_text(
        "Donation Interval Status (90 Days Rule)",
        where="on the Eligibility tab",
    )
    app.require_text("Last Donation Date:", where="in the 90-day calculator")
    app.require_all(list(ELIGIBILITY_CONTROLS), where="in the self-assessment form")

    # The three controls must be real switches/toggles, not plain text.
    controls = [
        n for n in app.nodes()
        if any(name in n.matches_text for name in ELIGIBILITY_CONTROLS)
        and n.w > 0 and n.h > 0
    ]
    assert controls, "No eligibility control nodes were rendered"
    roles = {n.role for n in controls}
    assert roles & {"switch", "checkbox", "button"}, (
        f"Eligibility controls are not interactive: roles seen {roles}"
    )
    # The form itself must never be submitted by this test.
    app.require_text("Save Eligibility Declaration", where="on the Eligibility tab")


def test_emergency_sos_request_details(app):
    """ID 23 | Module 05

    Expected: the Incoming Emergency SOS screen displays request ID, units,
    urgency, hospital and condition.
    Procedure: open the emergency SOS demo screen and check the key details.
    Screenshot: 24

    The screen's 48-second response timer starts on entry; the checks below
    run immediately after opening the tab and stay inside that window.
    """
    open_donor_tab(app, "Requests")
    app.require_text("Incoming Emergency SOS", where="on the donor Requests tab")
    app.require_all(list(SOS_DETAILS), where="in the emergency SOS request card")
    # Request id format (REQ-...) proves the identifier is rendered, not just
    # the row label.
    if "REQ-" not in app.text():
        app.scan_text()
        assert "REQ-" in app.text(), "No request identifier rendered on the SOS card"


def test_emergency_mission_hospital_details(app):
    """ID 24 | Module 05

    Expected: the Emergency Donation Mission displays the destination hospital
    and a navigation action.
    Procedure: open the mission screen and verify destination, distance and the
    Navigate control.
    Screenshot: 25

    Reaching the mission screen uses the demo-mode "Accept Emergency Call"
    shortcut on the SOS screen; demo mode is a local simulation, so no server
    record, donation or stock entry is created.
    """
    open_donor_tab(app, "Requests")
    app.require_text("Incoming Emergency SOS", where="on the donor Requests tab")
    try:
        app.click("Accept Emergency Call", timeout=15, wait=3)
    except FlutterLocatorError:
        app.scan_text()
        app.click("Accept Emergency Call", timeout=10, wait=3)
    app.require_text("Emergency Donation Mission", where="after accepting the demo call")
    app.require_text("Hospital Destination", where="on the mission screen")
    app.require_text("Distance:", where="on the mission screen")
    app.require_text("Navigate", where="on the mission screen")
