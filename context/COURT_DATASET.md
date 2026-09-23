# hoopsRN — Court Dataset

**Scope:** `hoopr/Resources/`, `tools/build_courts.py`, `tools/courts_common.py`,
`tools/fetch_city_courts.py`, `tools/assign_facilities.py`,
`tools/audit_courts.py`, `tools/facility_overrides.json`,
`tools/fetch_official_courts.py`, `tools/enrich_courts.py`,
`tools/official_sources/`, `tools/verify_worklist.json`,
`location-decoder-script/`
**Verified:** 2026-09-22 @ 8a35e9d

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
| `version` | **3** — `facilityId` (v2) then per-field `provenance` (v3), both 2026-09-22 |
| `generated` | 2026-08-06 |
| `attribution` | OSM/ODbL **plus four municipal sources** — see Provenance below |
| `sources` | five harvested layers, with URL, grain and fetch date |
| `cities` | Apex, Cary, Chapel Hill, Durham, Morrisville, Raleigh |
| courts | **214** |
| facilities | **191** — 22 of them holding more than one surface |
| addresses with a street line | **90** (was 0) |

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

## Courts and facilities

A **court** is one playing surface. A **facility** is the place a player travels
to. OSM tags each surface as its own way, so one park arrives as several courts —
Long Meadow Park as three records 17m apart.

Ungrouped, that cost two things. The map drew three pins on top of each other.
And because `Game.courtId` and `MatchTicket.courtIds` key on the *court*, one
physical court held **three separate queues**, none able to see the others — two
players on the same asphalt, invisible to each other. That's what `facilityId`
exists to fix.

`facilityId` is **derived, and carries no durability obligation.** Games still
store `courtId`; the facility is applied when games are *read*
(`FindAMatchViewModel.gamesByFacility`). Nothing in Firestore references a
facility, so unlike a court ID — which `courts_common.NAMESPACE` keeps stable
because stored documents point at it — a facility ID can be re-minted whenever
the grouping improves. That is what makes `assign_facilities.py` safe to re-run.

**`tools/assign_facilities.py`** stamps it. Courts within **80m** become one
facility (union-find over pairwise distance), and the ID is `uuid5` over the
group's *canonical* member — the smallest OSM ref — under a `facility/` prefix, so
adding a surface doesn't renumber the facility and a facility ID can never
collide with a court ID.

```bash
python3 tools/assign_facilities.py --dry-run
python3 tools/assign_facilities.py
```

Idempotent, and lossless: it preserves every existing field and rewrites only
`facilityId` and `version`.

80m rather than 60 because the three groups in that band are unambiguous — two
records *identically named* "Davis Drive Elementary School" 71m apart, "Jeffreys
Grove Elementary School #1/#2", and Halifax Park's two outdoor courts. Widening
gained those and split nothing. **A threshold is wrong the moment it merges two
names a player would read as different places**, which is the test to apply
before raising it again.

The grouping is written into the file rather than computed at launch so a human
can override it: `tools/facility_overrides.json` holds `merge` (force courts
together at any distance) and `split` (force one out). A court in both loses —
split wins, because a wrongly-merged facility silently pools two parks' queues
while a wrongly-split one only shows two pins. Both lists are currently empty.

## Provenance, and the one rule that governs it

Since 2026-09-22 the dataset is a **conflation of five sources, not one**, and
every value written by a source other than the original OSM extract carries its
origin in a per-court `provenance` map:

```json
"provenance": { "address": "durham_parks", "isLit": "raleigh_courts" }
```

**The rule: a park-level source may never set an amenity.** Official data comes at
two grains:

- **court-level** — `raleigh_courts` (Raleigh PRCR publishes a row per playing
  surface) and `osm` (a way per court). Its `Lighting` is a claim about *that
  court*.
- **park-level** — `wake_parks`, `durham_parks`, `chapelhill_facilities`,
  `raleigh_park_bounds`. A row is a whole park, so **its lights may be on the
  ballfield.**

Durham publishes `LIGHTS` for 26 basketball parks, and applying it would lift
`isLit` coverage from 9.8% to roughly 40%. It is refused anyway: a court shown as
lit that is dark at 7pm costs a player a wasted trip, while a court that admits it
doesn't know costs them nothing. Park-level lighting claims become a
**verification worklist** instead of data.

That asymmetry is the product decision behind this whole layer, and it's enforced
in three places so it can't quietly rot: `enrich_courts.py` won't write it,
`audit_courts.py` fails if a park-level source ever appears against an amenity,
and `FacilityTests` asserts it against the shipped file.

`osm` is allowed because its *grain* is one court — but it's the tier most likely
to be stale (a volunteer's `lit=yes` from some year), so the 11 courts we show as
lit on an OSM tag alone are on the worklist too, at the top.

### Regenerating the conflation

```bash
python3 tools/fetch_official_courts.py     # harvest -> tools/official_sources/
python3 tools/enrich_courts.py --dry-run   # report what would change
python3 tools/enrich_courts.py             # write courts.json + verify_worklist.json
```

`tools/official_sources/` is a **committed snapshot**: a dataset build has to be
reproducible, these are other people's servers, and a provenance claim is only
checkable if the response behind it was kept. It lives in `tools/`, not
`hoopr/Resources/` — that directory is a synchronized Xcode group, so anything
left there ships.

`tools/verify_worklist.json` is the output for human fieldwork: **35 checks across
26 facilities**, each with the court ID, facility ID, name, street address, the
claim, who claimed it, and why we didn't believe it. After checking one on site,
set the value in `courts.json` and mark its provenance `verified-onsite` — the one
source that outranks everything.

`enrich_courts.py` never overwrites a value it disagrees with. A conflict between
us and an official court-level source is reported and added to the worklist, and
for `isLit` **we deliberately keep the more pessimistic value** — taking their
`true` over our `false` is the one direction that can strand somebody at a dark
court.

## Auditing

**`tools/audit_courts.py`** reports what a null-check can't see. Every field in
`courts.json` is *populated* while some carry almost no information, so a
completeness check calls this dataset clean:

```bash
python3 tools/audit_courts.py           # summary
python3 tools/audit_courts.py --verbose # every affected record
python3 tools/audit_courts.py --json    # for CI; exits 1 on any finding
```

Read-only — it never writes the dataset. What it currently reports, all of it
Phase 1 work that `../plans/` should pick up:

- **`address` carries no street line for 124 of 214 records** — down from all 214
  before the 2026-09-22 conflation, which supplied 90 real street addresses. The
  remainder are courts in no official park layer (schools, apartments, and the
  towns that publish nothing). Shown by `CreateGameSheet` and handed to
  `MKAddress` by `MapTab.openDirections`.
- **Amenity coverage is still thin**: `isCovered` 10.7%, `isLit` 17.8%, `hoops`
  18.2%, `surface` 34.6% — up from 0.9 / 9.8 / 18.2 / 31.3, and every gain is
  court-level or better by construction. `CourtBadges` only emits a badge on a
  truthy value, so an *unknown* `isLit` still renders identically to a court known
  to have no lights. **`hoops` did not move**: no source publishes a hoop count,
  so it is the field only a person on the court can answer.
- **37% of names are generic** (`"Apex Basketball Court #7"` → `"Apex #7"`).
- ~~Davis Drive Elementary School's two surfaces disagree about their city~~ —
  **fixed 2026-09-22**: Wake County's `JURISDICTION` settled both on Cary.
- 38 courts carry a city that isn't their nearest known centre, because
  `courts_common.CITIES` assigns across **13** cities while the dataset ships
  **6**: a court nearest Holly Springs was labeled Apex.

Its `SAME_FACILITY_M` must match `assign_facilities.DEFAULT_THRESHOLD_M` — it
reports the clusters that one is expected to have grouped, so a disagreement
reads as a bug in the assigner rather than two tools with different opinions.

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
- **Facility IDs are the opposite**: derived, re-mintable, and referenced by
  nothing outside the client. Don't store one in Firestore — the moment a
  document points at a facility, re-running `assign_facilities.py` stops being
  safe.
- Every court has a `facilityId`, and a court on its own is a facility of one.
  `Court.init(from:)` falls back to the court's own `id` when the field is absent,
  so a pre-v2 hosted dataset still decodes rather than taking the map down.
- No facility ID may collide with a court ID — the `facility/` seed prefix is what
  guarantees it, and `FacilityTests` asserts it against the real file.
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
