"""Module 07 - New Blood Request form (inspect / toggle only, never submit).

Test cases 16, 17, 18, 20, 21 and 22 of the SmartBloodLink black-box plan.
"""

from __future__ import annotations

import pytest

from utils.flutter_app import FlutterLocatorError, Node
from utils.session import ensure_patient_home

pytestmark = [pytest.mark.request, pytest.mark.read_only]

UNITS_LABEL = "Units Required (Bags)"
ADDRESS_LABEL = "Hospital / Clinic Delivery Address"
NOTES_LABEL = "Clinical Notes / Patient Condition"

BLOOD_GROUPS = ("A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-")
URGENCY_LEVELS = ("ROUTINE", "URGENT", "CRITICAL")


def open_request_form(app) -> None:
    """Navigate to the New Blood Request screen (form is never submitted)."""
    ensure_patient_home(app)
    app.click_nav_tab("Request")
    app.require_text("New Blood Request", where="after opening the Request tab")


def units_value(app) -> int:
    """Read the displayed 'Units Required' counter."""
    labels = app.find(UNITS_LABEL)
    if not labels:
        raise AssertionError(f"{UNITS_LABEL!r} not on screen:\n{app.text()[:400]}")
    label = labels[0]
    for node in app.nodes():
        if node.text.isdigit() and node.w < 60 and abs(node.y - label.y) < 60:
            return int(node.text)
    raise AssertionError("Units counter not rendered next to the units label")


def unit_buttons(app) -> tuple[Node, Node]:
    """Return (decrement, increment) buttons of the units counter."""
    label = app.find(UNITS_LABEL)[0]
    buttons = [
        n for n in app.nodes()
        if n.role == "button" and not n.text and abs(n.y - label.y) < 60
    ]
    if len(buttons) < 2:
        raise AssertionError(
            f"Expected +/- controls next to {UNITS_LABEL!r}, found {buttons}"
        )
    buttons.sort(key=lambda n: n.x)
    return buttons[0], buttons[-1]


def test_request_form_elements_displayed(app):
    """ID 16 | Module 07

    Expected: blood group chips, units counter, urgency levels, address field
    and clinical notes are present.
    Procedure: open the request form and inspect the controls.
    Screenshot: 20
    """
    open_request_form(app)
    expected = [
        "Required Blood Group",
        *BLOOD_GROUPS,
        UNITS_LABEL,
        "Urgency Level",
        *URGENCY_LEVELS,
        ADDRESS_LABEL,
        NOTES_LABEL,
    ]
    app.require_all(expected, where="on the New Blood Request form")


def test_blood_group_selection_chips(app):
    """ID 17 | Module 07

    Expected: O-, A+ and B+ blood group options can be selected.
    Procedure: toggle the options and verify the selection state; the form is
    never submitted and inventory is never changed.
    Screenshot: 20
    """
    open_request_form(app)
    for group in ("O-", "A+", "B+"):
        before = app.selected_states(BLOOD_GROUPS)
        previously = [g for g, selected in before.items() if selected and g != group]
        app.select(group)
        after = app.selected_states(BLOOD_GROUPS)
        assert after[group], f"{group} is not shown as selected"
        for other in previously:
            assert not after[other], (
                f"{other} stayed selected after choosing {group} - the selector "
                "appears to allow multiple selections"
            )


def test_urgency_level_selection(app):
    """ID 18 | Module 07

    Expected: ROUTINE, URGENT and CRITICAL can be selected.
    Procedure: select each urgency level and verify its active state.
    Screenshot: 20
    """
    open_request_form(app)
    for level in URGENCY_LEVELS:
        app.select(level)
        states = app.selected_states(URGENCY_LEVELS)
        assert states[level], f"{level} is not shown as selected"


def test_request_units_increment_decrement(app):
    """ID 20 | Module 07

    Expected: the units value changes with the +/- controls and never falls
    below the minimum.
    Procedure: open New Blood Request, press plus once and minus once, then
    keep decrementing to confirm the floor; check the displayed count.
    Screenshot: 20
    """
    open_request_form(app)
    minus, plus = unit_buttons(app)
    initial = units_value(app)

    app.click_widget(plus, wait=1.0)
    after_plus = units_value(app)
    assert after_plus == initial + 1, (
        f"Plus control: expected {initial + 1}, displayed {after_plus}"
    )

    app.click_widget(minus, wait=1.0)
    after_minus = units_value(app)
    assert after_minus == initial, (
        f"Minus control: expected {initial} (back to the starting value), "
        f"displayed {after_minus}"
    )

    # Keep decrementing: the counter must stop at its minimum, never below 1.
    observed = [after_minus]
    for _ in range(5):
        app.click_widget(minus, wait=0.9)
        observed.append(units_value(app))
    assert min(observed) >= 1, f"Units counter went below the minimum: {observed}"
    assert observed[-1] == observed[-2], (
        f"Units counter kept decreasing past its minimum: {observed}"
    )


def test_request_address_field_visible(app):
    """ID 21 | Module 07

    Expected: the Hospital/Clinic Delivery Address field is visible and accepts
    text.
    Procedure: focus the address field and enter a sample delivery location
    without submitting the form.
    Screenshot: 20
    """
    open_request_form(app)
    app.require_text(ADDRESS_LABEL, where="on the New Blood Request form")
    sample = "Selenium Test Location, 42 Assessment Road"
    content = app.type_into(ADDRESS_LABEL, sample)
    assert sample in content, (
        f"Address field did not keep the entered text (content={content!r})"
    )
    assert "New Blood Request" in app.text(), "Form must stay open (nothing submitted)"


def test_request_clinical_notes_field_visible(app):
    """ID 22 | Module 07

    Expected: the Clinical Notes / Patient Condition field is visible and
    accepts text.
    Procedure: enter a short sample note and verify it remains in the field.
    Screenshot: 20
    """
    open_request_form(app)
    app.require_text(NOTES_LABEL, where="on the New Blood Request form")
    sample = "Automated check note - patient stable"
    content = app.type_into(NOTES_LABEL, sample)
    assert sample in content, (
        f"Clinical notes field did not keep the entered text (content={content!r})"
    )
    assert NOTES_LABEL in app.text(), "The notes field must remain on screen"
