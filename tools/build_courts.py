#!/usr/bin/env python3
"""
Build the bundled HoopRN court dataset from a one-time OSM/Overpass extract.

Input:  raw_triangle.json (basketball features), sites_raw.json (named parks/schools)
Output: courts.json  — cleaned, deduped, stably-identified courts for Durham + Raleigh

Re-runnable: court IDs are uuid5 over the OSM type/id, so re-extracting later
produces the same IDs for the same real-world courts.
"""
import json, datetime, collections

# Identity, geography and classification rules are shared with
# fetch_city_courts.py so the two scripts can't mint different IDs — or make
# different public/school/restricted calls — for the same court. See
# courts_common.py.
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

# Which of the Triangle cities *this script's* build ships. Local to this
# script: the per-city fetcher scopes by radius instead.
#
# The shipped `courts.json` has six cities, not these two — Apex, Cary, Chapel
# Hill and Morrisville were appended afterwards by `fetch_city_courts.py`. This
# constant describes the original bulk build, which is no longer re-runnable
# (its Overpass extracts aren't in the repo), so don't read it as the dataset's
# contents.
LAUNCH_CITIES = {"Durham", "Raleigh"}


def centroid(el):
    """Coordinate for a node, way, or relation from an Overpass extract."""
    if el.get("lat") is not None and el.get("lon") is not None:
        return el["lat"], el["lon"]
    if el.get("center"):
        return el["center"]["lat"], el["center"]["lon"]
    ring = polygon_of(el)
    if ring:
        return (sum(p[0] for p in ring) / len(ring),
                sum(p[1] for p in ring) / len(ring))
    return None


def polygon_of(el):
    """Outer ring as [(lat, lon), ...] for ways and multipolygon relations."""
    if el.get("geometry"):
        return [(p["lat"], p["lon"]) for p in el["geometry"] if "lat" in p]
    pts = []
    for m in el.get("members", []):
        if m.get("role") in ("outer", "") and m.get("geometry"):
            pts += [(p["lat"], p["lon"]) for p in m["geometry"] if "lat" in p]
    return pts


def point_in_ring(lat, lon, ring):
    """Ray casting. Rings here are small enough that planar math is fine."""
    inside = False
    n = len(ring)
    for i in range(n):
        y1, x1 = ring[i]
        y2, x2 = ring[(i + 1) % n]
        if (y1 > lat) != (y2 > lat):
            xin = (x2 - x1) * (lat - y1) / (y2 - y1) + x1
            if lon < xin:
                inside = not inside
    return inside


def bbox_of(ring):
    lats = [p[0] for p in ring]
    lons = [p[1] for p in ring]
    return min(lats), max(lats), min(lons), max(lons)


# ---------------------------------------------------------------- load sites
sites = []
for el in json.load(open("sites_raw.json"))["elements"]:
    tags = el.get("tags") or {}
    name = tags.get("name")
    if not name:
        continue
    ring = polygon_of(el)
    if len(ring) < 3:
        continue
    c = centroid(el)
    if not c:
        continue
    # A pitch polygon named after its park is a better label than the park itself,
    # so keep specificity ranking: smaller/more specific features win ties.
    kind = tags.get("leisure") or tags.get("amenity") or tags.get("landuse")
    sites.append({
        "name": name, "kind": kind, "ring": ring,
        "bbox": bbox_of(ring), "center": c,
    })
primary_count = len(sites)

# Lower-priority fallbacks: playgrounds, community centres, subdivisions,
# apartment complexes, neighbourhoods. Only consulted when nothing better exists.
fallback_sites = []
for el in json.load(open("sites2_raw.json"))["elements"]:
    tags = el.get("tags") or {}
    name = tags.get("name")
    if not name:
        continue
    c = centroid(el)
    if not c:
        continue
    ring = polygon_of(el)
    fallback_sites.append({
        "name": name,
        "kind": tags.get("leisure") or tags.get("amenity") or tags.get("landuse") or tags.get("place"),
        "ring": ring,
        "bbox": bbox_of(ring) if len(ring) >= 3 else None,
        "center": c,
    })
print(f"named sites: {primary_count} primary + {len(fallback_sites)} fallback")


def site_for(lat, lon):
    """Containing site, else nearest named site within 150m."""
    hits = []
    for s in sites:
        mnla, mxla, mnlo, mxlo = s["bbox"]
        if mnla <= lat <= mxla and mnlo <= lon <= mxlo and point_in_ring(lat, lon, s["ring"]):
            hits.append(s)
    if hits:
        # Prefer the smallest containing polygon — the most specific place name.
        def area(s):
            mnla, mxla, mnlo, mxlo = s["bbox"]
            return (mxla - mnla) * (mxlo - mnlo)
        return min(hits, key=area)["name"]

    best, bestd = None, 151.0
    for s in sites:
        d = haversine(lat, lon, s["center"][0], s["center"][1])
        if d < bestd:
            best, bestd = s, d
    if best:
        return best["name"]

    # Nothing park-like nearby: fall back to whatever place this sits in.
    for s in fallback_sites:
        if s["bbox"]:
            mnla, mxla, mnlo, mxlo = s["bbox"]
            if mnla <= lat <= mxla and mnlo <= lon <= mxlo and point_in_ring(lat, lon, s["ring"]):
                return s["name"]
    best, bestd = None, 300.0
    for s in fallback_sites:
        d = haversine(lat, lon, s["center"][0], s["center"][1])
        if d < bestd:
            best, bestd = s, d
    return best["name"] if best else None


# --------------------------------------------------------------- load courts
raw = json.load(open("raw_triangle.json"))["elements"]
dropped = collections.Counter()
staged = []

for el in raw:
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

    city, cd = min(
        ((n, haversine(lat, lon, p[0], p[1])) for n, p in CITIES.items()),
        key=lambda kv: kv[1],
    )

    own = tags.get("name") or tags.get("official_name")
    if is_generic(own):
        name = label(site_for(lat, lon), city)
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
        "_cityDist": cd,
    })

# ------------------------------------------------------------------- dedupe
# Tight 15m radius: genuine duplicate mappings only. Adjacent pitches in the
# same park are separate courts and must survive.
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
        # Keep whichever record carries more detail.
        if (c["hoops"] or 0) > (dup["hoops"] or 0):
            dup.update({k: v for k, v in c.items() if v is not None})
        continue
    kept.append(c)

launch = [c for c in kept if c["city"] in LAUNCH_CITIES]
other = collections.Counter(c["city"] for c in kept if c["city"] not in LAUNCH_CITIES)

for c in launch:
    del c["_cityDist"]
launch.sort(key=lambda c: (c["city"], c["name"]))

# Adjacent pitches in one park share a name; number them so lists disambiguate.
for c in launch:
    if c["name"] == "Basketball Court":
        c["name"] = f'{c["city"]} Basketball Court'

counts = collections.Counter((c["city"], c["name"]) for c in launch)
seen = collections.Counter()
for c in launch:
    key = (c["city"], c["name"])
    if counts[key] > 1:
        seen[key] += 1
        c["name"] = f'{c["name"]} #{seen[key]}'


out = {
    "version": 1,
    "generated": datetime.date.today().isoformat(),
    "attribution": "Court data © OpenStreetMap contributors, ODbL 1.0",
    "cities": sorted(LAUNCH_CITIES),
    "courts": launch,
}
with open("courts.json", "w") as f:
    json.dump(out, f, indent=2, ensure_ascii=False)

print("\ndropped:", dict(dropped))
print("kept (all Triangle):", len(kept))
print("launch cities:", collections.Counter(c["city"] for c in launch))
print("excluded other cities:", dict(other))
named = sum(1 for c in launch if c["name"] != "Basketball Court")
print(f"\nresolved names: {named}/{len(launch)}")
print("with hoops:", sum(1 for c in launch if c["hoops"]))
print("with surface:", sum(1 for c in launch if c["surface"]))
print("lit:", sum(1 for c in launch if c["isLit"]))
print("access:", collections.Counter(c["access"] for c in launch))
