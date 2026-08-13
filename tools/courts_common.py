#!/usr/bin/env python3
"""
Constants and pure helpers shared by the two court-dataset scripts.

`build_courts.py` (one-time bulk OSM extract) and `fetch_city_courts.py` (live
per-city Overpass fetch) both mint courts for the same dataset, so they have to
agree on what a court *is*: how it's identified, which city it belongs to, which
names are too generic to keep, and what counts as reachable by the public.

They previously each carried their own copy of all of that. `NAMESPACE` is the
reason that mattered most — it is the uuid5 seed for court IDs, and two copies
that drift would mint *different* IDs for the same real-world court, silently
orphaning every `UserProfile.homeCourtId` and `Game.courtId` pointing at it.
Nothing in the app or the test suite would detect that. One definition, here.

Import-safe: this module is constants and pure functions only, with no
top-level I/O, so importing it can't trigger either script's pipeline.
"""
import math
import uuid

# The uuid5 seed for court IDs. **Never change this.** Court IDs are uuid5 over
# the OSM type/id under this namespace, which is what makes re-extraction
# produce the same ID for the same real-world court — and what makes stored
# references to a court survive a dataset rebuild.
NAMESPACE = uuid.UUID("6f2a1c4e-9b3d-4f70-8a21-5c0d7e8b1234")

# Nearest-centroid city assignment across the Triangle. Courts are labeled with
# whichever city they're closest to; each script then keeps whichever subset it
# is launching or fetching for.
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

# Names that identify nothing — a court called "Basketball Court" needs its
# label derived from the park or school it sits in instead.
GENERIC_NAMES = {
    "basketball court", "basketball courts", "private basketball court",
    "outdoor basketball court", "court", "basketball",
}

# Division-I arenas and gyms — real basketball, but you cannot run pickup there.
EXCLUDE_LEISURE = {"stadium", "sports_centre"}

# Access values that mean the public can't play.
EXCLUDE_ACCESS = {"private", "customers", "permit", "no"}

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


def haversine(lat1, lon1, lat2, lon2):
    """Great-circle distance in meters."""
    R = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))


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


def court_id(osm_type, osm_id):
    """
    The stable ID for a court, from its OSM identity. Both scripts mint IDs this
    way; going through one function is what keeps the NAMESPACE from being
    applied two different ways.
    """
    return str(uuid.uuid5(NAMESPACE, f"{osm_type}/{osm_id}"))
