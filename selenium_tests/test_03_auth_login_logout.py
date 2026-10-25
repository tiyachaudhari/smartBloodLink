"""Module 03 - Demo authentication shortcuts.

Test cases 08 and 29 of the SmartBloodLink black-box plan.
"""

from __future__ import annotations

import pytest

from utils.session import DEMO_ROLES, ROLE_MARKERS, login_as, open_login

pytestmark = [pytest.mark.auth, pytest.mark.read_only]


def test_quick_demo_login(app):
    """ID 08 | Module 03

    Expected: selecting the "Patient" demo chip authenticates the demo session
    and routes to the dashboard.
    Procedure: use the site's explicit demo shortcut (1-Tap Demo Logins).
    Screenshot: 17
    """
    open_login(app)
    app.require_text("1-Tap Demo Logins", where="on the login screen")
    login_as(app, "Patient")
    app.require_text(ROLE_MARKERS["Patient"], where="after the Patient demo shortcut")
    app.require_text(
        "Need Blood Urgently?", where="on the dashboard reached by the demo shortcut"
    )


def test_role_demo_shortcuts_visible(app):
    """ID 29 | Module 03

    Expected: Patient, Donor, Hospital, Ambulance and Admin demo shortcut
    options are visible on the login page.
    Procedure: open the login page and verify the role shortcut labels.
    Screenshot: 17
    """
    open_login(app)
    app.require_text("1-Tap Demo Logins", where="on the login screen")
    missing = [role for role in DEMO_ROLES if role not in app.text()]
    assert not missing, (
        f"Demo shortcut chips missing from the login screen: {missing}. "
        f"Screen shows:\n{app.text()[:500]}"
    )
