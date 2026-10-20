#!/usr/bin/env python3
"""Checks that the Wikipedia API still answers in the shape the app expects.

The route generator in the app relies on a few MediaWiki API features
(geosearch generator, pageviews, descriptions, page images, extracts).
This script runs the same kind of queries and prints a short report, so a
change on Wikipedia's side shows up in CI before users notice it.

Usage: python3 scripts/wiki_probe.py
"""
import json
import sys
import time
import urllib.parse
import urllib.request

UA = "RecorridoContentCheck/1.0 (https://github.com/artyomvorobiov/recorrido)"


def api(lang, params):
    params = dict(params)
    params.setdefault("format", "json")
    params.setdefault("formatversion", "2")
    url = f"https://{lang}.wikipedia.org/w/api.php?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def query_all(lang, params, max_rounds=30):
    """Runs a query following `continue` and merges pages by pageid."""
    pages = {}
    rounds = 0
    cont = {}
    while True:
        rounds += 1
        data = api(lang, {**params, **cont})
        if "error" in data or "warnings" in data:
            print("  API error/warnings:", json.dumps({k: data.get(k) for k in ("error", "warnings")}, ensure_ascii=False)[:600])
        for page in data.get("query", {}).get("pages", []):
            merged = pages.setdefault(page["pageid"], {})
            for key, value in page.items():
                if key == "pageviews" and key in merged:
                    merged[key].update(value or {})
                else:
                    merged[key] = value
        if "continue" not in data or rounds >= max_rounds:
            return pages, rounds, data.get("continue")
        cont = data["continue"]


def probe_generator(lang, name, lat, lon, radius, limit, props, coprop=True):
    started = time.time()
    params = {
        "action": "query",
        "generator": "geosearch",
        "ggscoord": f"{lat}|{lon}",
        "ggsradius": str(radius),
        "ggslimit": str(limit),
        "prop": props,
        "pvipdays": "30",
        "piprop": "thumbnail",
        "pithumbsize": "400",
        "pilimit": "50",
        "colimit": "max",
    }
    if coprop:
        params["coprop"] = "type"
    pages, rounds, leftover = query_all(lang, params)
    with_views = [p for p in pages.values() if p.get("pageviews")]
    with_desc = [p for p in pages.values() if p.get("description")]
    with_thumb = [p for p in pages.values() if p.get("thumbnail")]
    with_coord = [p for p in pages.values() if p.get("coordinates")]

    def total(p):
        views = sum(v for v in (p.get("pageviews") or {}).values() if v)
        return views or p.get("length", 0)

    top = sorted(pages.values(), key=total, reverse=True)[:40]
    print(f"\n=== {name} [{lang}] radius={radius} limit={limit} props={props}")
    print(f"pages={len(pages)} rounds={rounds} leftover_continue={leftover} "
          f"views={len(with_views)} desc={len(with_desc)} thumb={len(with_thumb)} coord={len(with_coord)} "
          f"time={time.time() - started:.1f}s")
    for p in top:
        print(f"  {total(p):>8}  {p['title']}  |  {p.get('description', '')}")
    sample = top[0] if top else None
    if sample:
        trimmed = dict(sample)
        if "pageviews" in trimmed:
            items = list(trimmed["pageviews"].items())[:3]
            trimmed["pageviews"] = dict(items)
        print("  sample page json:", json.dumps(trimmed, ensure_ascii=False)[:900])
    return pages


def probe_geosearch_types(lang, lat, lon):
    data = api(lang, {
        "action": "query", "list": "geosearch", "gscoord": f"{lat}|{lon}",
        "gsradius": "2000", "gslimit": "40", "gsprop": "type|name",
    })
    items = data.get("query", {}).get("geosearch", [])
    print(f"\n=== list=geosearch types [{lang}] count={len(items)}")
    print("  sample item json:", json.dumps(items[0], ensure_ascii=False) if items else None)
    types = {}
    for item in items:
        types[item.get("type")] = types.get(item.get("type"), 0) + 1
    print("  types:", types)


def probe_extracts(lang, pageids):
    data = api(lang, {
        "action": "query", "pageids": "|".join(str(i) for i in pageids[:20]),
        "prop": "extracts", "exintro": "1", "explaintext": "1", "exsentences": "4", "exlimit": "20",
    })
    pages = data.get("query", {}).get("pages", [])
    have = [p for p in pages if p.get("extract")]
    print(f"\n=== extracts [{lang}] asked={len(pageids[:20])} got={len(have)} continue={data.get('continue')}")
    for p in have[:3]:
        print(f"  {p['title']}: {p['extract'][:300]!r}")


def probe_titles(lang, titles):
    data = api(lang, {
        "action": "query", "titles": "|".join(titles), "redirects": "1",
        "prop": "pageimages|coordinates", "piprop": "thumbnail", "pithumbsize": "800",
    })
    q = data.get("query", {})
    print(f"\n=== titles [{lang}]")
    print("  normalized:", q.get("normalized"))
    print("  redirects:", q.get("redirects"))
    for p in q.get("pages", []):
        print("  page:", json.dumps(p, ensure_ascii=False)[:400])


def main():
    paris = probe_generator("en", "Paris", 48.8566, 2.3522, 3000, 300, "info|description|coordinates")
    probe_generator("en", "Paris ring (Eiffel side)", 48.8580, 2.2950, 1800, 120, "info|description|coordinates")
    moscow = probe_generator("ru", "Moscow", 55.7539, 37.6208, 3000, 300, "info|description|coordinates")
    moscow = probe_generator("ru", "Moscow (no coprop)", 55.7539, 37.6208, 3000, 300, "info|description|coordinates", coprop=False)
    probe_generator("ru", "Pereslavl (no coprop)", 56.7360, 38.8543, 10000, 300, "info|description|coordinates", coprop=False)
    probe_generator("ru", "Kolomna (no coprop)", 55.1025, 38.7531, 10000, 300, "info|description|coordinates", coprop=False)
    probe_generator("ru", "Suzdal", 56.4196, 40.4492, 10000, 200, "info|description|coordinates")
    probe_geosearch_types("en", 48.8566, 2.3522)
    probe_extracts("en", sorted(paris, key=lambda i: -paris[i].get("length", 0))[:20])
    probe_extracts("ru", sorted(moscow, key=lambda i: -moscow[i].get("length", 0))[:20])
    probe_titles("ru", ["Эрмитаж", "Исаакиевский собор", "Медный всадник", "Несуществующая статья 123"])
    probe_titles("en", ["Hermitage Museum", "Eiffel tower", "Saint Isaac's Cathedral"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
