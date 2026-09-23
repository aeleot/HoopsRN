# Plan — Statewide Court Data, and the API Question

**Status:** proposed, not started
**Drafted:** 2026-09-22 @ queue-system (facility layer)
**Touches:** `tools/`, `hoopr/Resources/`, `hoopr/Services/CourtService.swift`,
`hoopr/Models/Court.swift`, `firebase.json`, `context/COURT_DATASET.md`

> `context/plans/` is not a dictionary entry and carries no `Scope`/`Verified`
> stamp. A plan describes work that hasn't happened; the dictionary describes
> code that has. When a phase below ships, fold what's true into the entries in
> "Documentation debt" and strike it from here.

Two questions, one subject: **what does it take to cover all of North Carolina,
and could the data we collect become an API of our own?**

## Relationship to `SCALE_UP.md`

`SCALE_UP.md` §2 already owns **delivery** — moving off a single bundled file
onto per-region files on Firebase Hosting with a `version` check. That design is
still right and is not restated here.

This plan owns the two things §2 doesn't: **how the data gets produced** at state
scale, and **whether to publish it**. Where they touch, §2 wins on delivery and
this file wins on ingest. A decision recorded in both places is two decisions
that drift.

---

## 1. The measurement that reframes the problem

Asked Overpass for every basketball feature in North Carolina on 2026-09-22,
using the same tag filters as `tools/fetch_city_courts.py`:

| | |
|---|---|
| nodes | 48 |
| ways | 1,712 |
| relations | 4 |
| **total** | **1,764** |

Against today's 214 courts / 96KB / 15.8KB gzipped, that projects to:

| | raw | gzipped | facilities |
|---|---|---|---|
| all 1,764 features | ~795 KB | ~131 KB | ~1,570 |
| after access/leisure filters (~85%) | ~676 KB | ~111 KB | ~1,340 |

**So statewide is about 8× the current dataset and still under a megabyte.**

That kills the most intuitive reason to re-architect. A 795KB JSON file in the
app bundle is smaller than a single App Store screenshot; `CourtService` decodes
it synchronously at launch today and 8× that is still milliseconds. **Bundling
survives statewide North Carolina comfortably.** `SCALE_UP.md` §2 has been
amended to say so.

What actually breaks at state scale is everything *upstream* of the file, plus
one thing downstream that has nothing to do with size.

---

## 2. What genuinely breaks

### 2.1 The ingest pipeline is the wrong shape

`fetch_city_courts.py` issues one Overpass query per city, around a hand-entered
centroid, against a **volunteer-run API** that `COURT_DATASET.md` already records
as intermittently timing out and rate-limiting. North Carolina has 500+
incorporated municipalities. That is 500+ queries against infrastructure donated
by other people, to assemble something they publish in bulk for free.

**Use the Geofabrik state extract instead.** Verified available and current:

```
https://download.geofabrik.de/north-america/us/north-carolina-latest.osm.pbf
→ north-carolina-260922.osm.pbf, 429 MB, rebuilt daily
```

One download, processed offline, repeatable, no rate limits, no politeness
budget, and it pins the exact snapshot a dataset was built from — which is
provenance the current pipeline doesn't have. `build_courts.py` already expects
local extract files (`raw_triangle.json`, `sites_raw.json`, neither in the repo);
this is that design done properly, with an input anyone can re-fetch.

Overpass stays the right tool for what it's good at: a single city, a spot check,
a count like §1's. It is the wrong tool for a state.

### 2.2 Nearest-centroid city assignment is already failing

`tools/audit_courts.py` reports **38 of 214 courts (17.8%) carry a city that
isn't their nearest known centre** — because `courts_common.CITIES` assigns
across 13 cities while the dataset ships 6. A court nearest Holly Springs, which
doesn't ship, gets labeled Apex. That's live today, in six cities.

At state scale a centroid model is indefensible: real municipal boundaries are
not Voronoi cells, and NC is full of doughnut annexations and adjacent
towns. Two courts 71m apart at one school already ship as Cary *and*
Morrisville.

**Fix: point-in-polygon against real boundaries** — OSM `admin_level=8` place
boundaries (already in the extract you just downloaded, so no new source) or
Census TIGER/Line places. Assign a court to the polygon that contains it, with
nearest-centroid kept only as the fallback for a court in unincorporated county
land. This also resolves the Davis Drive conflict at the source rather than
papering over it with `Facility.city`.

### 2.3 "Region" and "city" have to become different fields

`SCALE_UP.md` §1 denormalizes `Court.city` onto `games` as `region` and scopes
the public-runs query by it. That works for six Triangle cities. Statewide it
breaks in two directions at once:

- **Too fine.** Hundreds of regions, nearly all with zero activity. A user in
  Carrboro sees no runs because everything is filed under Chapel Hill.
- **Boundary blindness.** An equality filter on region means a user 500m from a
  city line is invisible to the runs nearest them.

**A region must be a metro, not a municipality** — CBSA-sized (Triangle,
Charlotte, Triad, Asheville, Wilmington). `city` stays for display; `region`
becomes a coarse query key with maybe a dozen values statewide. Both get
denormalized onto a game at write time. Getting this wrong is expensive later:
`region` is immutable on existing documents, so changing its grain is a
migration.

**This is a decision `SCALE_UP.md` §1 should absorb before it ships**, not
after — it's the same field, and §1 currently specifies `Field.region: court.city`.

### 2.4 Release cadence — the real case for hosted delivery

Not size. Adding a city means an App Store review cycle. Six cities over a
development season is fine; "can you add my town" at statewide scale is not.

That is the argument for `SCALE_UP.md` §2, and it stands on its own — it just
isn't a size argument, and shouldn't be sold as one.

### 2.5 Coverage becomes a product problem

Most NC counties will have a handful of courts, many untagged in OSM. A rural
user gets a near-empty map — correctly, per `gaps/ASSETS_AND_DATA.md`, but
correctly-empty and useless are the same experience. Statewide coverage converts
the amenity gap `DATA_MODEL.md` now records (`isCovered` 0.9%, `isLit` 9.8%,
`hoops` 18.2%, `surface` 31.3%) from a Triangle annoyance into the main thing
standing between a new user and value.

**Widening coverage and deepening it are the same project**, and the second one
is what the API question below actually turns on.

---

## 3. Recommended sequence for statewide

**Phase A — rebuild ingest, ship statewide bundled.** Geofabrik extract,
point-in-polygon city assignment, existing filter/label/facility logic reused
unchanged, `assign_facilities.py` run over the result. Keep it in the app bundle:
§1 says it fits. No hosting, no new infrastructure, no Blaze.

**Phase B — split `region` from `city`** and land it in `SCALE_UP.md` §1's
denormalization before that ships.

**Phase C — hosted delivery per `SCALE_UP.md` §2**, when release cadence starts
hurting — realistically when expanding past NC, not within it.

Phase A is most of the value and touches no runtime code beyond a bigger file.

---

## 4. The API question — CLOSED 2026-09-22: no API

**Decided against, by the product owner, after reading this section.** The plan is
to launch on the Triangle plus ~30 miles and expand outward slowly, competing on
*accuracy* rather than on distribution. §4.2 and §4.6 below are the reasoning that
held: the OSM half is a commodity you'd be obliged to give away, so an API is
effort spent on the least defensible asset.

What survives this decision and is still worth doing:

- **§4.1's attribution fix stays blocking** — it's a licence obligation on the
  app itself, not on any API.
- **§4.3's "what is actually yours"** is now the *product* rather than a
  hypothetical API's inventory, and the separate observation layer is still the
  right structure — see `COURT_DATA_SOURCES.md` §4, which needs it for provenance.
- **§4.4's Tier 1** (versioned regional JSON) remains the eventual answer for
  *your own* client's delivery, per `SCALE_UP.md` §2 — just with no public
  consumer and no urgency.

The rest of §4 is kept as the record of why, not as work to do.

## 4 (historical). The API question

### 4.1 Licensing is the first gate, not the last

Court geometry is OSM-derived, under **ODbL 1.0** — the dataset says so:
`Court data © OpenStreetMap contributors, ODbL 1.0`.

Publishing an API of that data distributes a *Derivative Database*, which
triggers ODbL's share-alike terms: attribute, and offer the derived database
under the same licence. Practically:

- **The OSM-derived half cannot be made proprietary.** Anyone may take it.
- **The attribution obligation is already unmet** — `gaps/ASSETS_AND_DATA.md`
  records that `attribution` is decoded and then discarded, displayed nowhere.
  Publishing an API while failing the licence on your own client is the worst
  order to do these in. **This is a blocker on anything in §4, and it's a small
  fix.**

*Not legal advice.* The Derivative-Database / Produced-Work distinction below is
the hinge of the whole strategy, and it's worth an actual lawyer's read before
anything ships commercially.

### 4.2 The commodity problem

I obtained every basketball court in North Carolina in one query, in seconds, for
free, while writing this. So can anyone.

**An API that redistributes OSM court geometry has no moat and carries
share-alike obligations.** It is strictly worse than the thing it wraps.

### 4.3 What is actually yours

The defensible asset is what OSM *doesn't* have and this app is uniquely
positioned to collect:

| Asset | Why it's yours | Why it's valuable |
|---|---|---|
| Corrected amenities | Player observations, not OSM tags | OSM is 0.9–31.3% populated; this is the gap |
| Facility grouping | Product judgment — the 80m rule plus `facility_overrides.json` | OSM has no concept of it |
| Live headcount | `plans/LIVE_HEADCOUNT.md` | Nobody else has it |
| Queue / run history | Your Firestore | Busyness over time is the real product |
| Verified-vs-unverified | Your review | OSM can't assert it |

These are **observations about** the courts, not a derivative of the OSM
database, which is the distinction that keeps them separable from share-alike.
Structure them that way from day one — a separate layer keyed by court ID, never
merged back into the ODbL geometry — and the licence line stays clean. Merge them
into one blob and you've arguably made the whole thing a derivative database.

**That structure is also just better engineering**, and it's the Phase 3 overlay
already sketched in this session's court-data findings: geometry is bundled and
ODbL; observations live in Firestore, are player-correctable, and carry
provenance. Do it for the data-quality reason; the licensing clarity is a
dividend.

### 4.4 What "our API" looks like, concretely

Three tiers, increasing in cost and commitment. **The first is nearly free and
you need it anyway.**

**Tier 1 — versioned static JSON on Firebase Hosting.** Available on Spark, no
Functions, CDN-cached and globally distributed:

```
/v1/manifest.json                → { region: version, url, sha256, generated }
/v1/regions/triangle.json        → CourtDataset envelope
/v1/regions/charlotte.json
```

`CourtService` fetches the manifest, compares per-region `version` against the
bundled copy, pulls what's newer, falls back to bundled on any failure — exactly
the job `CourtDataset.version` was built for and has never done. Making it
*public* is then a documentation decision, not an engineering one: the files are
already on a CDN.

This is a real API. It is read-only, infinitely cacheable, costs approximately
nothing, and serves the half of the data that never changes per-request.

**Tier 2 — dynamic reads** (headcount, queue state). These already live in
Firestore, and the client SDK plus `firestore.rules` *is* the API — that's why
`LIVE_HEADCOUNT.md` needs no server. Exposing it to third parties is a different
thing: that needs a gateway (Cloud Run or Functions), which needs **Blaze**.
`SCALE_UP.md` §7 is the standing list of what Blaze unlocks; this joins it.

**Tier 3 — a public REST API with keys, quotas and an SLA.** Auth, rate
limiting, abuse handling, versioning and deprecation policy, docs, a status page,
and somebody who answers when it breaks at 11pm. This is a product with an
on-call rotation, not a feature.

### 4.5 Process, in order

1. **Fix the attribution.** Blocking, small, already an open gap.
2. **Decide the licence split** — ODbL geometry layer, own terms for the
   observation layer — and have it reviewed.
3. **Build the pipeline** to emit versioned, hashed regional artifacts (§3 Phase
   A produces most of this).
4. **Publish to Firebase Hosting and point your own client at it first.**
   Dogfood for a release. If it can't reliably serve one app, it can't serve
   strangers.
5. **Then decide whether to document it publicly** — versioning policy, contact,
   attribution requirements for consumers, rate expectations.
6. **Tier 2/3 only with Blaze**, and only against real demand.

Steps 1–4 are work you need regardless of whether anyone else ever calls it.
That's what makes this a low-regret path: **the API is a by-product of fixing
your own delivery**, and the decision to open it stays deferred until the thing
already exists and runs.

### 4.6 The honest summary

Yes, it's possible. The useful version isn't "an API for basketball courts in the
Triangle" — that's a commodity you'd be obliged to give away anyway. The useful
version is **an API for which courts are real, what's actually at them, and
whether anyone is playing right now**, which is the data nobody else has and
which this app exists to collect.

Build the pipeline and the hosted artifacts because your own client needs them.
Treat publishing as a separate, later, deliberate decision.

---

## 5. Open questions

- **Metro region boundaries** — CBSA definitions, or hand-drawn? Hand-drawn is
  probably right for a handful of NC metros and avoids a dependency.
- **Rural fallback** — what a user sees in a county with four courts. A radius
  that grows until it finds something, or an explicit "nearest courts are 30
  miles away"?
- **Does statewide launch at once**, or metro by metro with the pipeline already
  statewide? The latter lets coverage quality lead adoption.
- **Who arbitrates a disputed correction** once observations are
  player-contributed — nothing in §4.3 answers this, and it's the question that
  decides whether the observation layer is trustworthy enough to sell.

## Documentation debt

When phases land, fold into:

- `COURT_DATASET.md` — the ingest source, boundary assignment, regional artifacts.
- `DATA_MODEL.md` — `region` vs `city`; the observation layer's types.
- `ARCHITECTURE.md` — `CourtService` gaining a network path.
- `BUILD_AND_CONFIG.md` — `firebase.json` gaining a hosting block.
- `SCALE_UP.md` — §1's `region` grain (§2.3 above), and strike §2 when delivery ships.

## See also

- `SCALE_UP.md` — delivery mechanism (§2), the region query fix (§1), Blaze list (§7).
- `LIVE_HEADCOUNT.md` — the first dynamic court data worth serving.
- `../COURT_DATASET.md` — the current pipeline and its invariants.
- `../gaps/ASSETS_AND_DATA.md` — the unmet ODbL attribution obligation.
