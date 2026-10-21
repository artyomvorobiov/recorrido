#!/usr/bin/env python3
"""Checks the curated catalog (Shared/Catalog/city-*.json) against Wikipedia.

For every stop with a `wiki` title it verifies that the article exists and
compares the stop's coordinate with the article's one. Big differences are
printed together with the Wikipedia coordinate, so they are easy to fix.

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
AREA_TYPES = {"waterbody", "river", "isle", "forest", "glacier", "mountain", "city", "adm1st", "adm2nd", "adm3rd"}
AREA = "area"


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
            if coords and coords[0].get("type", "").split("(")[0] in AREA_TYPES:
                coordinate = AREA
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
                elif coordinate != AREA:
                    d = distance(stop["coordinate"], coordinate)
                    if d > args.tolerance:
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
    print("\nSUGGESTED_COORDINATES " + json.dumps(suggestions, ensure_ascii=False))


if __name__ == "__main__":
    main()
