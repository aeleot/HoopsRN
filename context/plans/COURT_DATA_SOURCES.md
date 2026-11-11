# Plan — Better Court Data for the Triangle

**Status:** proposed, not started. Source survey completed 2026-09-22.
**Drafted:** 2026-09-22 @ queue-system
**Touches:** `tools/`, `hoopr/Resources/`, `hoopr/Models/Court.swift`,
`context/COURT_DATASET.md`

> `context/plans/` carries no `Scope`/`Verified` stamp. A plan describes work that
> hasn't happened.

**Decision recorded 2026-09-22:** no public API (see `COURT_DATA_PLATFORM.md` §4,
now closed). The goal is **the most accurate court tracker for the Triangle plus
~30 miles**, expanding outward later. This file is the survey of what data exists
to make that true, and it is a *reference* as much as a plan — the endpoints and
field names below are the expensive part to rediscover.

---

## 1. Are we achieving it today? No — measured

| | |
|---|---|
| OSM basketball features within 30mi of the Triangle centre | **343** |
| what we ship | **214** |
| **missing from the target area** | **129 (38%)** |
| our courts with a real street address | **0 of 214** |
| our courts corroborated by any official source | **77 (35%)** |
| Raleigh city-park courts in the official record with no match in ours | **~34** |

Amenity coverage, from `tools/audit_courts.py`: `isCovered` 0.9%, `isLit` 9.8%,
`hoops` 18.2%, `surface` 31.3%.

**The ceiling isn't OSM's completeness — it's that we only use one source.**
Four authoritative ones exist, all free, and three of them carry exactly the
fields we're missing.

---

## 2. The sources

### 2.1 Raleigh PRCR — Athletic Courts ★ best quality

**Court-level polygons**, published by Raleigh Parks, Recreation and Cultural
Resources — the department that owns the courts.

```
https://services.arcgis.com/v400IkDOw1ad7Yad/arcgis/rest/services/
  Raleigh_Parks_Athletic_Courts_and_Fields/FeatureServer/0
```
Filter: `Basketball NOT IN ('No','') AND Basketball IS NOT NULL` → **61 records.**

| field | maps to | coverage |
|---|---|---|
| `Lighting` (Yes/No) | `isLit` | **58/61 (95%)** vs our 9.8% |
| `IndoorOutdoor` (Outdoor Uncovered / Outdoor Covered) | `isCovered` | **61/61 (100%)** — 2 covered |
| `Surface` (asphalt, Sports Court Tile) | `surface` | 26/61 (43%) |
| `LocationName` / `Title` | `name` | 61/61, official |
| `Status` (Existing) | *nothing yet* | **a court being closed is unrepresentable in our model** |
| `Basketball` (Yes / fullcourt) | hints at `hoops` | 61/61 |

Also in the same org: `Raleigh_Park_Amenities/FeatureServer/0` (134 parks, 87
fields, `BASKETBALL` as 0/1 — 48 parks positive) and
`Raleigh_Park_Centers_(public)`, `Raleigh_Park_Playgrounds`,
`Raleigh_Park_Assets_(new)`.

### 2.2 Wake County Parks ★ best coverage

**Park-level, every jurisdiction in Wake** — Raleigh, Cary, Apex, Morrisville,
Wake Forest, Fuquay-Varina, Garner, Knightdale, Holly Springs, Rolesville,
Wendell, Zebulon, and unincorporated county. This is most of the 30-mile ring in
one layer.

```
https://services1.arcgis.com/a7CWfuGP5ZnLYE7I/arcgis/rest/services/
  Wake_Parks_Public/FeatureServer/0
```
Filter: `OUTDOORBASKETBALL='Yes'` → **75 of 263 parks.**

| field | why it matters |
|---|---|
| `OUTDOORBASKETBALL` (Yes/No) | answered for **all 263** — a court-exists check |
| `ADDRESS` + `Address2` | **real street addresses with ZIP** — we have none |
| `JURISDICTION` | **authoritative city**, which kills the nearest-centroid guess that currently mislabels 38/214 |
| `NAME`, `ALIAS1`, `ALIAS2` | official name *and aliases* — aliases make matching far easier |
| `GYM` | indoor courts, a category we don't model |
| `URL`, `PHONE`, `Lat`, `Lon`, `Notes`, `RESTROOMS` | |

### 2.3 Durham Parks

**Park-level**, City of Durham.

```
https://webgis2.durhamnc.gov/server/rest/services/PublicServices/
  Community/MapServer/8          (Parks — 76 records)
  Community/MapServer/7          (Recreation and Aquatics Centers)
```
Filter: `BASKETBALL='Yes'` → **26 parks.** Carries `FULLADDR`, `LIGHTS`,
`RESTROOM`, `PARKURL`, `PARKACRES`, `ADACOMPLY`.

Sanity check that it's the real thing: it returns *Long Meadow Park, 917 Liberty
St* and *C. R. Wood Park, 417 Commonwealth St* — both facilities the 2026-09-22
facility grouping had already merged from split OSM ways.

### 2.4 Chapel Hill — addresses only

```
https://services2.arcgis.com/7KRXAKALbBGlCW77/arcgis/rest/services/
  Parks_and_Recreation_Facilities/FeatureServer/0
```
28 facilities, **28 of 28 with a street address** (`Facility_Address`), plus
official `Facility_Name` and `Season_of_Operation`.

**But zero records name basketball.** Its feature fields go only as specific as
"Athletic fields/courts" (6) and "Gymnasium" (4). Useful for names and addresses,
useless for amenity truth.

### 2.5 What we did *not* find — the honest negatives

- **Cary publishes no basketball field at all.** Its open data portal
  (`data.townofcary.org`, OpenDataSoft) has a park feature layer with flags for
  `soccer`, `skatepark`, `dogpark`, `discgolf`, `playground`, `naturetrail`,
  `lake`, `restroom` — and no basketball. Searching every Cary dataset for
  "basketball" returns 0 records. Cary's ArcGIS `ParkEquipmentAndSigns_PublicView`
  exposes only `OBJECTID` publicly. **Cary is our worst-covered town and Wake
  County's layer is the only official source for it.**
- **Apex / Morrisville**: park boundaries and names only, no amenity inventory.
- **No hoop-count source.** Raleigh's joint-use layer has exactly the right
  schema — `BASKETBALL_OUTDOOR_HALF` / `BASKETBALL_OUTDOOR_FULL` — but it's
  populated for only 10 school sites and is almost all zeros. `hoops` stays the
  field only a person standing on the court can answer.
- **WCPSS Joint Use Agreements** (`prcr_wcpss_juas/FeatureServer`, 10 sites)
  names school properties legally open to the public — Athens Drive, Broughton,
  Carroll Middle, Sanderson, and 6 more. Small, but it's *evidence* for an
  `access` value we currently infer from whether the court's name contains
  "school".

---

## 3. What integrating them actually buys — measured

Matched by distance against the current 214 courts:

| win | count | confidence |
|---|---|---|
| courts that could take a **real street address** | **76** | high (park containment) |
| unknown `isLit` → known, from Raleigh **court-level** | **31** | **high — it's a fact about the court** |
| unknown `isLit` → known, from Durham **park-level** | 36 | **lower — see §4** |
| unknown `surface` → known, from Raleigh | 12 | high |
| official basketball parks with **no court in our dataset** | **35** | a work queue, with names and addresses attached |
| courts whose city can be set from `JURISDICTION` | all Wake | authoritative |

Of our 53 Raleigh courts, 29 don't match Raleigh PRCR — and **22 of those 29 are
`school` (12) or `restricted` (10)**, which is exactly what a city-parks
department wouldn't publish. Only 7 are public courts PRCR doesn't know about.
That breakdown is the evidence the matching is working rather than silently
failing. Match counts are stable from 100m to 400m (22→25), so they aren't an
artifact of the radius.

---

## 4. The distinction that has to survive into the schema

**Raleigh is court-level. Wake and Durham are park-level.** These are not the
same kind of claim:

- Raleigh says *this court has lights*. That is a fact about the court.
- Durham says *this park has basketball, and this park has lights*. **The lights
  may be on the ballfield.** Applying it to the basketball court is an
  inference.

Collapsing both into `isLit = true` would make the dataset look 40% covered while
quietly mixing facts with guesses — which is a worse failure than the honest
9.8% we have now, because it can't be audited afterwards.

So each field needs **provenance and confidence**, not just a value. That is the
same overlay `DATA_MODEL.md` already records as needed (`Bool?` can't say
"unknown"), arriving with a second source class beyond player reports:

```
official-court-level  >  official-park-level  >  player-reported  >  OSM  >  unknown
```

Getting this right is what makes "most accurate court tracker" a defensible claim
rather than a marketing line — you can say *why* you believe each fact.

---

## 5. Proposed work

**Phase 1 — harvest.** `tools/fetch_official_courts.py` pulling the four sources
in §2 into a cached local snapshot (they're small; Wake is 263 records). Commit
the snapshot so builds are reproducible and the endpoints aren't hit per build.

**Phase 2 — conflate.** For each OSM court: point-in-polygon into the official
park polygon, inherit `name` / `address` / `city` from it. Separately, match
Raleigh's court polygons court-to-court for `surface` / `isLit` / `isCovered`.
Write provenance per field (§4). Facility grouping from `assign_facilities.py`
runs after, and official park identity should *inform* grouping — a park boundary
is better evidence than an 80m radius.

**Phase 3 — close the coverage gap.** Two queues:
- the **129** OSM courts in the 30-mile ring we don't ship — mostly a matter of
  running the pipeline over the wider area;
- the **35** official basketball parks with no court record at all — these need a
  court located within the park, and they come with a name and address already.

**Phase 4 — model what we're currently unable to say.** `Status` (a closed
court), `GYM` (indoor), and `access` backed by joint-use evidence rather than a
name-string heuristic.

**Phase 5 — contribute back.** Courts found via official data and absent from OSM
can be added to OSM. Improves the upstream everyone uses, and it's the right
posture given we depend on it.

---

## 6. Licensing

These are US government open-data publications, which is a far friendlier footing
than ODbL — Raleigh publishes under an "Open Raleigh Data Policy", and the others
carry their own terms. **Confirm each source's terms and attribution requirement
before shipping**, and record them next to the data the way `attribution` already
travels in `CourtDataset`.

One interaction worth flagging: merging official data *into* the OSM-derived
database could extend ODbL share-alike over the combination. Keeping official and
player-contributed facts in a **separate overlay keyed by court ID** — which §4
wants anyway for provenance reasons — also keeps that boundary clean. The
engineering reason and the licensing reason point the same way.

*Not legal advice; worth a review before launch.*

## Open questions

- **Cary.** Its town data has no basketball at all, so Wake County's park-level
  layer is the only official source. Is that good enough for a launch city, or
  does Cary need manual survey?
- **Match radius for park containment.** Point-in-polygon is cleaner than the
  400m proximity used for the §3 estimate; the real numbers will shift somewhat.
- **Refresh cadence.** These layers change slowly. Quarterly? And what detects a
  court that has been removed?
- **Who wins on conflict** when Raleigh says asphalt and a player says concrete?

## See also

- `COURT_DATA_PLATFORM.md` — the statewide/API analysis; its §4 is closed by the
  no-API decision, its §2 ingest findings still stand.
- `../COURT_DATASET.md` — the current pipeline.
- `../DATA_MODEL.md` — why `Bool?` can't express "unknown".
- `../gaps/ASSETS_AND_DATA.md` — the unmet ODbL attribution obligation.
