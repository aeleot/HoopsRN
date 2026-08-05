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
import math
import re
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

# Same namespace as build_courts.py — IDs stay stable for the same real-world
# court across scripts and re-fetches.
NAMESPACE = uuid.UUID("6f2a1c4e-9b3d-4f70-8a21-5c0d7e8b1234")

# Same mirrors CourtSearchService.swift used to try, so one rate-limited
# mirror doesn't block a fetch.
OVERPASS_ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]

# Same Triangle city centers as build_courts.py's CITIES dict.
CITIES = {
    "Durham":        (35.9940, -78.8986),
    "Raleigh":       (35.7796, -78.6382),
    "Chapel Hill":   (35.9132, -79.0558),
    "Carrboro":      (35.9101, -79.0753),
    "Cary":          (35.7915, -78.7811),
    "Apex":          (35.7327, -78.8503),
    "Morrisville":   (35.8235, -78.8256),
    "Wake Forest":   (35.9799, -78.5097),
    "Garner":        (35.7113, -78.6142),
    "Hillsborough":  (36.0754, -79.0997),
    "Knightdale":    (35.7877, -78.4805),
    "Holly Springs": (35.6513, -78.8336),
    "Rolesville":    (35.9232, -78.4675),
}

GENERIC_NAMES = {
    "basketball court", "basketball courts", "private basketball court",
    "outdoor basketball court", "court", "basketball",
}
# Division-I arenas and gyms — real basketball, but you cannot run pickup there.
EXCLUDE_LEISURE = {"stadium", "sports_centre"}
# Access values that mean the public can't play.
EXCLUDE_ACCESS = {"private", "customers", "permit", "no"}

RESTRICTED_WORDS = (
    "apartment", "apartments", "hotel", "extended stay", "swim & tennis",
    "swim and tennis", "country club", "campus crossings", "greek village",
    "olde towne", "the wilde", "meadow ridge", "village green", "greencastle",
    "condo", "townhome", "residences", "lodge", "inn ",
)
SCHOOL_WORDS = (
    "school", "elementary", "middle", "high school", "academy",
    "university", "college", "montessori",
)

DEFAULT_COURTS_JSON = Path(__file__).parent.parent / "hoopr" / "Resources" / "courts.json"


def haversine(lat1, lon1, lat2, lon2):
    R = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))


def centroid(el):
    if el.get("lat") is not None and el.get("lon") is not None:
        return el["lat"], el["lon"]
    if el.get("center"):
        return el["center"]["lat"], el["center"]["lon"]
    return None


def is_generic(name):
    return not name or name.strip().lower() in GENERIC_NAMES


def access_kind(name):
    n = name.lower()
    if any(w in n for w in RESTRICTED_WORDS):
        return "restricted"
    if any(w in n for w in SCHOOL_WORDS):
        return "school"
    return "public"


def truthy(v):
    return v not in (None, "no", "false", "0")


def label(site_name, city):
    if not site_name:
        return "Basketball Court"
    if "basketball" in site_name.lower():
        return site_name
    return f"{site_name} Basketball Court"


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
            "id": str(uuid.uuid5(NAMESPACE, f"{el['type']}/{el['id']}")),
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
