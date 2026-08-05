#!/usr/bin/env python3
"""
Build the bundled HoopRN court dataset from a one-time OSM/Overpass extract.

Input:  raw_triangle.json (basketball features), sites_raw.json (named parks/schools)
Output: courts.json  — cleaned, deduped, stably-identified courts for Durham + Raleigh

Re-runnable: court IDs are uuid5 over the OSM type/id, so re-extracting later
produces the same IDs for the same real-world courts.
"""
import json, math, uuid, datetime, collections

NAMESPACE = uuid.UUID("6f2a1c4e-9b3d-4f70-8a21-5c0d7e8b1234")  # HoopRN court namespace

# Nearest-centroid city assignment across the Triangle. Courts are labeled with
# whichever city they're closest to; we then keep only the ones we're launching in.
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
LAUNCH_CITIES = {"Durham", "Raleigh"}

GENERIC_NAMES = {
    "basketball court", "basketball courts", "private basketball court",
    "outdoor basketball court", "court", "basketball",
}
# Division-I arenas and gyms — real basketball, but you cannot run pickup there.
EXCLUDE_LEISURE = {"stadium", "sports_centre"}
# Access values that mean the public can't play.
EXCLUDE_ACCESS = {"private", "customers", "permit", "no"}


def haversine(lat1, lon1, lat2, lon2):
    R = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))


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


def is_generic(name):
    return not name or name.strip().lower() in GENERIC_NAMES


# Courts that exist but that a stranger can't simply walk onto. OSM rarely tags
# these access=private, so classify from the place they belong to.
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


def access_kind(name):
    n = name.lower()
    if any(w in n for w in RESTRICTED_WORDS):
        return "restricted"
    if any(w in n for w in SCHOOL_WORDS):
        return "school"
    return "public"


def truthy(v):
    return v not in (None, "no", "false", "0")


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


def label(site_name, city):
    if not site_name:
        return "Basketball Court"
    if "basketball" in site_name.lower():
        return site_name
    return f"{site_name} Basketball Court"


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
