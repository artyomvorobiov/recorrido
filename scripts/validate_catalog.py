#!/usr/bin/env python3
"""Checks the curated catalog (Shared/Catalog/city-*.json) against Wikipedia.

For every stop with a `wiki` title it verifies that the article exists and
compares the stop's coordinate with the article's one. Big differences are
printed together with the Wikipedia coordinate, so they are easy to fix.
Stops that Wikipedia can't place (no article, or one without coordinates)
are looked up on OpenStreetMap near where the catalog puts them instead.

Usage: python3 scripts/validate_catalog.py [--tolerance 250]
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


TRANSPORT = {"highway", "railway", "public_transport"}


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
    return sorted(found, key=lambda place: (place[2].split("/")[0] in TRANSPORT, distance(near, place[0])))


def osm_check(stop):
    """(searched text, places) for the stop's title, falling back to its article's title."""
    texts = []
    for text in (stop["title"].get("ru"), (stop.get("wiki") or {}).get("ru", "").split(" (")[0]):
        text = (text or "").replace("«", "").replace("»", "")
        if text and text not in texts:
            texts.append(text)
    for text in texts:
        found = osm_search(text, stop["coordinate"])
        if found:
            return text, found
    return texts[0] if texts else "", []


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
        for lang, title in wiki.items():
            exists, coordinate, final, has_image = info[lang].get(title, (False, None, title, False))
            if not exists:
                hint = suggest_titles(lang, title, stop["coordinate"])
                missing.append(f"{file} {stop['id']}: [{lang}] '{title}' not found\n    try: {hint}")
                continue
            if lang == "ru" or "ru" not in wiki:
                if not has_image:
                    no_image.append(f"{stop['id']} [{lang}] {title}")
                if coordinate is None:
                    no_coord.append(f"{stop['id']} [{lang}] {title}")
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

    print(f"Checked {len(stops)} stops.")
    print(f"\n== Missing articles ({len(missing)})")
    print("\n".join(missing) or "none")
    print(f"\n== Coordinates more than {int(args.tolerance)} m from Wikipedia ({len(far)})")
    print("\n".join(far) or "none")
    print(f"\n== Articles without coordinates ({len(no_coord)})")
    print("\n".join(no_coord) or "none")
    print(f"\n== Articles without a picture ({len(no_image)})")
    print("\n".join(no_image) or "none")

    unplaced = [(file, stop) for file, _, stop in stops if stop["id"] not in placed]
    print(f"\n== Stops without a Wikipedia coordinate vs OpenStreetMap ({len(unplaced)})")
    osm = {}
    for file, stop in unplaced:
        try:
            text, found = osm_check(stop)
        except Exception as error:  # noqa: BLE001
            print(f"OpenStreetMap unavailable: {error}")
            break
        if not found:
            print(f"{file} {stop['id']}: nothing called '{text}' nearby")
            continue
        (where, name, kind), others = found[0], found[1:3]
        d = distance(stop["coordinate"], where)
        line = f"{file} {stop['id']}: {int(d)} m off; OSM {name} ({kind}) = {where[0]:.5f}, {where[1]:.5f}"
        if others:
            line += "\n    also: " + " | ".join(f"{n} ({k}) {int(distance(stop['coordinate'], w))} m" for w, n, k in others)
        print(line)
        if d > args.tolerance:
            osm[stop["id"]] = [round(where[0], 5), round(where[1], 5)]

    print("\nSUGGESTED_COORDINATES " + json.dumps(suggestions, ensure_ascii=False))
    print("OSM_COORDINATES " + json.dumps(osm, ensure_ascii=False))


if __name__ == "__main__":
    main()
