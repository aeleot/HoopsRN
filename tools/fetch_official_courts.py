#!/usr/bin/env python3
"""
Harvest the official municipal court/park data the Triangle governments publish.

OSM tells us where a court's asphalt is. It does **not** reliably tell us the
park's real name, its street address, which town it's in, or whether it has
lights — `tools/audit_courts.py` measures that gap: 0 of 214 courts have a street
address, and `isLit` is answered for 9.8%.

The departments that own the courts publish all of it, for free. This script
pulls their layers into a committed snapshot; `enrich_courts.py` conflates the
snapshot into `courts.json`.

## Why a committed snapshot rather than fetching at build time

Four reasons, in order of how much they'd hurt:

1. A dataset build must be **reproducible**. Live endpoints change under you.
2. These are other people's servers. One fetch per deliberate refresh, not one
   per build.
3. The snapshot is the audit trail for a field's provenance — "Raleigh said
   asphalt on 2026-09-22" is only checkable if that response is kept.
4. It keeps `enrich_courts.py` offline and fast, so it can be re-run freely.

The snapshot lands in `tools/official_sources/`, **not** `hoopr/Resources/` —
that directory is a synchronized Xcode group, so anything dropped there ships
inside the app (`COURT_DATASET.md`).

## Grain matters, and is recorded

`raleigh_courts` is **court-level**: a row is one playing surface, so its
`Lighting` is a fact about that court. `wake_parks` and `durham_parks` are
**park-level**: a row is a whole park, so its lights may be on the ballfield.
Each source carries a `grain` field for exactly this reason, and
`enrich_courts.py` refuses to write an amenity from a park-level source. See
`plans/COURT_DATA_SOURCES.md` §4.

    python3 tools/fetch_official_courts.py
    python3 tools/fetch_official_courts.py --only raleigh_courts
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "tools", "official_sources")

UA = {"User-Agent": "hoopsRN court-data script (github.com/hoopsRN)"}

# Each source: the layer, what to keep, and — load-bearing — its grain.
#
# `where` is pushed to the server so we download the basketball subset rather
# than every park in the county. `park_level` sources keep their basketball flag
# anyway, because a park that says it has basketball and has no court in our
# dataset is a discovery lead (see enrich_courts.py's worklist).
SOURCES = {
    "raleigh_courts": {
        "url": "https://services.arcgis.com/v400IkDOw1ad7Yad/arcgis/rest/services"
               "/Raleigh_Parks_Athletic_Courts_and_Fields/FeatureServer/0",
        "where": "Basketball NOT IN ('No','') AND Basketball IS NOT NULL",
        "fields": ["LocationName", "Title", "Surface", "Type", "IndoorOutdoor",
                   "Basketball", "Lighting", "Status", "Features", "Fencing"],
        "grain": "court",
        "geometry": True,
        "attribution": "City of Raleigh Parks, Recreation and Cultural Resources "
                       "(Open Raleigh Data Policy)",
    },
    "raleigh_park_bounds": {
        "url": "https://maps.raleighnc.gov/arcgis/rest/services/Parks/Greenway"
               "/MapServer/5",
        "where": "1=1",
        "fields": ["*"],
        "grain": "park",
        "geometry": True,
        "attribution": "City of Raleigh Parks, Recreation and Cultural Resources "
                       "(Open Raleigh Data Policy)",
    },
    "wake_parks": {
        "url": "https://services1.arcgis.com/a7CWfuGP5ZnLYE7I/arcgis/rest/services"
               "/Wake_Parks_Public/FeatureServer/0",
        # Every park, not just the basketball ones: a park with
        # OUTDOORBASKETBALL='No' that contains one of our courts is a
        # contradiction worth surfacing, and the address is useful regardless.
        "where": "1=1",
        "fields": ["NAME", "ALIAS1", "ALIAS2", "JURISDICTION", "ADDRESS",
                   "Address2", "URL", "PHONE", "OUTDOORBASKETBALL", "GYM",
                   "RESTROOMS", "Lat", "Lon", "Notes"],
        "grain": "park",
        "geometry": False,   # point layer; Lat/Lon are already attributes
        "attribution": "Wake County Government",
    },
    "durham_parks": {
        "url": "https://webgis2.durhamnc.gov/server/rest/services/PublicServices"
               "/Community/MapServer/8",
        "where": "1=1",
        "fields": ["NAME", "FULLADDR", "PHONENUM", "PROPTYPE", "PARKURL",
                   "BASKETBALL", "LIGHTS", "RESTROOM", "PLAYGROUND"],
        "grain": "park",
        "geometry": True,
        "attribution": "City of Durham",
    },
    "chapelhill_facilities": {
        "url": "https://services2.arcgis.com/7KRXAKALbBGlCW77/arcgis/rest/services"
               "/Parks_and_Recreation_Facilities/FeatureServer/0",
        "where": "1=1",
        "fields": ["Facility_Type", "Facility_Name", "Facility_Address", "Zipcode",
                   "Season_of_Operation", "Main_Feature", "Secondary_Feature",
                   "Tertiary_Feature", "Quaternary_Feature"],
        "grain": "park",
        "geometry": True,
        "attribution": "Town of Chapel Hill",
    },
}


def fetch(url, params, attempts=3):
    body = urllib.parse.urlencode(params).encode("utf-8")
    last = None
    for i in range(attempts):
        try:
            req = urllib.request.Request(
                url, data=body,
                headers={**UA, "Content-Type": "application/x-www-form-urlencoded"},
            )
            with urllib.request.urlopen(req, timeout=120) as resp:
                return json.load(resp)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            last = e
            print(f"    attempt {i + 1} failed: {e}", file=sys.stderr)
            time.sleep(2 * (i + 1))
    raise RuntimeError(f"{url} failed after {attempts} attempts: {last}")


def centroid(ring):
    """Unweighted mean of a ring's vertices.

    Good enough: it's used to place a *label point* for a park or court, and every
    consumer either does real point-in-polygon against the rings (which are kept)
    or wants a rough centre. A proper area centroid would be more correct and no
    call site needs it.
    """
    return (sum(p[1] for p in ring) / len(ring),
            sum(p[0] for p in ring) / len(ring))


def harvest(name, spec):
    print(f"  {name} ({spec['grain']}-level)")
    params = {
        "where": spec["where"],
        "outFields": ",".join(spec["fields"]),
        "returnGeometry": "true" if spec["geometry"] else "false",
        "outSR": "4326",
        "f": "json",
        "resultRecordCount": 2000,
    }
    data = fetch(spec["url"].rstrip("/") + "/query", params)
    if "error" in data:
        raise RuntimeError(f"{name}: {data['error']}")
    # The layer root also returns 200 with valid JSON — it just has no
    # `features` key. Treating that as "zero records" is how this failed
    # silently the first time, so require the key rather than defaulting it.
    if "features" not in data:
        raise RuntimeError(
            f"{name}: response has no 'features' (queried the layer root?)"
        )

    records = []
    for feat in data.get("features", []):
        rec = {"attributes": feat.get("attributes", {})}
        geom = feat.get("geometry") or {}
        if "rings" in geom and geom["rings"]:
            rec["rings"] = geom["rings"]
            lat, lon = centroid(geom["rings"][0])
            rec["lat"], rec["lon"] = lat, lon
        elif "x" in geom and geom.get("x") is not None:
            rec["lat"], rec["lon"] = geom["y"], geom["x"]
        else:
            # Point layers that publish coordinates as plain attributes.
            a = rec["attributes"]
            if a.get("Lat") is not None and a.get("Lon") is not None:
                rec["lat"], rec["lon"] = float(a["Lat"]), float(a["Lon"])
        records.append(rec)

    if not records:
        raise RuntimeError(f"{name}: query succeeded but returned no records")

    located = sum(1 for r in records if "lat" in r)
    with_rings = sum(1 for r in records if "rings" in r)
    print(f"    {len(records)} records, {located} located"
          f"{f', {with_rings} with polygons' if with_rings else ''}")
    if data.get("exceededTransferLimit"):
        print("    WARN server capped the result set — paging needed",
              file=sys.stderr)
    return {
        "source": name,
        "grain": spec["grain"],
        "url": spec["url"],
        "where": spec["where"],
        "attribution": spec["attribution"],
        "fetched": time.strftime("%Y-%m-%d"),
        "records": records,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--only", action="append",
                    help="fetch just this source (repeatable)")
    ap.add_argument("--out", default=OUT_DIR)
    args = ap.parse_args()

    names = args.only or list(SOURCES)
    unknown = [n for n in names if n not in SOURCES]
    if unknown:
        print(f"unknown source(s): {unknown}\nknown: {list(SOURCES)}",
              file=sys.stderr)
        return 2

    os.makedirs(args.out, exist_ok=True)
    print(f"harvesting {len(names)} source(s) -> {args.out}")

    failed = []
    for name in names:
        try:
            payload = harvest(name, SOURCES[name])
        except Exception as e:
            print(f"    FAILED: {e}", file=sys.stderr)
            failed.append(name)
            continue
        path = os.path.join(args.out, f"{name}.json")
        with open(path, "w") as h:
            json.dump(payload, h, indent=1, ensure_ascii=False, sort_keys=True)
            h.write("\n")

    if failed:
        print(f"\n{len(failed)} source(s) failed: {failed}", file=sys.stderr)
        print("Existing snapshots for those are left untouched.", file=sys.stderr)
        return 1
    print("\ndone")
    return 0


if __name__ == "__main__":
    sys.exit(main())
