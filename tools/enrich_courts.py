#!/usr/bin/env python3
"""
Conflate the official municipal snapshot into `courts.json`, with provenance.

`fetch_official_courts.py` harvests what the Triangle governments publish. This
script decides what of it we're entitled to believe, writes only that, and
records where every changed value came from.

## The rule this script exists to enforce

Official sources come at two grains, and they are **not the same kind of claim**:

- **court-level** (`raleigh_courts`): a row is one playing surface. Its
  `Lighting` is a fact *about that court*.
- **park-level** (`wake_parks`, `durham_parks`, `chapelhill_facilities`,
  `raleigh_park_bounds`): a row is a whole park. Its lights may be on the
  ballfield.

So a park-level source may set **where a court is and what it's called** —
address, city, park name — and is **never** allowed to set an amenity. Durham
publishes `LIGHTS` for 26 basketball parks and applying it would lift `isLit`
coverage from 9.8% to ~40%, which is exactly why it's refused: a court shown as
lit that is dark at 7pm is worse than one that admits it doesn't know. Those
become a **verification worklist** for someone to check in person instead.

Decided 2026-09-22. See `plans/COURT_DATA_SOURCES.md` §4.

## What it will and won't overwrite

| field | from | rule |
|---|---|---|
| `address` | park-level | overwrite — every current value is a bare "City, NC" with no street line |
| `city` | `wake_parks.JURISDICTION` | **only when it's already a shipped city** — see below |
| `name` | park-level | only replaces a generic `<City> Basketball Court` |
| `surface`, `isLit`, `isCovered` | court-level **only** | fills a null; a disagreement is reported, never silently applied |

**Why `city` is handled timidly.** `Court.city` is not just a label — it *is* the
matchmaking pool key (`MatchTicket.region`, and `SquadViewModel.region`). Moving a
court from "Apex" to "Holly Springs" because the county says so would be more
accurate *and* would create a one-court matchmaking pool that can never match
anybody. Until `region` is split from `city` (`COURT_DATA_PLATFORM.md` §2.3),
correcting within the shipped six is a fix and correcting outside it is a
regression. Out-of-set jurisdictions are reported, not written.

    python3 tools/enrich_courts.py --dry-run
    python3 tools/enrich_courts.py

Idempotent. Never invents or re-mints a court ID.
"""
import argparse
import collections
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from courts_common import haversine  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATASET = os.path.join(ROOT, "hoopr", "Resources", "courts.json")
SOURCE_DIR = os.path.join(ROOT, "tools", "official_sources")
WORKLIST = os.path.join(ROOT, "tools", "verify_worklist.json")

DATASET_VERSION = 3  # gained per-field provenance

# Sources that may set an amenity. Everything else is park-level.
COURT_LEVEL = {"raleigh_courts"}

# How close a court has to be to a park's published point to be treated as
# inside it, when the park has no polygon (Wake and Chapel Hill are point
# layers). Deliberately tight: a wrong address is worse than none, and a park
# point is usually near its entrance rather than its centre.
POINT_RADIUS_M = 250

# Buffer around a court-level polygon, for matching our OSM point to Raleigh's
# court footprint when the two are drawn slightly differently.
COURT_BUFFER_M = 60

GENERIC_NAME = re.compile(
    r"^(Apex|Cary|Chapel Hill|Durham|Morrisville|Raleigh)"
    r" Basketball Court(?P<suffix>\s*#\d+)?$"
)

# "City of Raleigh" / "Town of Cary" -> "Raleigh" / "Cary".
JURIS = re.compile(r"^(?:City|Town|Village)\s+of\s+(?P<name>.+?)\s*$", re.I)

STREET = re.compile(
    r"(^\d+\s)|(\b(st|street|rd|road|ave|avenue|dr|drive|ln|lane|blvd|boulevard"
    r"|way|ct|court|cir|circle|pkwy|parkway|trl|trail|hwy|highway|pl|place)\b\.?)",
    re.IGNORECASE,
)

YES = {"yes", "y", "true", "1"}
NO = {"no", "n", "false", "0"}


def load_sources(path):
    out = {}
    if not os.path.isdir(path):
        return out
    for fn in sorted(os.listdir(path)):
        if fn.endswith(".json"):
            with open(os.path.join(path, fn)) as h:
                d = json.load(h)
            out[d["source"]] = d
    return out


def in_ring(lat, lon, ring):
    """Ray-casting point-in-polygon. `ring` is [[lon, lat], ...]."""
    inside = False
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i][0], ring[i][1]
        x2, y2 = ring[(i + 1) % n][0], ring[(i + 1) % n][1]
        if (y1 > lat) != (y2 > lat):
            # x of the edge at this latitude
            t = (lat - y1) / (y2 - y1) if y2 != y1 else 0.0
            if lon < x1 + t * (x2 - x1):
                inside = not inside
    return inside


def contains(rec, lat, lon):
    """Whether a harvested record's footprint contains the point.

    Polygon records use real containment on the outer ring. Point records fall
    back to `POINT_RADIUS_M`, and report the distance so the caller can prefer a
    containment hit over a proximity one.
    """
    if "rings" in rec:
        for ring in rec["rings"]:
            if in_ring(lat, lon, ring):
                return True, 0.0
        return False, None
    if "lat" in rec:
        d = haversine(lat, lon, rec["lat"], rec["lon"])
        return (d <= POINT_RADIUS_M), d
    return False, None


def best_park(court, sources):
    """The park-level record this court sits in, preferring containment.

    Ordered: a polygon containment hit beats any proximity hit, and among
    proximity hits the nearest wins. Ties between sources are broken by the
    order in `preference` — a city's own parks layer knows its addresses better
    than the county's roll-up does.
    """
    preference = ["durham_parks", "raleigh_park_bounds", "chapelhill_facilities",
                  "wake_parks"]
    lat, lon = court["latitude"], court["longitude"]
    hits = []
    for name in preference:
        src = sources.get(name)
        if not src or name in COURT_LEVEL:
            continue
        for rec in src["records"]:
            ok, dist = contains(rec, lat, lon)
            if ok:
                contained = "rings" in rec
                hits.append((0 if contained else 1, dist or 0.0,
                             preference.index(name), name, rec))
    if not hits:
        return None, None
    hits.sort(key=lambda h: (h[0], h[2], h[1]))
    return hits[0][3], hits[0][4]


def best_court_record(court, sources):
    """The court-level record for this court, if any."""
    src = sources.get("raleigh_courts")
    if not src:
        return None
    lat, lon = court["latitude"], court["longitude"]
    best, bestd = None, None
    for rec in src["records"]:
        if "rings" in rec:
            for ring in rec["rings"]:
                if in_ring(lat, lon, ring):
                    return rec
        if "lat" in rec:
            d = haversine(lat, lon, rec["lat"], rec["lon"])
            if d <= COURT_BUFFER_M and (bestd is None or d < bestd):
                best, bestd = rec, d
    return best


def park_address(name, attrs):
    for key in ("FULLADDR", "ADDRESS", "Facility_Address"):
        v = (attrs.get(key) or "").strip()
        if v and STREET.search(v):
            extra = (attrs.get("Address2") or "").strip()
            if extra and extra.lower() not in v.lower():
                v = f"{v}, {extra}"
            return v
    return None


# A candidate name mentioning a *different* amenity means the record we matched
# is a sub-feature of a park, not the park. Taking it produces names that are
# actively worse than the generic one they replace: the first pass renamed a
# court to "The PIT Soccer Field Basketball Court" and another to "Elevate
# Fitness Course Basketball Court" — a basketball court named after a soccer
# field and a fitness trail. A generic "Apex #9" at least doesn't lie.
#
# Deliberately not a general profanity-style blocklist: these are the specific
# amenity words that appear in this data's sub-feature names.
OTHER_AMENITY = re.compile(
    r"\b(soccer|football|baseball|softball|tennis|pickleball|volleyball|"
    r"skate\s*park|skatepark|batting\s*cage|fitness|disc\s*golf|golf|"
    r"playground|pool|aquatic|dog\s*park|garden|greenway|trail|"
    r"amphitheater|amphitheatre|shelter|restroom|parking)\b",
    re.IGNORECASE,
)


def park_name(attrs):
    """The park's own name, or None if the best candidate names something else.

    Returning None leaves the court's existing name alone, which is the right
    outcome: a generic name is uninformative, but a wrong one is misleading, and
    only one of those gets a player to the wrong place.
    """
    for key in ("NAME", "Facility_Name", "NAME_1", "PARK_NAME"):
        v = (attrs.get(key) or "").strip()
        if not v:
            continue
        if OTHER_AMENITY.search(v):
            return None
        return v
    return None


def main():
    ap = argparse.ArgumentParser(description="Conflate official data into courts.json")
    ap.add_argument("--path", default=DATASET)
    ap.add_argument("--sources", default=SOURCE_DIR)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    with open(args.path) as h:
        dataset = json.load(h)
    courts = dataset["courts"]
    sources = load_sources(args.sources)
    if not sources:
        print(f"no snapshots in {args.sources} — run fetch_official_courts.py first",
              file=sys.stderr)
        return 2
    summary = ", ".join(
        "{}({},{})".format(k, v["grain"], len(v["records"]))
        for k, v in sources.items()
    )
    print("sources: " + summary)

    shipped_cities = set(dataset.get("cities", []))
    stats = collections.Counter()
    conflicts = []
    verify = []
    city_out_of_set = []

    for court in courts:
        prov = dict(court.get("provenance") or {})

        # ---- park-level: where it is and what it's called -------------------
        src_name, park = best_park(court, sources)
        if park:
            attrs = park["attributes"]
            addr = park_address(src_name, attrs)
            if addr and addr != court.get("address"):
                court["address"] = addr
                prov["address"] = src_name
                stats["address"] += 1

            pname = park_name(attrs)
            m = GENERIC_NAME.match(court["name"] or "")
            if pname and m:
                suffix = m.group("suffix") or ""
                court["name"] = f"{pname} Basketball Court{suffix}"
                prov["name"] = src_name
                stats["name"] += 1

            juris = (attrs.get("JURISDICTION") or "").strip()
            if juris:
                jm = JURIS.match(juris)
                city = jm.group("name").strip() if jm else juris
                if city != court.get("city"):
                    if city in shipped_cities:
                        court["city"] = city
                        prov["city"] = src_name
                        stats["city"] += 1
                    else:
                        city_out_of_set.append(
                            (court["name"], court.get("city"), city))

            # Park-level lights are NOT written. They become a worklist.
            lights = str(attrs.get("LIGHTS") or "").strip().lower()
            if lights in YES and court.get("isLit") is None:
                verify.append({
                    "courtId": court["id"], "facilityId": court.get("facilityId"),
                    "name": court["name"],
                    "city": court.get("city"),
                    "address": court.get("address"),
                    "field": "isLit",
                    "claim": True,
                    "claimedBy": src_name,
                    "park": park_name(attrs),
                    "note": "park-level LIGHTS=Yes; may be ballfield lighting. "
                            "Verify on site before setting isLit.",
                })
                stats["verify_isLit"] += 1

        # ---- court-level: amenities ----------------------------------------
        rec = best_court_record(court, sources)
        if rec:
            a = rec["attributes"]
            stats["court_matched"] += 1

            lighting = str(a.get("Lighting") or "").strip().lower()
            if lighting in YES or lighting in NO:
                val = lighting in YES
                if court.get("isLit") is None:
                    court["isLit"] = val
                    prov["isLit"] = "raleigh_courts"
                    stats["isLit"] += 1
                elif court["isLit"] != val:
                    conflicts.append((court["name"], "isLit", court["isLit"], val))
                    # A court-level source disagreeing with us is the strongest
                    # possible reason to go look. Note the asymmetry: we keep our
                    # `False` rather than taking their `True`, because a court
                    # shown as lit that is dark costs a wasted trip while the
                    # reverse only costs a missed opportunity.
                    verify.append({
                        "courtId": court["id"], "facilityId": court.get("facilityId"),
                        "name": court["name"],
                        "city": court.get("city"), "address": court.get("address"),
                        "field": "isLit", "claim": val, "claimedBy": "raleigh_courts",
                        "ours": court["isLit"], "park": None,
                        "note": "CONFLICT: court-level official source disagrees. "
                                "We kept ours. Verify on site.",
                    })

            io = str(a.get("IndoorOutdoor") or "").strip().lower()
            if io:
                covered = "covered" in io and "uncovered" not in io
                if court.get("isCovered") is None:
                    court["isCovered"] = covered
                    prov["isCovered"] = "raleigh_courts"
                    stats["isCovered"] += 1
                elif court["isCovered"] != covered:
                    conflicts.append((court["name"], "isCovered",
                                      court["isCovered"], covered))

            surf = (a.get("Surface") or "").strip()
            if surf:
                norm = surf.lower()
                if court.get("surface") is None:
                    court["surface"] = norm
                    prov["surface"] = "raleigh_courts"
                    stats["surface"] += 1
                elif court["surface"].lower() != norm:
                    conflicts.append((court["name"], "surface",
                                      court["surface"], norm))
                    verify.append({
                        "courtId": court["id"], "facilityId": court.get("facilityId"),
                        "name": court["name"],
                        "city": court.get("city"), "address": court.get("address"),
                        "field": "surface", "claim": norm,
                        "claimedBy": "raleigh_courts", "ours": court["surface"],
                        "park": None,
                        "note": "CONFLICT: court-level official source disagrees. "
                                "We kept ours. Verify on site.",
                    })

            status = (a.get("Status") or "").strip()
            if status and status.lower() != "existing":
                stats["non_existing_status"] += 1

            # **Ownership is evidence of jurisdiction.** Raleigh PRCR publishes
            # only Raleigh's own city-park courts, so a court-level match is a
            # stronger claim about which city a court is in than the
            # nearest-centroid guess that assigned `city` in the first place.
            # Powell Drive Park sits 3m from Raleigh's own record and inside its
            # city limits, and shipped labeled "Cary".
            if court.get("city") != "Raleigh" and "Raleigh" in shipped_cities:
                stats["city_from_ownership"] += 1
                court["city"] = "Raleigh"
                prov["city"] = "raleigh_courts"

            # A court-level name is better than a generic one.
            title = (a.get("LocationName") or "").strip()
            if title and GENERIC_NAME.match(court["name"] or ""):
                court["name"] = f"{title} Basketball Court"
                prov["name"] = "raleigh_courts"
                stats["name"] += 1

        # ---- attribute what was already there ------------------------------
        # Anything with a value and no provenance came from the OSM extract.
        # Stamping it matters for two reasons: an unattributed value is
        # indistinguishable from a verified one, and `osm` is the tier most
        # likely to be wrong — a volunteer's `lit=yes` from some year, on a court
        # nobody has checked since.
        for field in ("hoops", "surface", "isLit", "isCovered"):
            if court.get(field) is not None and field not in prov:
                prov[field] = "osm"
                stats[f"osm_{field}"] += 1

        # An OSM `lit=yes` is exactly the failure mode we refused park-level data
        # for: a court shown as lit that is dark. It's court-level in *grain*, so
        # it stays in the dataset — but it goes on the list to confirm.
        if court.get("isLit") is True and prov.get("isLit") == "osm":
            verify.append({
                "courtId": court["id"], "facilityId": court.get("facilityId"),
                "name": court["name"],
                "city": court.get("city"), "address": court.get("address"),
                "field": "isLit", "claim": True, "claimedBy": "osm",
                "ours": True, "park": None,
                "note": "We already show this court as LIT, on an OSM volunteer "
                        "tag nobody has verified. Highest priority to confirm — "
                        "if it's wrong, a player is shown lights that don't exist.",
            })
            stats["verify_osm_lit"] += 1

        if prov:
            court["provenance"] = prov

    # ---- a generic name must not contradict a corrected city ---------------
    #
    # A generic name embeds the city the *old* nearest-centroid guess produced:
    # "Cary Basketball Court #2". Correcting the city to Apex leaves a row
    # reading "Cary #2" under "Apex · 3.2 mi away", which looks like a bug to a
    # reader and is one to anyone searching. Re-prefix with the real city, taking
    # the next free index there so the rename can't collide with an existing
    # "Apex Basketball Court #2".
    used = collections.defaultdict(set)
    for court in courts:
        m = GENERIC_NAME.match(court["name"] or "")
        if m:
            suffix = (m.group("suffix") or "").strip().lstrip("#")
            if suffix.isdigit():
                used[m.group(1)].add(int(suffix))

    for court in courts:
        m = GENERIC_NAME.match(court["name"] or "")
        if not m or m.group(1) == court["city"]:
            continue
        city = court["city"]
        n = 1
        while n in used[city]:
            n += 1
        used[city].add(n)
        old = court["name"]
        court["name"] = f"{city} Basketball Court #{n}"
        prov = dict(court.get("provenance") or {})
        prov["name"] = "derived-from-city"
        court["provenance"] = prov
        stats["name_recity"] += 1
        if args.verbose:
            print(f"  re-prefixed {old!r} -> {court['name']!r}")

    # ---- report ------------------------------------------------------------
    total = len(courts)
    print(f"\n{total} courts")
    print(f"  address written   : {stats['address']}")
    print(f"  name corrected    : {stats['name']}")
    print(f"  city corrected    : {stats['city']}"
          f" (+{stats['city_from_ownership']} from Raleigh PRCR ownership)")
    print(f"  matched court-level: {stats['court_matched']}")
    print(f"    isLit filled    : {stats['isLit']}")
    print(f"    isCovered filled: {stats['isCovered']}")
    print(f"    surface filled  : {stats['surface']}")
    print(f"\n  park-level lights NOT applied (verify on site): "
          f"{stats['verify_isLit']}")
    print(f"  pre-existing values attributed to osm: "
          f"isLit={stats['osm_isLit']} surface={stats['osm_surface']} "
          f"hoops={stats['osm_hoops']} isCovered={stats['osm_isCovered']}")
    print(f"  unverified OSM 'lit=yes' flagged to confirm: "
          f"{stats['verify_osm_lit']}")

    def cov(field):
        n = sum(1 for c in courts if c.get(field) is not None)
        return f"{n}/{total} ({100 * n // total}%)"
    print("\ncoverage now:")
    for f in ("address", "isLit", "isCovered", "surface", "hoops"):
        if f == "address":
            n = sum(1 for c in courts if STREET.search(c.get("address") or ""))
            print(f"  address with street line: {n}/{total} ({100 * n // total}%)")
        else:
            print(f"  {f:10} {cov(f)}")

    if conflicts:
        print(f"\nCONFLICTS — official disagrees with what we had ({len(conflicts)}), "
              "left as-is:")
        for name, field, ours, theirs in (conflicts if args.verbose else conflicts[:8]):
            print(f"  {name[:42]:42} {field}: ours={ours} official={theirs}")
        if not args.verbose and len(conflicts) > 8:
            print(f"  ... {len(conflicts) - 8} more (--verbose)")

    if city_out_of_set:
        print(f"\nCITY left alone — official jurisdiction is outside the shipped "
              f"cities ({len(city_out_of_set)}):")
        seen = collections.Counter(c[2] for c in city_out_of_set)
        for city, n in seen.most_common():
            print(f"  {n:3} court(s) -> {city}")
        print("  (writing these would create one-court matchmaking pools; see "
              "COURT_DATA_PLATFORM.md §2.3)")

    if args.dry_run:
        print("\ndry run — nothing written")
        return 0

    dataset["version"] = DATASET_VERSION
    dataset["sources"] = [
        {"source": k, "grain": v["grain"], "url": v["url"],
         "attribution": v["attribution"], "fetched": v["fetched"]}
        for k, v in sorted(sources.items())
    ]
    # The licence line has to name everyone whose data is in the file now.
    extra = sorted({v["attribution"] for v in sources.values()})
    dataset["attribution"] = (
        "Court data © OpenStreetMap contributors, ODbL 1.0. "
        + "Municipal data: " + "; ".join(extra) + "."
    )

    with open(args.path, "w") as h:
        json.dump(dataset, h, indent=2, ensure_ascii=False)
        h.write("\n")
    print(f"\nwrote {args.path} (dataset v{DATASET_VERSION})")

    with open(WORKLIST, "w") as h:
        json.dump({
            "generated": max(v["fetched"] for v in sources.values()),
            "note": "Courts where an official PARK-level source claims lights but "
                    "we refuse to infer isLit from it. Check on site, then set "
                    "isLit directly in courts.json with provenance 'verified-onsite'.",
            "items": verify,
        }, h, indent=2, ensure_ascii=False)
        h.write("\n")
    print(f"wrote {WORKLIST} ({len(verify)} to verify on site)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
