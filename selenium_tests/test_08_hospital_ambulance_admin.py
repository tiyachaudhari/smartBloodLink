"""Module 08 - Hospital portal: stock, cold chain and low-stock alerts.

Test cases 19, 26, 27 and 28 of the SmartBloodLink black-box plan.
"""

from __future__ import annotations

import re

import pytest

from utils.session import login_as

pytestmark = [pytest.mark.hospital, pytest.mark.read_only]

# Status labels the fridge card can render; "NO READING" means the sensor data
# is missing and therefore fails the display checks.
TEMP_STATUSES = (
    "Optimal (2-6°C)",
    "Outside 2-6°C",
    "BREACH ALERT!",
)


def as_hospital(app) -> None:
    """Enter the Hospital demo role (1-tap shortcut)."""
    login_as(app, "Hospital")
    app.require_text("Blood Bank Portal", where="after the Hospital demo shortcut")


def fridge_card_text(app) -> str:
    """The cold-chain card is small and sits high on the dashboard."""
    return app.text()


def test_hospital_workflow_and_dashboard(app):
    """ID 19 | Module 08

    Expected: the Hospital Staff portal, the stock overview and the cold-chain
    indicators appear.
    Procedure: use the approved demo route and inspect only.
    Screenshot: 30
    """
    as_hospital(app)
    app.require_all(
        ["Blood Bank Portal", "TOTAL BLOOD UNITS", "Stock Count by Blood Group"],
        where="on the hospital dashboard",
    )
    # Cold-chain indicator: the fridge device card with its temperature status.
    text = fridge_card_text(app)
    assert "°C" in text, f"No cold-chain temperature on the dashboard:\n{text[:400]}"
    assert any(status in text for status in TEMP_STATUSES), (
        f"No cold-chain status indicator on the dashboard:\n{text[:400]}"
    )


def test_hospital_stock_summary_visible(app):
    """ID 26 | Module 08

    Expected: the hospital dashboard displays the total blood units and the
    stock by blood group.
    Procedure: open the Hospital Staff demo and inspect the total units and the
    blood-group stock cards.
    Screenshot: 30
    """
    as_hospital(app)
    app.require_all(
        ["TOTAL BLOOD UNITS", "Stock Count by Blood Group"],
        where="on the hospital dashboard",
    )
    totals = re.findall(r"TOTAL BLOOD UNITS\s*\n?\s*(\d+)", app.text())
    if not totals:
        # The number sits in its own semantics node right under the caption.
        totals = re.findall(r"^\s*(\d{1,4})\s*$", app.text(), flags=re.MULTILINE)
    assert totals, (
        "No total-units figure rendered under 'TOTAL BLOOD UNITS'. "
        f"Dashboard shows:\n{app.text()[:400]}"
    )
    group_units = re.findall(r"(\d+)\s*Units", app.text())
    if not group_units:
        app.scan_text()
        group_units = re.findall(r"(\d+)\s*Units", app.text())
    assert len(group_units) >= 2, (
        "Blood-group stock cards were not rendered. "
        f"Dashboard shows:\n{app.text()[:400]}"
    )
    app.scroll_to_top()


def test_cold_chain_temperature_displayed(app):
    """ID 27 | Module 08

    Expected: the fridge temperature is displayed with an optimal/normal
    status indicator.
    Procedure: inspect the ESP32 fridge temperature card and its status text.
    Screenshot: 30
    """
    as_hospital(app)
    text = fridge_card_text(app)

    readings = re.findall(r"(\d{1,2}\.\d)\s*°C", text)
    assert readings, f"No fridge temperature reading on the dashboard:\n{text[:400]}"

    status = next((s for s in TEMP_STATUSES if s in text), None)
    assert status, (
        "The fridge card shows no optimal/out-of-range status indicator "
        f"(sensor data missing?). Dashboard shows:\n{text[:400]}"
    )

    # The card belongs to the ESP32 fridge (device caption on the card).
    lowered = text.lower()
    assert "esp32" in lowered or "fridge" in lowered, (
        f"Temperature card is not attributed to the ESP32 fridge:\n{text[:400]}"
    )


def test_low_stock_alert_displayed(app):
    """ID 28 | Module 08

    Expected: the Low Stock Threshold Alert is visible when blood groups fall
    below the displayed threshold.
    Procedure: open the hospital dashboard demo and inspect the low-stock
    warning area.
    Screenshot: 30
    """
    as_hospital(app)
    app.require_text(
        "Low Stock Threshold Alert!",
        where="on the hospital dashboard",
    )
    app.require_text(
        "Running low (< 3 units) in:",
        where="in the low-stock warning area",
    )
