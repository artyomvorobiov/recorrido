#!/usr/bin/env python3
"""Checks the curated catalog (Shared/Catalog/city-*.json) against Wikipedia.

For every stop with a `wiki` title it verifies that the article exists and
compares the stop's coordinate with the article's one. Big differences are
printed together with the Wikipedia coordinate, so they are easy to fix.
Stops that Wikipedia can't place (no article, or one without coordinates)
are looked up on OpenStreetMap near where the catalog puts them instead;
when the map knows no place by that name, the sights around the pin are
listed, so a misplaced pin is still easy to spot.

Usage: python3 scripts/validate_catalog.py [--tolerance 250] [--stops id,id=name|name]
--stops looks those stops up on OpenStreetMap too, even when Wikipedia
places them, and lists the sights around their pins; names after "=" are
searched before the stop's own title.
Exit code is 0 even with warnings: the network may be flaky in CI.
"""
import argparse
import glob
import json
import math
import os
import time
import urllib.parse
import urllib.request

UA = "RecorridoContentCheck/1.0 (https://github.com/artyomvorobiov/recorrido)"
NOMINATIM = "https://nominatim.openstreetmap.org/search?"
OVERPASS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def api(lang, params, attempts=5):
    params = {**params, "format": "json", "formatversion": "2", "action": "query"}
    url = f"https://{lang}.wikipedia.org/w/api.php?" + urllib.parse.urlencode(params)
    for attempt in range(attempts):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            if "error" in data and "busy" in data["error"].get("code", "") and attempt < attempts - 1:
                time.sleep(1.5 * (attempt + 1))
                continue
            return data
        except Exception as error:  # noqa: BLE001
            if attempt == attempts - 1:
                raise
            time.sleep(1.5 * (attempt + 1))
    return {}


# Lakes, rivers and regions have a coordinate somewhere in the middle; a stop
# on their shore is fine wherever it is.
AREA_TYPES = {"waterbody", "river", "isle", "forest", "glacier", "mountain", "adm1st", "adm2nd", "adm3rd"}
AREA = "area"
# A stop anywhere in a town or village is fine, but not one in the next district.
SETTLEMENT_TYPES = {"city"}
SETTLEMENT_TOLERANCE = 5000
settlements = set()


def search(lang, text, near=None, limit=5):
    """Titles that match `text`, optionally only near a coordinate."""
    query = text.replace("«", "").replace("»", "")
    if near:
        query += f" nearcoord:5km,{near[0]},{near[1]}"
    data = api(lang, {"list": "search", "srsearch": query, "srlimit": str(limit), "srprop": ""})
    return [item["title"] for item in data.get("query", {}).get("search", [])]


def suggest_titles(lang, title, coordinate):
    """Likely right titles for a missing article, with their distance to the stop."""
    base = title.split(" (")[0]
    found = []
    for text, near in ((base, coordinate), (title, None)):
        try:
            for item in search(lang, text, near):
                if item not in found:
                    found.append(item)
        except Exception:  # noqa: BLE001
            pass
        time.sleep(0.3)
    if not found:
        return "no suggestions"
    info = lookup(lang, found[:8])
    parts = []
    for item in found[:8]:
        _, where, _, _ = info.get(item, (False, None, item, False))
        if where and where != AREA:
            parts.append(f"{item} ({int(distance(coordinate, where))} m)")
        else:
            parts.append(item)
    return " | ".join(parts)


# Bus stops and stations are named after the sights they serve.
TRANSPORT = {"railway", "public_transport", "highway/bus_stop", "highway/platform"}


def osm_search(text, near, radius=0.05):
    """OpenStreetMap places called `text` within a few kilometres of `near`, nearest first."""
    lat, lon = near
    box = (lon - 2 * radius, lat + radius, lon + 2 * radius, lat - radius)
    params = {"q": text, "format": "jsonv2", "limit": "5", "bounded": "1", "accept-language": "ru",
              "viewbox": ",".join(f"{value:.5f}" for value in box)}
    req = urllib.request.Request(NOMINATIM + urllib.parse.urlencode(params), headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as resp:
        places = json.loads(resp.read().decode("utf-8"))
    time.sleep(1.1)  # Nominatim allows one request a second
    found = [((float(p["lat"]), float(p["lon"])), p.get("name") or p["display_name"].split(",")[0],
              f"{p.get('category', '')}/{p.get('type', '')}") for p in places]
    # A bus stop named after a museum is not the museum.
    return sorted(found, key=lambda place: ({place[2], place[2].split("/")[0]} & TRANSPORT != set(),
                                             distance(near, place[0])))


def osm_check(stop, queries=(), radius=0.05):
    """(searched text, places) for `queries`, the stop's title, its spellings and its article's title.

    Map names are often longer or shorter than ours ("Дом памяти М. И. Цветаевой"),
    so the last try is the stop's last proper name alone.
    """
    title = stop["title"].get("ru", "")
    article = (stop.get("wiki") or {}).get("ru", "").split(" (")[0]
    words = title.replace("«", "").replace("»", "").replace("-", " ").split()
    names = [word for word in words[1:] if word[:1].isupper()]
    texts = []
    for text in (*queries, title, title.replace("ё", "е"), article, names[-1] if names else ""):
        text = text.replace("«", "").replace("»", "").strip()
        if text and text not in texts:
            texts.append(text)
    for text in texts:
        found = osm_search(text, stop["coordinate"], radius)
        if found:
            return text, found
    return texts[0] if texts else "", []


overpass_failures = 0


def osm_nearby(near, radius=1500, limit=8):
    """Named sights within `radius` metres of `near`, nearest first: (metres, name)."""
    global overpass_failures
    # When the servers are down, waiting on every stop would outlast the CI job.
    if overpass_failures >= 3:
        raise RuntimeError("skipped after repeated failures")
    around = f"(around:{radius},{near[0]},{near[1]})"
    query = f"""[out:json][timeout:20];
(
  nwr{around}["name"]["tourism"~"museum|attraction|viewpoint|artwork|gallery"];
  nwr{around}["name"]["historic"];
  nwr{around}["name"]["amenity"="place_of_worship"];
  nwr{around}["name"]["natural"~"spring|peak|cliff|beach"];
);
out center;"""
    data = urllib.parse.urlencode({"data": query}).encode()
    for attempt, server in enumerate(OVERPASS):
        try:
            req = urllib.request.Request(server, data=data, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=30) as resp:
                elements = json.loads(resp.read().decode("utf-8")).get("elements", [])
            break
        except Exception:  # noqa: BLE001
            if attempt == len(OVERPASS) - 1:
                overpass_failures += 1
                raise
            time.sleep(3)  # try the mirror
    overpass_failures = 0
    time.sleep(1)
    places = {}
    for element in elements:
        where = element.get("center") or element
        d = int(distance(near, (where["lat"], where["lon"])))
        name = element["tags"]["name"]
        places[name] = min(d, places.get(name, d))
    return sorted((d, name) for name, d in places.items())[:limit]


def distance(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 2 * 6371000 * math.asin(min(1, math.sqrt(h)))


def lookup(lang, titles):
    """title -> (exists, coordinate or None, final title)"""
    result = {}
    for start in range(0, len(titles), 40):
        batch = titles[start:start + 40]
        data = api(lang, {"titles": "|".join(batch), "redirects": "1", "prop": "coordinates|pageimages",
                          "piprop": "name", "pilimit": "max", "colimit": "max", "coprop": "type"})
        q = data.get("query", {})
        mapping = {t: t for t in batch}
        for item in q.get("normalized", []):
            for k, v in mapping.items():
                if v == item["from"]:
                    mapping[k] = item["to"]
        for item in q.get("redirects", []):
            for k, v in mapping.items():
                if v == item["from"]:
                    mapping[k] = item["to"]
        pages = {p["title"]: p for p in q.get("pages", [])}
        for title in batch:
            page = pages.get(mapping[title])
            if not page or page.get("missing"):
                result[title] = (False, None, mapping[title], False)
                continue
            coords = page.get("coordinates")
            coordinate = (coords[0]["lat"], coords[0]["lon"]) if coords else None
            kind = coords[0].get("type", "").split("(")[0] if coords else ""
            if kind in AREA_TYPES:
                coordinate = AREA
            elif kind in SETTLEMENT_TYPES:
                settlements.add((lang, title))
            result[title] = (True, coordinate, mapping[title], bool(page.get("pageimage")))
        time.sleep(0.3)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tolerance", type=float, default=250)
    parser.add_argument("--stops", default="",
                        help="stop ids to look up on OpenStreetMap as well, comma-separated; "
                             "'id=name|other name' searches those names first")
    args = parser.parse_args()

    stops = []
    for path in sorted(glob.glob(os.path.join(ROOT, "Shared/Catalog/city-*.json"))):
        data = json.load(open(path, encoding="utf-8"))
        for route in data["routes"]:
            for day in route["days"]:
                for stop in day["stops"]:
                    stops.append((os.path.basename(path), route["id"], stop))

    by_lang = {}
    for _, _, stop in stops:
        for lang, title in (stop.get("wiki") or {}).items():
            by_lang.setdefault(lang, set()).add(title)

    info = {}
    for lang, titles in by_lang.items():
        info[lang] = lookup(lang, sorted(titles))

    missing, far, no_coord, no_image = [], [], [], []
    suggestions = {}
    placed = set()
    for file, route, stop in stops:
        wiki = stop.get("wiki") or {}
        # The Russian article first; another language's coordinate stands in when it has none.
        langs = sorted(wiki, key=lambda lang: lang != "ru")
        found = []
        for lang in langs:
            title = wiki[lang]
            exists, coordinate, final, has_image = info[lang].get(title, (False, None, title, False))
            if not exists:
                hint = suggest_titles(lang, title, stop["coordinate"])
                missing.append(f"{file} {stop['id']}: [{lang}] '{title}' not found\n    try: {hint}")
                continue
            found.append(f"[{lang}] {title}")
            if lang == langs[0] and not has_image:
                no_image.append(f"{stop['id']} [{lang}] {title}")
            if coordinate is None or stop["id"] in placed:
                continue
            placed.add(stop["id"])
            if coordinate != AREA:
                d = distance(stop["coordinate"], coordinate)
                tolerance = args.tolerance
                if (lang, title) in settlements:
                    tolerance = max(tolerance, SETTLEMENT_TOLERANCE)
                if d > tolerance:
                    far.append(f"{file} {stop['id']}: {int(d)} m off; wiki [{lang}] {final} = {coordinate[0]:.5f}, {coordinate[1]:.5f}")
                    suggestions[stop["id"]] = [round(coordinate[0], 5), round(coordinate[1], 5)]
        if found and stop["id"] not in placed:
            no_coord.append(f"{stop['id']} " + ", ".join(found))

    print(f"Checked {len(stops)} stops.")
    print(f"\n== Missing articles ({len(missing)})")
    print("\n".join(missing) or "none")
    print(f"\n== Coordinates more than {int(args.tolerance)} m from Wikipedia ({len(far)})")
    print("\n".join(far) or "none")
    print(f"\n== Articles without coordinates ({len(no_coord)})")
    print("\n".join(no_coord) or "none")
    print(f"\n== Articles without a picture ({len(no_image)})")
    print("\n".join(no_image) or "none")

    extra = {}
    for item in filter(None, (part.strip() for part in args.stops.split(","))):
        stop_id, _, names = item.partition("=")
        extra[stop_id.strip()] = [name.strip() for name in names.split("|") if name.strip()]
    unknown = set(extra) - {stop["id"] for _, _, stop in stops}
    if unknown:
        print(f"\nUnknown stops: {', '.join(sorted(unknown))}")
    unplaced = [(file, stop) for file, _, stop in stops if stop["id"] not in placed or stop["id"] in extra]
    print(f"\n== Stops without a Wikipedia coordinate vs OpenStreetMap ({len(unplaced)})")
    osm = {}
    for file, stop in unplaced:
        try:
            # A stop asked for by hand may be far off, so it gets a wider search.
            text, found = osm_check(stop, extra.get(stop["id"], ()), 0.15 if stop["id"] in extra else 0.05)
        except Exception as error:  # noqa: BLE001
            print(f"OpenStreetMap unavailable: {error}")
            break
        around = ""
        if not found or stop["id"] in extra:
            try:
                around = " | ".join(f"{name} {d} m" for d, name in osm_nearby(stop["coordinate"])) or "no sights"
            except Exception as error:  # noqa: BLE001
                around = f"Overpass unavailable: {error}"
            around = f"\n    around the pin: {around}"
        if not found:
            print(f"{file} {stop['id']}: nothing called '{text}' nearby{around}")
            continue
        (where, name, kind), others = found[0], found[1:3]
        d = distance(stop["coordinate"], where)
        line = f"{file} {stop['id']}: {int(d)} m off; OSM {name} ({kind}) = {where[0]:.5f}, {where[1]:.5f}"
        if text != stop["title"].get("ru"):
            line += f" (searched '{text}')"
        if others:
            line += "\n    also: " + " | ".join(f"{n} ({k}) {int(distance(stop['coordinate'], w))} m = {w[0]:.5f}, {w[1]:.5f}"
                                         for w, n, k in others)
        print(line + around)
        if d > args.tolerance:
            osm[stop["id"]] = [round(where[0], 5), round(where[1], 5)]

    print("\nSUGGESTED_COORDINATES " + json.dumps(suggestions, ensure_ascii=False))
    print("OSM_COORDINATES " + json.dumps(osm, ensure_ascii=False))


if __name__ == "__main__":
    main()
