# hoopsRN — Court Dataset

**Scope:** `hoopr/Resources/`, `tools/build_courts.py`, `tools/courts_common.py`,
`tools/fetch_city_courts.py`, `location-decoder-script/`
**Verified:** 2026-08-21 @ 9a81cc2

Where courts come from, how they get into the app, and how to add a city. Read
this before changing court data or wondering why there's no network call for it.

---

## Why bundled, not fetched

Courts ship as a curated JSON file in the app bundle rather than being queried
at runtime. The map is populated instantly, works offline, and doesn't depend on
the volunteer-run Overpass API, which intermittently times out and rate-limits.
An earlier live-query implementation was removed for exactly that reason —
`tools/fetch_city_courts.py` still references the mirror list "CourtSearchService
used to try."

Live game state will layer on top of this at runtime, joined by `Court.id`.

## Current dataset

`hoopr/Resources/courts.json`:

| | |
|---|---|
| `version` | 1 |
| `generated` | 2026-08-06 |
| `attribution` | `Court data © OpenStreetMap contributors, ODbL 1.0` |
| `cities` | Apex, Cary, Chapel Hill, Durham, Morrisville, Raleigh |
| courts | **214** — Durham 55, Raleigh 53, Chapel Hill 43, Cary 26, Apex 22, Morrisville 15 |

`CourtService` hardcodes the resource name `"courts"`, decodes the whole file
into `CourtDataset` in `init()`, and sorts by name.

**A load failure is invisible.** Missing from the bundle or undecodable, it is
logged through `os.Logger` and leaves `courts` empty — there is no published
error, no retry, and no fallback file, so the symptom is a map with no pins and
a nearby list that reads as "none in range". Nothing in the UI can tell that
apart from a genuinely empty result.

The envelope's `version` and `attribution` are decoded into `CourtDataset` and
then **discarded** — `CourtService` keeps only `courts`. `version` is logged
once at load; `attribution` is read by nothing, which is the licence obligation
`GAPS.md` records.

The Xcode target uses `PBXFileSystemSynchronizedRootGroup`, so **anything
dropped into `hoopr/` is bundled automatically** — no pbxproj edit needed, and
also no way to exclude a file by leaving it out of a build phase.

## Regeneration

**`tools/build_courts.py`** — the original bulk build. Reads two local
Overpass extract files (`raw_triangle.json` for basketball features,
`sites_raw.json` for named parks/schools), then filters, dedupes, names, and
classifies. Neither input file is in the repo, so this script is not re-runnable
as-is. Notable logic: courts are assigned to whichever of 13 Triangle city
centres is nearest; `EXCLUDE_LEISURE` drops stadiums and sports centres (real
basketball, but no pickup); `EXCLUDE_ACCESS` drops `private`/`customers`/
`permit`/`no`; generic names get resolved against a nearby named site. Its
`LAUNCH_CITIES` is still `{"Durham", "Raleigh"}` — the other four cities in the
current file were added afterwards by the script below.

**`tools/fetch_city_courts.py`** — the one to use now. Hits Overpass live for a
single city and appends into `courts.json` in place:

```bash
python3 tools/fetch_city_courts.py Cary
python3 tools/fetch_city_courts.py Morrisville --radius-miles 6
python3 tools/fetch_city_courts.py Apex --dry-run
```

One HTTP request per run (courts and label sites unioned in a single query),
tried against three Overpass mirrors in turn. It merges by ID, skips courts
already present, re-sorts by `(city, name)`, adds the city to `cities`, and
stamps `generated` with today's date. It does **not** bump `version` — do that
by hand if the schema changes.

Both scripts share `NAMESPACE = 6f2a1c4e-9b3d-4f70-8a21-5c0d7e8b1234` and mint
IDs as `uuid5` over the OSM type/id, so the same real-world court gets the same
ID across scripts and re-fetches. Don't change the namespace.

**`location-decoder-script/reverseGeocode.js`** — a Node one-off that reverse-
geocodes coordinates through Nominatim to improve names and addresses (1 req/sec,
retry with backoff, resumable). It reads `courts.json` and writes
`courts_updated.json`. It is **not** part of the current pipeline: its output is
a flat array with `"lat,lon"` string IDs, which `CourtDataset` cannot decode.
That output was committed and bundled for a while without ever being loaded; it
has since been deleted, so `hoopr/Resources/` holds `courts.json` and nothing
else. Its `OUTPUT_FILE` is `hoopr/Resources/courts_updated.json` — it writes
straight into the bundled directory, so re-running it re-creates a shipped file.
Move the output elsewhere or delete it afterwards. `node_modules/` exists at
the repo root but is gitignored; run `npm install` in `location-decoder-script/`
if you ever need this script.

---

## Invariants

- Court IDs are `uuid5(NAMESPACE, "<osmType>/<osmId>")`. Never re-mint them, and
  never derive an ID from coordinates.
- `courts.json` must stay a `CourtDataset` envelope (`version`, `generated`,
  `attribution`, `cities`, `courts`), not a bare array — `CourtService` decodes
  the envelope.
- `CourtService` looks for the resource named exactly `courts`. Renaming the
  file breaks the map silently at runtime, not at compile time.
- The ODbL attribution string travels with the data and must survive any
  regeneration.
- `hoopr/Resources/` holds exactly the files meant to ship. The target uses a
  synchronized group, so a scratch file left there is a bundled file.

## See also

- `DATA_MODEL.md` — the `Court` and `CourtDataset` contracts.
- `MAP_LAYER.md` — what consumes the loaded courts.
- `GAPS.md` — the unshown ODbL attribution, and the un-rerunnable bulk build.
