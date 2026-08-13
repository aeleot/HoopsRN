#!/usr/bin/env python3
"""
Fetch basketball courts for a single city from the Overpass API and append
them into the bundled courts.json dataset.

Unlike build_courts.py (which processes a one-time bulk OSM extract for the
whole Triangle from local files), this hits Overpass live for one city at a
time — for extending coverage to a new city without re-running the full
bulk pipeline or needing fresh raw extract files.

One HTTP request per run: a single Overpass query unions the basketball
features with nearby named parks/schools (for label resolution), scoped
tightly to a radius around the target city rather than the whole region —
keeping the call itself cheap and avoiding a second round trip.

Usage:
    python3 tools/fetch_city_courts.py Cary
    python3 tools/fetch_city_courts.py Morrisville --radius-miles 6
    python3 tools/fetch_city_courts.py Apex --dry-run
"""
import argparse
import collections
import datetime
import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

# Identity, geography and classification rules are shared with build_courts.py
# so the two scripts can't mint different IDs — or make different public/school/
# restricted calls — for the same court. See courts_common.py.
from courts_common import (
    CITIES,
    EXCLUDE_ACCESS,
    EXCLUDE_LEISURE,
    access_kind,
    court_id,
    haversine,
    is_generic,
    label,
    truthy,
)

# Same mirrors CourtSearchService.swift used to try, so one rate-limited
# mirror doesn't block a fetch.
OVERPASS_ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]

DEFAULT_COURTS_JSON = Path(__file__).parent.parent / "hoopr" / "Resources" / "courts.json"


def centroid(el):
    if el.get("lat") is not None and el.get("lon") is not None:
        return el["lat"], el["lon"]
    if el.get("center"):
        return el["center"]["lat"], el["center"]["lon"]
    return None


def build_query(lat, lon, radius_m):
    """
    One Overpass request combining three feature-class queries:
    1. sport=basketball nodes/ways/relations (explicit courts)
    2. leisure=pitch + sport=basketball (pitched courts)
    3. Named parks/schools/sports centres for label resolution
    All with lightweight `out center tags` (no full polygon geometry).
    """
    return f"""
    [out:json][timeout:60];
    (
      node["sport"="basketball"](around:{radius_m},{lat},{lon});
      way["sport"="basketball"](around:{radius_m},{lat},{lon});
      relation["sport"="basketball"](around:{radius_m},{lat},{lon});
      way["leisure"="pitch"]["sport"="basketball"](around:{radius_m},{lat},{lon});
      relation["leisure"="pitch"]["sport"="basketball"](around:{radius_m},{lat},{lon});
    );
    out center tags;
    (
      way["leisure"~"^(park|pitch|sports_centre|recreation_ground)$"]["name"](around:{radius_m},{lat},{lon});
      relation["leisure"~"^(park|pitch|sports_centre|recreation_ground)$"]["name"](around:{radius_m},{lat},{lon});
      way["amenity"~"^(school|university|college)$"]["name"](around:{radius_m},{lat},{lon});
      relation["amenity"~"^(school|university|college)$"]["name"](around:{radius_m},{lat},{lon});
    );
    out center tags;
    """


def fetch_overpass(query):
    body = f"data={query}".encode("utf-8")
    last_error = None
    for endpoint in OVERPASS_ENDPOINTS:
        try:
            req = urllib.request.Request(
                endpoint,
                data=body,
                headers={
                    "Content-Type": "application/x-www-form-urlencoded",
                    "User-Agent": "HoopRN court-fetch script",
                },
            )
            with urllib.request.urlopen(req, timeout=65) as resp:
                return json.load(resp)
        except (urllib.error.URLError, TimeoutError) as e:
            last_error = e
            print(f"  ⚠ {endpoint} failed: {e}", file=sys.stderr)
            time.sleep(1)
            continue
    raise RuntimeError(f"All Overpass endpoints failed: {last_error}")


def nearest_site_name(lat, lon, sites, max_dist=150.0):
    best, bestd = None, max_dist
    for s in sites:
        d = haversine(lat, lon, s["lat"], s["lon"])
        if d < bestd:
            best, bestd = s, d
    return best["name"] if best else None


def process(elements, city):
    """Split raw elements into court candidates vs. named sites, then filter/dedupe the courts."""
    courts_raw = []
    sites = []
    for el in elements:
        tags = el.get("tags") or {}
        if tags.get("sport") == "basketball":
            courts_raw.append(el)
        elif tags.get("name"):
            c = centroid(el)
            if c:
                sites.append({"name": tags["name"], "lat": c[0], "lon": c[1]})

    dropped = collections.Counter()
    staged = []
    for el in courts_raw:
        tags = el.get("tags") or {}

        if tags.get("leisure") in EXCLUDE_LEISURE:
            dropped["arena/gym"] += 1
            continue
        if tags.get("access") in EXCLUDE_ACCESS:
            dropped["not public"] += 1
            continue

        c = centroid(el)
        if not c:
            dropped["no coordinates"] += 1
            continue
        lat, lon = c

        own = tags.get("name") or tags.get("official_name")
        if is_generic(own):
            name = label(nearest_site_name(lat, lon, sites), city)
        else:
            name = own

        # Indoor arenas sometimes tagged as pitches (e.g. Cameron Indoor Stadium).
        if tags.get("indoor") == "yes" or "stadium" in name.lower() or "arena" in name.lower():
            dropped["indoor arena"] += 1
            continue

        hoops = tags.get("hoops")
        try:
            hoops = int(hoops) if hoops else None
        except ValueError:
            hoops = None

        addr = " ".join(filter(None, [
            tags.get("addr:housenumber"), tags.get("addr:street"),
        ])).strip()

        staged.append({
            "id": court_id(el["type"], el["id"]),
            "name": name,
            "latitude": round(lat, 6),
            "longitude": round(lon, 6),
            "address": addr or f"{city}, NC",
            "access": access_kind(name),
            "city": city,
            "hoops": hoops,
            "surface": tags.get("surface"),
            "isLit": truthy(tags.get("lit")) if tags.get("lit") else None,
            "isCovered": truthy(tags.get("covered")) if tags.get("covered") else None,
            "osmType": el["type"],
            "osmId": el["id"],
        })

    # Tight 15m radius: genuine duplicate mappings only. Adjacent pitches in
    # the same park are separate courts and must survive.
    staged.sort(key=lambda c: (c["name"], -(c["hoops"] or 0)))
    kept = []
    for c in staged:
        dup = next(
            (k for k in kept
             if haversine(c["latitude"], c["longitude"], k["latitude"], k["longitude"]) < 15),
            None,
        )
        if dup:
            dropped["duplicate"] += 1
            if (c["hoops"] or 0) > (dup["hoops"] or 0):
                dup.update({k: v for k, v in c.items() if v is not None})
            continue
        kept.append(c)

    for c in kept:
        if c["name"] == "Basketball Court":
            c["name"] = f'{city} Basketball Court'

    return kept, dropped


def existing_suffix_range(existing_courts, city, base_name):
    """Highest existing ' #N' suffix for (city, base_name), and whether a bare (unsuffixed) entry exists."""
    pattern = re.compile(rf"^{re.escape(base_name)}(?: #(\d+))?$")
    max_n = 0
    has_bare = False
    for c in existing_courts:
        if c["city"] != city:
            continue
        m = pattern.match(c["name"])
        if m:
            if m.group(1):
                max_n = max(max_n, int(m.group(1)))
            else:
                has_bare = True
    return max_n, has_bare


def compute_additions(dataset, new_courts, city):
    """
    Figures out which of `new_courts` aren't already in `dataset`, and assigns
    final (possibly disambiguated) names to the ones that survive. Pure —
    doesn't touch `dataset` or any file, so dry-run can preview exactly what
    a real merge would produce.
    """
    existing_by_osm = {
        (c.get("osmType"), c.get("osmId")): c
        for c in dataset["courts"] if c.get("osmType") is not None
    }
    existing_coords = [(c["latitude"], c["longitude"]) for c in dataset["courts"]]

    to_add = []
    skipped = 0
    for court in new_courts:
        key = (court["osmType"], court["osmId"])
        if key in existing_by_osm:
            skipped += 1
            continue
        # Also check by proximity in case the same real court got a different OSM ID.
        if any(haversine(court["latitude"], court["longitude"], lat, lon) < 15
               for lat, lon in existing_coords):
            skipped += 1
            continue
        to_add.append(dict(court))

    # Disambiguate identically-named new courts against each other and against
    # whatever's already in the dataset for this city, continuing any existing
    # "#N" sequence rather than restarting it. (A pre-existing bare entry that
    # newly needs a "#1" of its own is left as-is — cosmetic only, not fixed up here.)
    by_name = collections.defaultdict(list)
    for c in to_add:
        by_name[c["name"]].append(c)

    for base_name, group in by_name.items():
        max_n, has_bare = existing_suffix_range(dataset["courts"], city, base_name)
        if not (has_bare or max_n > 0 or len(group) > 1):
            continue
        n = max_n
        for c in group:
            n += 1
            c["name"] = f"{base_name} #{n}"

    return to_add, skipped


def merge_into_dataset(dataset_path, new_courts, city):
    with open(dataset_path) as f:
        dataset = json.load(f)

    to_add, skipped = compute_additions(dataset, new_courts, city)

    dataset["courts"].extend(to_add)
    dataset["courts"].sort(key=lambda c: (c["city"], c["name"]))
    if city not in dataset["cities"]:
        dataset["cities"] = sorted(set(dataset["cities"]) | {city})
    dataset["generated"] = datetime.date.today().isoformat()

    with open(dataset_path, "w") as f:
        json.dump(dataset, f, indent=2, ensure_ascii=False)
        f.write("\n")

    return len(to_add), skipped


def resolve_city(name):
    if name in CITIES:
        return name
    match = next((c for c in CITIES if c.lower() == name.lower()), None)
    if not match:
        print(f"Unknown city '{name}'. Known cities: {', '.join(sorted(CITIES))}", file=sys.stderr)
        print("(Add coordinates to the CITIES dict in this script to support another city.)", file=sys.stderr)
        sys.exit(1)
    return match


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("city", help=f"Target city. Known: {', '.join(sorted(CITIES))}")
    parser.add_argument("--radius-miles", type=float, default=7.0,
                         help="Search radius around the city center (default: 7 miles)")
    parser.add_argument("--courts-json", default=str(DEFAULT_COURTS_JSON),
                         help="Path to courts.json to append into")
    parser.add_argument("--dry-run", action="store_true",
                         help="Fetch and process, but don't write to courts.json")
    args = parser.parse_args()

    city = resolve_city(args.city)
    lat, lon = CITIES[city]
    radius_m = args.radius_miles * 1609.34

    print(f"Fetching basketball courts within {args.radius_miles} mi of {city} ({lat}, {lon})...")
    data = fetch_overpass(build_query(lat, lon, radius_m))
    print(f"  → {len(data['elements'])} raw elements returned")

    courts, dropped = process(data["elements"], city)
    print(f"  → {len(courts)} courts kept after filtering/dedup")
    if dropped:
        print(f"  → dropped: {dict(dropped)}")

    dataset_path = Path(args.courts_json)
    with open(dataset_path) as f:
        dataset = json.load(f)
    to_add, skipped = compute_additions(dataset, courts, city)

    if args.dry_run:
        print(f"\n--dry-run: would append {len(to_add)} court(s) to {dataset_path}"
              f" ({skipped} already present, skipped):")
        for c in to_add:
            print(f"  - {c['name']} ({c['latitude']}, {c['longitude']})")
        return

    added, skipped = merge_into_dataset(dataset_path, courts, city)
    print(f"\n✓ Appended {added} new court(s) to {dataset_path}")
    if skipped:
        print(f"  ({skipped} already present, skipped)")


if __name__ == "__main__":
    main()
