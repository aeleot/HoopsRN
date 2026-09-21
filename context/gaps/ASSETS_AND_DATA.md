# hoopsRN — Assets and data gaps

**Scope:** —
**Verified:** 2026-09-16 @ 8209408

The missing accent colour, the unmet licence obligation, and two scripts that
can't be re-run cleanly.

`Scope: —` because this is a narrative over the asset catalogue and the court
tooling, which `COURT_DATASET.md` and `BUILD_AND_CONFIG.md` own. It can't be
diffed, so it's re-read by hand every pass.

---

## ~~The app ships with a placeholder icon~~ — fixed 2026-09-20

`AppIcon.appiconset` now carries three 1024×1024 images; `BUILD_AND_CONFIG.md`
has what they are and how to re-render them.

**This entry was wrong about the stakes, not just out of date.** It said
"nothing is broken by this, and nothing will flag it — it just ships looking
unfinished". An app with no 1024×1024 icon is rejected by App Store Connect at
processing, before review ever sees it. It was never a cosmetic item; it was a
hard submission blocker filed as a nice-to-have. Recorded here so the next
"nothing will flag it" gets checked rather than believed.

**`AccentColor.colorset` still has no colour defined**, and that part *is*
cosmetic: nothing in the app reads it, because every colour comes from
`Theme.swift`.

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
