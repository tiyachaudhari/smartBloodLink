# SmartBloodLink — Black-box Selenium suite

Browser-level (black-box) tests for the deployed site
**<https://smartbloodlink.fenric.uk/>**, written against the 29-case test plan
(Module 01–08). No access to the application source is required to run them.

---

## 1. Setup

```bash
cd selenium_tests
python -m venv .venv && .venv\Scripts\activate      # optional
pip install -r requirements.txt
```

Chrome (or Chromium) must be installed; Selenium Manager downloads a matching
driver automatically.

## 2. Run

```bash
pytest                      # full suite + HTML report (reports/report.html)
pytest -m smoke             # fast sanity checks only
pytest test_07_blood_request_validation.py -v
SBL_HEADED=1 pytest         # watch the browser while tests run (Windows: $env:SBL_HEADED=1)
```

| Env var           | Default                                   | Purpose                                    |
| ----------------- | ----------------------------------------- | ------------------------------------------ |
| `SBL_BASE_URL`    | `https://smartbloodlink.fenric.uk/`       | Site under test                            |
| `SBL_HEADED`      | `0` (headless)                            | `1` shows the browser while tests run      |
| `SBL_WINDOW_SIZE` | `1440,900`                                | Browser viewport (colour checks assume it) |
| `SBL_SHOTS`       | `selenium_tests/screenshots`              | Where evidence screenshots are written     |

Every test writes its screenshot with the number documented in the test plan,
e.g. `screenshots/test_navigation_tabs_present_ss18.png`; a failing test adds a
`_FAIL` copy. `reports/report.html` is a self-contained pytest-html report.

## 3. Coverage matrix (plan → test)

| ID | Test case | File | Screenshot |
| -- | --------- | ---- | ---------- |
| 01 | `test_website_availability_and_title` | `test_01_availability_and_home.py` | 17 |
| 02 | `test_patient_portal_dashboard_rendered` | `test_01_availability_and_home.py` | 18 |
| 03 | `test_navigation_tabs_present` | `test_01_availability_and_home.py` | 18 |
| 04 | `test_navigate_to_request_tab` | `test_02_navigation_and_titles.py` | 20 |
| 05 | `test_navigate_to_tracking_tab` | `test_02_navigation_and_titles.py` | 19 |
| 06 | `test_navigate_to_blood_banks_tab` | `test_02_navigation_and_titles.py` | 22 |
| 07 | `test_navigate_back_to_home_tab` | `test_02_navigation_and_titles.py` | 18 |
| 08 | `test_quick_demo_login` | `test_03_auth_login_logout.py` | 17 |
| 09 | `test_donor_dashboard_loads` | `test_05_donor_workflows.py` | 23 |
| 10 | `test_donor_incoming_requests_tab` | `test_05_donor_workflows.py` | 21 |
| 11 | `test_donor_rewards_and_leaderboard` | `test_05_donor_workflows.py` | 26 |
| 12 | `test_donor_eligibility_checker` | `test_05_donor_workflows.py` | 28 |
| 13 | `test_blood_availability_map_loads` | `test_06_blood_search.py` | 22 |
| 14 | `test_blood_group_filter_selection` | `test_06_blood_search.py` | 22 |
| 15 | `test_blood_bank_navigation_tabs_active` | `test_06_blood_search.py` | 22 |
| 16 | `test_request_form_elements_displayed` | `test_07_blood_request_validation.py` | 20 |
| 17 | `test_blood_group_selection_chips` | `test_07_blood_request_validation.py` | 20 |
| 18 | `test_urgency_level_selection` | `test_07_blood_request_validation.py` | 20 |
| 19 | `test_hospital_workflow_and_dashboard` | `test_08_hospital_ambulance_admin.py` | 30 |
| 20 | `test_request_units_increment_decrement` | `test_07_blood_request_validation.py` | 20 |
| 21 | `test_request_address_field_visible` | `test_07_blood_request_validation.py` | 20 |
| 22 | `test_request_clinical_notes_field_visible` | `test_07_blood_request_validation.py` | 20 |
| 23 | `test_emergency_sos_request_details` | `test_05_donor_workflows.py` | 24 |
| 24 | `test_emergency_mission_hospital_details` | `test_05_donor_workflows.py` | 25 |
| 25 | `test_tracking_delivery_otp_visible` | `test_02_navigation_and_titles.py` | 19 |
| 26 | `test_hospital_stock_summary_visible` | `test_08_hospital_ambulance_admin.py` | 30 |
| 27 | `test_cold_chain_temperature_displayed` | `test_08_hospital_ambulance_admin.py` | 30 |
| 28 | `test_low_stock_alert_displayed` | `test_08_hospital_ambulance_admin.py` | 30 |
| 29 | `test_role_demo_shortcuts_visible` | `test_03_auth_login_logout.py` | 17 |

## 4. Files

```
selenium_tests/
├── conftest.py                          # driver / app / evidence fixtures
├── pytest.ini                           # markers + report output
├── utils/
│   ├── flutter_app.py                   # FlutterApp: the interaction layer
│   ├── session.py                       # demo login / logout / role switching
│   └── constants.py                     # URL, timeouts, screenshot map
├── test_01_availability_and_home.py     # cases 01–03
├── test_02_navigation_and_titles.py     # cases 04–07, 25
├── test_03_auth_login_logout.py         # cases 08, 29
├── test_05_donor_workflows.py           # cases 09–12, 23, 24
├── test_06_blood_search.py              # cases 13–15
├── test_07_blood_request_validation.py  # cases 16–18, 20–22
└── test_08_hospital_ambulance_admin.py  # cases 19, 26–28
```

Markers: `smoke`, `navigation`, `auth`, `donor`, `search`, `request`,
`hospital`, `read_only` (every test only inspects/toggles the UI — nothing is
submitted, no inventory, SOS or mission record is changed).

## 5. How the suite talks to a Flutter web app

The site is a Flutter Web build: the UI is painted into one graphics surface,
so ordinary Selenium locators find nothing. `utils/flutter_app.py` bridges that
gap:

1. **Accessibility tree on demand** — Flutter ships a hidden
   `flt-semantics-placeholder`; clicking it (via JS) makes Flutter publish the
   whole screen as `flt-semantics` DOM nodes. Their `innerText` / `aria-label`
   is what `app.text()` and `app.find()` read.
   *Some widgets (the demo shortcut chips) expose their name only through
   `aria-label`, which is why both are merged.*
2. **Trusted clicks, not `element.click()`** — Flutter nodes are
   `pointer-events: none`. Clicks are sent as Chrome DevTools Protocol
   `mousePressed`/`mouseReleased` events at the widget's viewport coordinates,
   so Flutter's own hit-testing receives them.
3. **Overlay-aware scrolling** — an app bar (≈56 px) and a fixed bottom
   navigation (≈76 px) sit above the scene. Before tapping, the widget is
   scrolled into the safe middle band (`_prepare`), otherwise the click
   silently lands on the navigation bar. Scrolling uses CDP `mouseWheel`
   events, because DOM scrolling never reaches Flutter.
4. **Colour-based "selected" state** — Flutter does not publish `selected`
   for these chips through ARIA, so the rendered pixel is sampled instead:
   a filled chip is saturated (`max(rgb)-min(rgb) > 60`), a pale one is not.
5. **Text fields** — Flutter mirrors the focused field into a hidden
   `<input>`; tests type with `ActionChains` and verify the field content
   through that input's `value`.
6. **Screens taller than the viewport** — Flutter only registers *visible*
   widgets, so `require_all()` scans the screen top-to-bottom and asserts the
   labels against the union of all frames (proving they belong to the same
   screen), then scrolls back to the top.

## 6. Read-only guarantees

* The request form is opened, toggled and typed into — **never submitted**
  (`Start Parallel Matching Search` is never clicked).
* Blood bank filters only change what is *displayed*.
* Donor/hospital flows only navigate and inspect; stock edits, dispatches and
  confirmations are out of scope for this plan. Reaching the mission screen
  (case 24) uses the demo-mode "Accept Emergency Call" shortcut, which only
  moves the local simulation forward.

## 7. Troubleshooting

| Symptom | Fix |
| --- | --- |
| `Flutter semantics tree could not be enabled` | The page never finished loading — check network/URL, or re-run. |
| `Could not tap ... stayed under an overlay` | The screen did not scroll; resize with `SBL_WINDOW_SIZE` (needs a viewport tall enough for the form). |
| Colour assertion fails intermittently | Use the default `1440,900` viewport and keep Chrome's GPU enabled (headless is fine). |
| Demo chips "missing" | They are on the login screen (`Profile → Sign Out`); the suite handles this automatically. |
| Driver/browser mismatch | `pip install -U selenium` lets Selenium Manager fetch the right driver. |
