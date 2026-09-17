# hoopsRN — Assets and data gaps

**Scope:** —
**Verified:** 2026-09-16 @ 8209408

The placeholder icon, the unmet licence obligation, and two scripts that can't
be re-run cleanly.

`Scope: —` because this is a narrative over the asset catalogue and the court
tooling, which `COURT_DATASET.md` and `BUILD_AND_CONFIG.md` own. It can't be
diffed, so it's re-read by hand every pass.

---

## The app ships with a placeholder icon

`AppIcon.appiconset` declares 14 image slots and contains **no images**;
`AccentColor.colorset` has no colour defined. Nothing is broken by this, and
nothing will flag it — it just ships looking unfinished.

---

## The ODbL attribution is decoded and then discarded

The attribution string is decoded into `CourtDataset` and then **dropped** —
`CourtService` keeps only `courts`, and there is no `attribution` property
anywhere to display. **That is a licence obligation currently unmet**, and
closing it means holding the value as well as rendering it.

*(This entry claimed the string was "loaded into `CourtService.attribution`"
until 2026-08-21. No such property has ever existed. `CourtService` now
publishes `loadError`, but still keeps no `attribution`.)*

---

## Two scripts that can't be re-run as-is

- **`tools/build_courts.py` can't be re-run at all**: its inputs
  (`raw_triangle.json`, `sites_raw.json`) aren't in the repo.
- **`location-decoder-script/reverseGeocode.js` writes into the app bundle** —
  its output path is `hoopr/Resources/courts_updated.json`, inside the bundled
  directory. The stale copy that sat there unloaded has been deleted, but
  re-running the script puts it straight back in.

---

## Coverage is a data problem, not a location one

`homeLocation` follows the device as of 2026-08-27, so distances are no longer
anchored to a fixed Durham point. The consequence worth knowing: **the dataset
is six Triangle cities**, so a user outside it now correctly sees an empty map
rather than a wrong one. Widening that is `../plans/SCALE_UP.md`'s subject, not
a bug in location.

*(Fixed 2026-08-21: a court-dataset load failure used to be completely silent.
`CourtService` publishes `loadError`, `FindAMatchViewModel` mirrors it as
`datasetError`, and the map's empty state reports "Court data unavailable"
ahead of any per-tab wording. Still no retry, deliberately — the dataset ships
in the app bundle, so a failure is a build problem rather than a transient
one.)*

---

## See also

- `../COURT_DATASET.md` — where courts come from and how to regenerate them.
- `../plans/SCALE_UP.md` — court-data delivery for more than six cities.
