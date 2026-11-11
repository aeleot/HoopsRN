#!/usr/bin/env python3
"""
Assign a `facilityId` to every court in the bundled dataset.

A *facility* is one place a player travels to. A *court* is one playing surface
there. The dataset has only ever had the second, which is why Long Meadow Park
ships as three records 17m apart: OSM tags each surface as its own way, and
nothing downstream ever grouped them back together.

That gap is visible in two places. On the map it's three pins stacked on each
other. In the queue it's worse — `Game.courtId` and `MatchTicket.courtIds` key on
the court, so a player queued at Long Meadow #1 and a player queued at #2 are in
two queues seventeen metres apart, neither able to see the other.

## Why this is a grouping key and not a stored reference

`facilityId` is **derived**, and deliberately carries no durability obligation.
Games keep storing `courtId`; the facility is how the client *groups* them at
read time. So unlike a court ID — which `courts_common.NAMESPACE` exists to keep
stable across rebuilds because `Game.courtId` and `UserProfile.homeCourtId` point
at it — a facility ID can be re-minted freely. Nothing in Firestore references
one. That is what makes re-running this script safe.

## Why the clustering is baked into the file

The 60m rule is a guess, and sometimes it guesses wrong in both directions: two
parks across a narrow street read as one facility, and one park with courts at
opposite ends reads as two. A human has to be able to correct that, so the
grouping is written into `courts.json` and `facility_overrides.json` holds the
corrections. Computing it at app launch instead would put the rule somewhere
nobody can override it per-court.

    python3 tools/assign_facilities.py --dry-run
    python3 tools/assign_facilities.py
    python3 tools/assign_facilities.py --threshold 80

Idempotent: running it twice produces the same file.
"""
import argparse
import collections
import json
import os
import sys
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from courts_common import NAMESPACE, haversine  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATASET = os.path.join(ROOT, "hoopr", "Resources", "courts.json")
OVERRIDES = os.path.join(ROOT, "tools", "facility_overrides.json")

# Two surfaces closer together than this belong to one facility. Wider than a
# full court's diagonal (~32m) so the halves of a single OSM-split court always
# group, narrower than the gap between genuinely separate parks.
#
# 80 rather than 60 because the three groups in that band are all unambiguous —
# two records *identically named* "Davis Drive Elementary School" 71m apart,
# "Jeffreys Grove Elementary School #1/#2", and Halifax Park's two outdoor
# courts. Widening to 80 gained those three and split nothing that 60 had
# grouped. Raise it further only against the same test: a threshold is wrong the
# moment it merges two names a player would read as different places.
DEFAULT_THRESHOLD_M = 80

# The dataset version this script writes. `CourtDataset.version` is how a future
# hosted copy is compared against the bundled one without parsing courts, so it
# has to move when the court schema gains a field.
DATASET_VERSION = 2


def facility_id(members):
    """The facility ID for a group of courts.

    Minted from the group's **canonical** member — the smallest OSM reference —
    rather than from the whole membership list, so adding a surface to a facility
    doesn't renumber it. Courts with no OSM provenance fall back to their court
    ID, which is already unique.

    Namespaced under `facility/` so a facility ID can never collide with a court
    ID minted by `courts_common.court_id`, and so a value in the wrong field is
    obvious rather than merely wrong.
    """
    def sort_key(court):
        # None sorts before any string, so courts without provenance are only
        # canonical when nothing in the group has any.
        return (
            court.get("osmType") is None,
            court.get("osmType") or "",
            court.get("osmId") or 0,
            court["id"],
        )

    canonical = min(members, key=sort_key)
    if canonical.get("osmType") and canonical.get("osmId") is not None:
        seed = f"facility/{canonical['osmType']}/{canonical['osmId']}"
    else:
        seed = f"facility/court/{canonical['id']}"
    return str(uuid.uuid5(NAMESPACE, seed))


def cluster(courts, threshold_m):
    """Union-find over pairwise distance. Returns a list of court-index groups."""
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

    # ~0.002 degrees of latitude is ~220m — beyond any sane threshold, so the
    # trig is skipped for the overwhelming majority of pairs.
    lat_window = max(0.002, threshold_m / 45_000.0)
    for i in range(len(courts)):
        for j in range(i + 1, len(courts)):
            if abs(courts[i]["latitude"] - courts[j]["latitude"]) > lat_window:
                continue
            if haversine(
                courts[i]["latitude"], courts[i]["longitude"],
                courts[j]["latitude"], courts[j]["longitude"],
            ) <= threshold_m:
                union(i, j)

    groups = collections.defaultdict(list)
    for i in range(len(courts)):
        groups[find(i)].append(i)
    return list(groups.values())


def apply_overrides(groups, courts, overrides):
    """Fold human corrections into the distance-derived grouping.

    `merge` forces court IDs into one facility across any distance; `split`
    forces a court out of whatever group the distance rule put it in, onto its
    own. Split is applied after merge so an entry in both wins as a split — the
    conservative outcome, since a wrongly-merged facility silently pools two
    parks' queues while a wrongly-split one merely shows two pins.
    """
    index_by_id = {c["id"]: i for i, c in enumerate(courts)}
    group_of = {}
    for gi, members in enumerate(groups):
        for i in members:
            group_of[i] = gi

    unknown = []

    for merge_group in overrides.get("merge", []):
        indices = []
        for court_id in merge_group:
            if court_id not in index_by_id:
                unknown.append(court_id)
                continue
            indices.append(index_by_id[court_id])
        if len(indices) < 2:
            continue
        target = group_of[indices[0]]
        for i in indices[1:]:
            source = group_of[i]
            if source == target:
                continue
            for j, g in group_of.items():
                if g == source:
                    group_of[j] = target

    next_group = len(groups) + 1
    for court_id in overrides.get("split", []):
        if court_id not in index_by_id:
            unknown.append(court_id)
            continue
        group_of[index_by_id[court_id]] = next_group
        next_group += 1

    rebuilt = collections.defaultdict(list)
    for i, g in group_of.items():
        rebuilt[g].append(i)
    return list(rebuilt.values()), unknown


def load_overrides(path):
    if not os.path.exists(path):
        return {"merge": [], "split": []}
    with open(path) as handle:
        return json.load(handle)


def main():
    parser = argparse.ArgumentParser(
        description="Assign facilityId to every court in courts.json",
    )
    parser.add_argument("--path", default=DATASET)
    parser.add_argument("--overrides", default=OVERRIDES)
    parser.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD_M,
                        help=f"metres; default {DEFAULT_THRESHOLD_M}")
    parser.add_argument("--dry-run", action="store_true",
                        help="report the grouping without writing")
    args = parser.parse_args()

    with open(args.path) as handle:
        dataset = json.load(handle)
    courts = dataset["courts"]

    groups = cluster(courts, args.threshold)
    overrides = load_overrides(args.overrides)
    groups, unknown = apply_overrides(groups, courts, overrides)

    for court_id in unknown:
        print(f"  WARN override names unknown court {court_id}", file=sys.stderr)

    # Assign. Sorted member lists keep the output deterministic.
    assigned = 0
    multi = 0
    for members in groups:
        member_courts = [courts[i] for i in sorted(members)]
        fid = facility_id(member_courts)
        if len(member_courts) > 1:
            multi += 1
        for court in member_courts:
            court["facilityId"] = fid
            assigned += 1

    print(f"{len(courts)} courts -> {len(groups)} facilities "
          f"({multi} holding more than one surface), threshold {args.threshold:.0f}m")
    if overrides.get("merge") or overrides.get("split"):
        print(f"  overrides: {len(overrides.get('merge', []))} merge, "
              f"{len(overrides.get('split', []))} split")

    for members in sorted(groups, key=lambda m: -len(m)):
        if len(members) < 2:
            continue
        member_courts = [courts[i] for i in sorted(members)]
        names = ", ".join(c["name"].replace(" Basketball Court", "")
                          for c in member_courts)
        print(f"  {len(member_courts)}x  {names[:72]}")

    if args.dry_run:
        print("\ndry run — nothing written")
        return 0

    # Rewrite the envelope. `facilityId` is placed right after `city` so a
    # human scanning the file sees identity, then place, then grouping.
    ordered = []
    for court in courts:
        out = {}
        for key in ("id", "name", "latitude", "longitude", "address", "access",
                    "city", "facilityId", "hoops", "surface", "isLit",
                    "isCovered", "osmType", "osmId"):
            if key in court:
                out[key] = court[key]
        # Preserve anything the schema gains later without dropping it.
        for key, value in court.items():
            if key not in out:
                out[key] = value
        ordered.append(out)

    dataset["courts"] = ordered
    dataset["version"] = DATASET_VERSION

    with open(args.path, "w") as handle:
        json.dump(dataset, handle, indent=2, ensure_ascii=False)
        handle.write("\n")

    print(f"\nwrote {args.path} (dataset v{DATASET_VERSION}), "
          f"{assigned} courts stamped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
