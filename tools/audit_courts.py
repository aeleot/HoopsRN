#!/usr/bin/env python3
"""
Quality report over the bundled court dataset.

`build_courts.py` and `fetch_city_courts.py` answer "what courts exist". Neither
answers "is what we shipped any good", and the difference is not academic: every
field in `courts.json` is *populated* — `address` is non-empty for all 214
records — while carrying almost no information. A completeness check that only
tests for `null` reports this dataset as clean.

So this script checks the two things a null-check can't see:

1. **Fields that are present but vacuous.** An `address` of "Durham, NC" is a
   city label wearing an address's clothes. `CreateGameSheet` renders it as the
   court's address and `MapTab.openDirections` hands it to `MKAddress`.
2. **Records that disagree with each other.** Two pins 17m apart are one place a
   player walks to, and anything keyed on `courtId` — `Game.courtId`,
   `MatchTicket.courtIds` — treats them as two. That splits a queue in half at
   the court where it matters most.

Read-only. It never writes `courts.json`; `--json` is for CI, `--verbose` lists
every affected record instead of a sample.

    python3 tools/audit_courts.py
    python3 tools/audit_courts.py --verbose
    python3 tools/audit_courts.py --json

Exit status is 1 when any check reports a finding, so CI can gate on it.
"""
import argparse
import collections
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from courts_common import CITIES, haversine  # noqa: E402

DATASET = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "hoopr", "Resources", "courts.json",
)

# Two courts closer together than this are the same facility: adjacent surfaces
# at one park, not two destinations. Wider than a full court's diagonal (~32m)
# and narrower than the gap between genuinely separate parks, and it is roughly
# the distance at which two map pins start to overlap at neighbourhood zoom.
#
# **Must match `assign_facilities.DEFAULT_THRESHOLD_M`** — this script reports
# the splits that one is expected to have fixed, so a disagreement here reads as
# a bug in the assigner rather than a difference of opinion between two tools.
SAME_FACILITY_M = 80

# The fields a player reads as a fact about the court. Kept separate from
# identity/geometry fields because a null here is a *silent* gap: `CourtBadges`
# only emits a badge when the value is truthy, so an unknown `isLit` renders
# exactly like a court known to have no lights.
AMENITY_FIELDS = ("hoops", "surface", "isLit", "isCovered")

# Coverage below this is reported: the field is present often enough to look
# like it means something and rare enough that its absence is noise.
COVERAGE_FLOOR = 0.50


def load(path):
    with open(path) as handle:
        return json.load(handle)


def vacuous_addresses(courts):
    """Addresses that resolve no finer than the city already does.

    An address is vacuous when it carries no street line — no leading house
    number and no street token. These are the records where the app shows a
    reader something in the address slot that they already knew from the city
    line above it.
    """
    findings = []
    for court in courts:
        address = (court.get("address") or "").strip()
        has_number = bool(re.match(r"^\d+\s", address))
        # "Durham, NC" is two tokens and a comma; a street line has a road type.
        has_street = bool(
            re.search(
                r"\b(st|street|rd|road|ave|avenue|dr|drive|ln|lane|blvd|"
                r"boulevard|way|ct|court|cir|circle|pkwy|parkway|trl|trail|"
                r"hwy|highway|pl|place)\b\.?",
                address,
                re.IGNORECASE,
            )
        )
        if not (has_number or has_street):
            findings.append((court, address))
    return findings


def amenity_coverage(courts):
    """How often each player-facing amenity field is actually answered."""
    total = len(courts) or 1
    return {
        field: sum(1 for c in courts if c.get(field) is not None) / total
        for field in AMENITY_FIELDS
    }


def facility_clusters(courts):
    """Group records that sit within `SAME_FACILITY_M` of each other.

    Union-find over the pairwise distances, short-circuited on latitude so this
    stays fast enough to run on every commit. Returns only the groups holding
    more than one record — the ones that are one facility split across several
    court IDs.
    """
    parent = list(range(len(courts)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    for i in range(len(courts)):
        for j in range(i + 1, len(courts)):
            # ~0.002 degrees of latitude is ~220m; anything beyond that cannot
            # be within the threshold, so skip the trig.
            if abs(courts[i]["latitude"] - courts[j]["latitude"]) > 0.002:
                continue
            metres = haversine(
                courts[i]["latitude"], courts[i]["longitude"],
                courts[j]["latitude"], courts[j]["longitude"],
            )
            if metres <= SAME_FACILITY_M:
                union(i, j)

    groups = collections.defaultdict(list)
    for i in range(len(courts)):
        groups[find(i)].append(courts[i])
    return [g for g in groups.values() if len(g) > 1]


def display_name(name):
    """Mirror of `Court.displayName` — what the reader actually sees.

    Kept in step with `Models/Court.swift` deliberately: a collision only
    matters if it survives the stripping the app does before drawing the name.
    """
    stripped = re.sub(r"(?i)basketball court", " ", name)
    stripped = " ".join(stripped.split())
    return stripped or name


def name_collisions(courts):
    """Display names drawn on more than one pin."""
    seen = collections.defaultdict(list)
    for court in courts:
        seen[display_name(court["name"])].append(court)
    return {k: v for k, v in seen.items() if len(v) > 1}


def generic_names(courts, cities):
    """Records named only after their city and a counter.

    "Apex Basketball Court #7" tells a player nothing that the pin's position
    hasn't already told them, and `Court.displayName` renders it "Apex #7".
    """
    pattern = re.compile(r"^(.+?) Basketball Court(?:s)?(?:\s*#\d+)?$", re.IGNORECASE)
    out = []
    for court in courts:
        match = pattern.match(court["name"])
        if match and match.group(1).strip() in cities:
            out.append(court)
    return out


def split_city_facilities(groups):
    """One facility whose records disagree about which city they're in."""
    return [g for g in groups if len({c["city"] for c in g}) > 1]


def ungrouped_clusters(clusters):
    """Distance clusters whose members do **not** share a `facilityId`.

    Before facilities existed, every cluster was a finding. Now the clusters are
    expected — `assign_facilities.py` builds them deliberately — and the finding
    is a cluster it *failed* to group: two surfaces a player walks between that
    still carry separate facility IDs, and therefore still hold separate queues.

    Reporting the clusters themselves would make this script cry wolf on 45
    records forever, which is how a checker stops being read.
    """
    out = []
    for group in clusters:
        ids = {c.get("facilityId") or c["id"] for c in group}
        if len(ids) > 1:
            out.append(group)
    return out


def facility_groups(courts):
    """Courts grouped by their assigned `facilityId`, in dataset order."""
    order = []
    by_id = collections.defaultdict(list)
    for court in courts:
        key = court.get("facilityId") or court["id"]
        if key not in by_id:
            order.append(key)
        by_id[key].append(court)
    return [by_id[k] for k in order]


def city_mislabels(courts):
    """Records labeled with a city that isn't the nearest known centre.

    Nearest-centroid is how `courts_common.CITIES` assigns a city, so a record
    that disagrees with it was either labeled by a different pass or is genuinely
    across a municipal line the centroid model can't see. Reported as a review
    queue, not a bug — real boundaries are not Voronoi cells.
    """
    out = []
    for court in courts:
        assigned = court["city"]
        if assigned not in CITIES:
            out.append((court, assigned, None, None))
            continue
        nearest = min(
            CITIES,
            key=lambda c: haversine(
                court["latitude"], court["longitude"], *CITIES[c]
            ),
        )
        if nearest != assigned:
            # haversine is metres; the report talks in miles.
            d_assigned = haversine(
                court["latitude"], court["longitude"], *CITIES[assigned]
            ) / 1609.344
            d_nearest = haversine(
                court["latitude"], court["longitude"], *CITIES[nearest]
            ) / 1609.344
            out.append((court, assigned, nearest, d_assigned - d_nearest))
    return out


def provenance_summary(courts):
    """Where each written field's value came from, and the discipline check.

    The one invariant worth failing over: **an amenity may only carry a
    court-level or on-site provenance.** `enrich_courts.py` refuses to infer
    `isLit` from a park saying it has lights, because the lights may be on the
    ballfield — and a court shown as lit that is dark costs a wasted trip. If a
    park-level source ever appears against an amenity here, that refusal has
    broken.
    """
    COURT_LEVEL = {"raleigh_courts", "verified-onsite", "osm"}
    AMENITIES = {"isLit", "isCovered", "surface", "hoops"}
    by_field = collections.defaultdict(collections.Counter)
    violations = []
    for court in courts:
        for field, source in (court.get("provenance") or {}).items():
            by_field[field][source] += 1
            if field in AMENITIES and source not in COURT_LEVEL:
                violations.append((court.get("name"), field, source))
    return by_field, violations


def integrity(courts):
    """Invariants that should never fail: unique IDs, unique OSM refs, sane coords."""
    problems = []
    ids = collections.Counter(c["id"] for c in courts)
    for court_id, count in ids.items():
        if count > 1:
            problems.append(f"court id {court_id} used by {count} records")

    refs = collections.Counter((c.get("osmType"), c.get("osmId")) for c in courts)
    for ref, count in refs.items():
        if count > 1 and ref != (None, None):
            problems.append(f"OSM ref {ref[0]}/{ref[1]} used by {count} records")

    for court in courts:
        lat, lon = court.get("latitude"), court.get("longitude")
        if lat is None or lon is None:
            problems.append(f"{court['name']}: missing coordinate")
        elif not (-90 <= lat <= 90 and -180 <= lon <= 180):
            problems.append(f"{court['name']}: coordinate out of range")
        elif lat == 0 and lon == 0:
            problems.append(f"{court['name']}: null-island coordinate")
    return problems


def main():
    parser = argparse.ArgumentParser(
        description="Quality report over hoopr/Resources/courts.json",
    )
    parser.add_argument("--path", default=DATASET, help="dataset to audit")
    parser.add_argument("--json", action="store_true", dest="as_json",
                        help="emit machine-readable findings")
    parser.add_argument("--verbose", action="store_true",
                        help="list every affected record, not a sample")
    args = parser.parse_args()

    dataset = load(args.path)
    courts = dataset["courts"]
    cities = set(dataset.get("cities", []))
    total = len(courts)

    vacuous = vacuous_addresses(courts)
    coverage = amenity_coverage(courts)
    clusters = facility_clusters(courts)
    groups = facility_groups(courts)
    ungrouped = ungrouped_clusters(clusters)
    collisions = name_collisions(courts)
    generic = generic_names(courts, cities)
    split_city = split_city_facilities(groups)
    mislabeled = city_mislabels(courts)
    broken = integrity(courts)
    prov, prov_violations = provenance_summary(courts)

    assigned_count = sum(1 for c in courts if c.get("facilityId"))
    multi = [g for g in groups if len(g) > 1]
    thin = {f: r for f, r in coverage.items() if r < COVERAGE_FLOOR}

    if args.as_json:
        print(json.dumps({
            "path": args.path,
            "version": dataset.get("version"),
            "generated": dataset.get("generated"),
            "courts": total,
            "vacuous_addresses": len(vacuous),
            "amenity_coverage": coverage,
            "facilities": len(groups),
            "multi_surface_facilities": len(multi),
            "facility_ids_assigned": assigned_count,
            "clusters_not_grouped": len(ungrouped),
            "facilities_with_conflicting_city": len(split_city),
            "display_name_collisions": len(collisions),
            "generic_names": len(generic),
            "city_mislabels": len(mislabeled),
            "integrity_problems": broken,
            "provenance": {k: dict(v) for k, v in prov.items()},
            "provenance_violations": len(prov_violations),
        }, indent=2))
    else:
        def pct(n):
            return f"{100.0 * n / total:.0f}%" if total else "—"

        print(f"courts.json — v{dataset.get('version')}, "
              f"generated {dataset.get('generated')}, {total} records")
        print(f"cities: {', '.join(sorted(cities))}\n")

        print("ADDRESSES")
        print(f"  no street line: {len(vacuous)}/{total} ({pct(len(vacuous))})")
        distinct = len({(c.get('address') or '') for c in courts})
        print(f"  distinct address strings: {distinct}")
        if vacuous:
            print("  shown by CreateGameSheet and handed to MKAddress as-is")
            for court, address in (vacuous if args.verbose else vacuous[:3]):
                print(f"    {court['name'][:44]:44} -> {address!r}")
            if not args.verbose and len(vacuous) > 3:
                print(f"    ... {len(vacuous) - 3} more (--verbose)")

        print("\nAMENITY COVERAGE  (a null renders as absent, not unknown)")
        for field, ratio in coverage.items():
            mark = "  <- thin" if ratio < COVERAGE_FLOOR else ""
            print(f"  {field:11} {ratio * 100:5.1f}%{mark}")

        print("\nFACILITIES")
        print(f"  facilityId assigned: {assigned_count}/{total} ({pct(assigned_count)})")
        print(f"  {total} courts -> {len(groups)} facilities "
              f"({len(multi)} holding more than one surface)")
        if ungrouped:
            print(f"  NOT GROUPED: {len(ungrouped)} cluster(s) within "
                  f"{SAME_FACILITY_M}m carry different facility IDs —")
            print("  still separate queues at one physical place; "
                  "re-run assign_facilities.py")
            for group in (ungrouped if args.verbose else ungrouped[:5]):
                names = ", ".join(display_name(c["name"]) for c in group)
                print(f"    {len(group)}x  {names[:70]}")
        else:
            print(f"  every cluster within {SAME_FACILITY_M}m shares a facility")
        if split_city:
            print(f"  conflicting city within one facility: {len(split_city)} "
                  "(Facility.city takes the primary's)")
            for group in split_city:
                cs = sorted({c["city"] for c in group})
                print(f"    {display_name(group[0]['name'])[:48]:48} {cs}")

        print("\nPROVENANCE  (where a written value came from)")
        if prov:
            for field in sorted(prov):
                srcs = ", ".join(f"{s}={n}" for s, n in prov[field].most_common())
                print(f"  {field:11} {srcs}")
        else:
            print("  none recorded — enrich_courts.py has not run")
        if prov_violations:
            print(f"  FAIL {len(prov_violations)} amenity value(s) from a "
                  "park-level source:")
            for name, field, src in prov_violations[:6]:
                print(f"    {str(name)[:40]:40} {field} <- {src}")
        elif prov:
            print("  every amenity traces to a court-level or on-site source")

        print("\nNAMES")
        print(f"  generic '<City> Basketball Court': {len(generic)}/{total} "
              f"({pct(len(generic))})")
        print(f"  display names on 2+ pins: {len(collisions)}")
        for name, group in (list(collisions.items()) if args.verbose
                            else list(collisions.items())[:3]):
            print(f"    {name!r} x{len(group)} "
                  f"{sorted({c['city'] for c in group})}")

        print("\nCITY LABELS")
        print(f"  not the nearest known centre: {len(mislabeled)}/{total} "
              "(review queue — real boundaries aren't Voronoi cells)")
        for court, assigned, nearest, delta in (
            mislabeled if args.verbose else mislabeled[:3]
        ):
            if nearest:
                print(f"    {court['name'][:40]:40} {assigned} "
                      f"(nearest: {nearest}, {delta:.1f} mi closer)")
            else:
                print(f"    {court['name'][:40]:40} {assigned} (unknown city)")

        print("\nINTEGRITY")
        if broken:
            for problem in broken:
                print(f"  FAIL {problem}")
        else:
            print("  ids unique, OSM refs unique, coordinates in range")

    findings = (
        len(vacuous) + len(ungrouped) + len(collisions)
        + len(generic) + len(thin) + len(broken)
        + (total - assigned_count) + len(prov_violations)
    )
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
