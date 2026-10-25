"""Shared configuration for the SmartBloodLink black-box Selenium suite."""

from __future__ import annotations

import os
from pathlib import Path

# --- target application -----------------------------------------------------
BASE_URL = os.environ.get("SBL_BASE_URL", "https://smartbloodlink.fenric.uk/")
APP_TITLE = "Smart BloodLink"

# --- run mode ---------------------------------------------------------------
# Headless Chrome by default; set SBL_HEADED=1 (or SBL_HEADED=0) to override.
HEADLESS = os.environ.get("SBL_HEADED", "0").lower() not in ("1", "true", "yes")
WINDOW_SIZE = os.environ.get("SBL_WINDOW_SIZE", "1440,900")

# --- timing (seconds) -------------------------------------------------------
ENGINE_TIMEOUT = 45          # wait for the Flutter engine + first frame
SEMANTICS_TIMEOUT = 30       # wait for the accessibility tree to be built
CLICK_TIMEOUT = 20           # wait for a tappable semantics node
TEXT_TIMEOUT = 20            # wait for a label to appear after navigation
POST_CLICK_PAUSE = 1.6       # settle time after a screen transition

# --- outputs ----------------------------------------------------------------
ROOT = Path(__file__).resolve().parent.parent  # the selenium_tests/ folder
SCREENSHOT_DIR = Path(os.environ.get("SBL_SHOTS", ROOT / "screenshots"))
REPORT_DIR = ROOT / "reports"

# Screenshot number documented for each test case in the black-box test plan.
SCREENSHOT_MAP: dict[str, int] = {
    "test_website_availability_and_title": 17,
    "test_patient_portal_dashboard_rendered": 18,
    "test_navigation_tabs_present": 18,
    "test_navigate_to_request_tab": 20,
    "test_navigate_to_tracking_tab": 19,
    "test_navigate_to_blood_banks_tab": 22,
    "test_navigate_back_to_home_tab": 18,
    "test_quick_demo_login": 17,
    "test_donor_dashboard_loads": 23,
    "test_donor_incoming_requests_tab": 21,
    "test_donor_rewards_and_leaderboard": 26,
    "test_donor_eligibility_checker": 28,
    "test_blood_availability_map_loads": 22,
    "test_blood_group_filter_selection": 22,
    "test_blood_bank_navigation_tabs_active": 22,
    "test_request_form_elements_displayed": 20,
    "test_blood_group_selection_chips": 20,
    "test_urgency_level_selection": 20,
    "test_hospital_workflow_and_dashboard": 30,
    "test_request_units_increment_decrement": 20,
    "test_request_address_field_visible": 20,
    "test_request_clinical_notes_field_visible": 20,
    "test_emergency_sos_request_details": 24,
    "test_emergency_mission_hospital_details": 25,
    "test_tracking_delivery_otp_visible": 19,
    "test_hospital_stock_summary_visible": 30,
    "test_cold_chain_temperature_displayed": 30,
    "test_low_stock_alert_displayed": 30,
    "test_role_demo_shortcuts_visible": 17,
}

# Bottom navigation of the patient portal (used by several modules).
PATIENT_TABS = ["Home", "Request", "Tracking", "History", "Blood Banks"]
