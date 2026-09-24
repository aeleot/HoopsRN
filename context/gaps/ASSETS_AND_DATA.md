# hoopsRN — Assets and data gaps

**Scope:** —
**Verified:** 2026-09-20 @ 349d309

The empty accent colour, two scripts that can't be re-run cleanly, and a
dataset that covers six cities.

`Scope: —` because this is a narrative over the asset catalogue and the court
tooling, which `COURT_DATASET.md` and `BUILD_AND_CONFIG.md` own. It can't be
diffed, so it's re-read by hand every pass.

---

## `AccentColor.colorset` has no colour defined

Cosmetic: nothing in the app reads it, because every colour comes from
`Theme.swift`. (The app icon it used to sit beside shipped 2026-09-20 — see
`BUILD_AND_CONFIG.md`.)

---

## The ODbL notice is on the tab, not on the court card

`CourtService.attribution` holds the dataset's own notice and the map sheet
shows it at the foot of every court list and in the empty state, linked to
OpenStreetMap's copyright page. It is not on the court detail card — one
findable notice on the tab is the usual standard — which is the one place a
stricter reading of ODbL §4.3 could ask for more.

---

## Two scripts that can't be re-run as-is

- **`tools/build_courts.py` can't be re-run at all**: its inputs
  (`raw_triangle.json`, `sites_raw.json`) aren't in the repo.
- **`location-decoder-script/reverseGeocode.js` writes into the app bundle** —
  its output path is `hoopr/Resources/courts_updated.json`, inside the bundled
  directory. Re-running the script puts an unloaded stray copy there.

---

## Coverage is a data problem, not a location one

`homeLocation` follows the device, so **the dataset is the limit: six Triangle
cities**. A user outside them correctly sees an empty map rather than a wrong
one. Widening that is `../plans/SCALE_UP.md`'s subject.

A dataset load failure is reported ("Court data unavailable") with no retry,
deliberately — the dataset ships in the bundle, so a failure is a build
problem rather than a transient one.

---

## See also

- `../COURT_DATASET.md` — where courts come from and how to regenerate them.
- `../plans/SCALE_UP.md` — court-data delivery for more than six cities.
