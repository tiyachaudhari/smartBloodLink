"""Module 06 - Blood bank map, directory and inventory filters.

Test cases 13, 14 and 15 of the SmartBloodLink black-box plan.
"""

from __future__ import annotations

import re

import pytest

from utils.session import ensure_patient_home

pytestmark = [pytest.mark.search, pytest.mark.read_only]

# Blood bank stock directory entries rendered under the city map.
DIRECTORY_ENTRIES = (
    "City Apex Blood Center",
    "Ruby Hall Clinic Transfusion Services",
    "Sassoon General Hospital Red Cross Bank",
    "Deenanath Mangeshkar Hospital Blood Bank",
)


def open_blood_banks(app) -> None:
    ensure_patient_home(app)
    app.click_nav_tab("Blood Banks")
    app.require_text("City Blood Availability Map", where="on the Blood Banks tab")


def displayed_units(app) -> set[int]:
    """Unit counts currently rendered by the stock directory."""
    values = re.findall(r"(\d+)\s*Units", app.text())
    return {int(v) for v in values}


def test_blood_availability_map_loads(app):
    """ID 13 | Module 06

    Expected: the City Blood Availability Map and the blood bank stock
    directory appear.
    Procedure: open Blood Banks and verify the map/directory content.
    Screenshot: 22
    """
    open_blood_banks(app)
    app.require_text("Filter by Blood Group", where="on the blood bank screen")
    # The directory below the map lists every stocked blood bank.
    app.require_all(list(DIRECTORY_ENTRIES), where="in the blood bank directory")


def test_blood_group_filter_selection(app):
    """ID 14 | Module 06

    Expected: B+, AB- and O- filters can be toggled to filter the inventory.
    Procedure: toggle the filters and verify the selection and the resulting
    unit counts; no inventory is modified.
    Screenshot: 22
    """
    open_blood_banks(app)
    baseline = displayed_units(app)
    assert baseline, "No inventory units were rendered before filtering"

    results: dict[str, set[int]] = {}
    for group in ("B+", "AB-", "O-"):
        app.select(group)
        states = app.selected_states(("B+", "AB-", "O-"))
        assert states[group], f"{group} filter is not shown as selected"
        for other, selected in states.items():
            if other != group:
                assert not selected, f"{other} stayed selected while {group} was chosen"
        # The directory must re-render counts for the chosen group.
        units = displayed_units(app)
        assert units, f"No unit counts rendered for the {group} filter"
        results[group] = units

    assert results["B+"] != results["O-"], (
        "Changing the blood group filter did not change the displayed inventory "
        f"(B+ and O- both showed {results['B+']})"
    )


def test_blood_bank_navigation_tabs_active(app):
    """ID 15 | Module 06

    Expected: the bottom navigation stays visible and usable on the blood-bank
    view.
    Procedure: verify navigation visibility and return to another tab.
    Screenshot: 22
    """
    open_blood_banks(app)
    tabs = app.nav_tab_labels()
    assert len(tabs) == 5, f"Expected 5 navigation tabs on the blood bank view, got {tabs}"
    app.click_nav_tab("History")
    app.require_text("Request History", where="after leaving the blood bank view")
    app.click_nav_tab("Home")
    app.require_text("Need Blood Urgently?", where="after returning home")
