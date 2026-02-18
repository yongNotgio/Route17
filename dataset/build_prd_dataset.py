import json
import math
import re
from pathlib import Path
from urllib.parse import urlparse, parse_qs

import pandas as pd
import requests
from bs4 import BeautifulSoup


ROOT = Path(__file__).resolve().parent
OUTPUT_DIR = ROOT / "output"

INDEX_JSON = OUTPUT_DIR / "iloilo_routes_index.json"
FULL_GUIDES_JSON = OUTPUT_DIR / "iloilo_full_guides.json"

PRD_JSON = OUTPUT_DIR / "prd_routes_dataset.json"
PRD_SUMMARY_CSV = OUTPUT_DIR / "prd_routes_summary.csv"
PRD_SQL = OUTPUT_DIR / "prd_route25_dump.sql"

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/122.0.0.0 Safari/537.36"
    )
}


def normalize_text(text: str) -> str:
    if not text:
        return ""
    return " ".join(text.replace("\xa0", " ").split())


def extract_route_name(route_title: str) -> str:
    if not route_title:
        return ""
    return normalize_text(re.sub(r"^ROUTE\s*#?\s*\d+\s*", "", route_title, flags=re.IGNORECASE))


def parse_fare_from_text(text: str):
    if not text:
        return None, None, None

    flat = normalize_text(text)

    range_pattern = re.compile(
        r"(?:₱|PHP|Php|php|P)?\s*(\d{1,3}(?:\.\d{1,2})?)\s*(?:-|to|–)\s*(?:₱|PHP|Php|php|P)?\s*(\d{1,3}(?:\.\d{1,2})?)"
    )
    single_pattern = re.compile(
        r"(?:minimum fare|fare|pamasahe)[^0-9]{0,20}(?:₱|PHP|Php|php|P)?\s*(\d{1,3}(?:\.\d{1,2})?)",
        flags=re.IGNORECASE,
    )

    m = range_pattern.search(flat)
    if m:
        low = float(m.group(1))
        high = float(m.group(2))
        return min(low, high), max(low, high), m.group(0)

    m = single_pattern.search(flat)
    if m:
        value = float(m.group(1))
        return value, value, m.group(0)

    return None, None, None


def parse_map_markers_from_kml(kml_text: str):
    soup = BeautifulSoup(kml_text, "xml")
    markers = []

    for placemark in soup.find_all("Placemark"):
        point = placemark.find("Point")
        if not point:
            continue

        coord_tag = point.find("coordinates")
        if not coord_tag:
            continue

        coords = normalize_text(coord_tag.get_text(" ", strip=True)).split()
        if not coords:
            continue

        raw = coords[0].split(",")
        if len(raw) < 2:
            continue

        try:
            lng = float(raw[0])
            lat = float(raw[1])
        except ValueError:
            continue

        name_tag = placemark.find("name")
        marker_name = normalize_text(name_tag.get_text(" ", strip=True)) if name_tag else None

        markers.append(
            {
                "marker_name": marker_name,
                "lat": lat,
                "lng": lng,
            }
        )

    return markers


def fetch_markers_for_mid(map_mid: str, session: requests.Session, cache: dict):
    if not map_mid:
        return None, [], None
    if map_mid in cache:
        return cache[map_mid]

    kml_url = f"https://www.google.com/maps/d/kml?mid={map_mid}&forcekml=1"
    try:
        resp = session.get(kml_url, headers=HEADERS, timeout=45)
        resp.raise_for_status()
        if not resp.encoding:
            resp.encoding = "utf-8"
        markers = parse_map_markers_from_kml(resp.text)
        result = (kml_url, markers, None)
    except Exception as exc:
        result = (kml_url, [], str(exc))

    cache[map_mid] = result
    return result


def map_mid_from_embed(url: str):
    if not url:
        return None
    parsed = urlparse(url)
    qs = parse_qs(parsed.query)
    mids = qs.get("mid")
    return mids[0] if mids else None


def sql_value(value):
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if math.isnan(value) or math.isinf(value):
            return "NULL"
        return repr(value)
    text = str(value).replace("'", "''")
    return f"'{text}'"


def insert_line(table, columns, values):
    cols = ", ".join(columns)
    vals = ", ".join(sql_value(v) for v in values)
    return f"INSERT INTO {table} ({cols}) VALUES ({vals});"


def build_sql_dump(payload: dict):
    lines = []
    lines.append("-- Route25 PRD-focused SQL dump (PostgreSQL / Supabase)")
    lines.append("BEGIN TRANSACTION;")
    lines.append("")
    lines.append("DROP TABLE IF EXISTS prd_route_stops;")
    lines.append("DROP TABLE IF EXISTS prd_routes;")
    lines.append("DROP TABLE IF EXISTS prd_meta;")
    lines.append("")
    lines.append(
        """
CREATE TABLE prd_meta (
    id INTEGER PRIMARY KEY,
    generated_at_utc TEXT,
    route_count INTEGER,
    routes_with_stop_coordinates INTEGER,
    routes_with_fare INTEGER
);
""".strip()
    )
    lines.append(
        """
CREATE TABLE prd_routes (
    route_id INTEGER PRIMARY KEY,
    route_number INTEGER NOT NULL UNIQUE,
    route_code TEXT NOT NULL,
    route_name TEXT NOT NULL,
    fare_min_php REAL,
    fare_max_php REAL,
    fare_text TEXT,
    stop_count INTEGER
);
""".strip()
    )
    lines.append(
        """
CREATE TABLE prd_route_stops (
    stop_id INTEGER PRIMARY KEY,
    route_id INTEGER NOT NULL,
    stop_order INTEGER NOT NULL,
    stop_name TEXT,
    lat REAL,
    lng REAL,
    FOREIGN KEY (route_id) REFERENCES prd_routes(route_id)
);
""".strip()
    )
    lines.append("")

    lines.append(
        insert_line(
            "prd_meta",
            [
                "id",
                "generated_at_utc",
                "route_count",
                "routes_with_stop_coordinates",
                "routes_with_fare",
            ],
            [
                1,
                payload.get("generated_at_utc"),
                payload.get("route_count"),
                payload.get("routes_with_stop_coordinates"),
                payload.get("routes_with_fare"),
            ],
        )
    )

    stop_id = 1

    for route_idx, route in enumerate(payload["routes"], start=1):
        lines.append(
            insert_line(
                "prd_routes",
                [
                    "route_id",
                    "route_number",
                    "route_code",
                    "route_name",
                    "fare_min_php",
                    "fare_max_php",
                    "fare_text",
                    "stop_count",
                ],
                [
                    route_idx,
                    route.get("route_number"),
                    route.get("route_code"),
                    route.get("route_name"),
                    route.get("fare_min_php"),
                    route.get("fare_max_php"),
                    route.get("fare_text"),
                    route.get("stop_count"),
                ],
            )
        )

        for stop in route.get("stops", []):
            lines.append(
                insert_line(
                    "prd_route_stops",
                    [
                        "stop_id",
                        "route_id",
                        "stop_order",
                        "stop_name",
                        "lat",
                        "lng",
                    ],
                    [
                        stop_id,
                        route_idx,
                        stop.get("stop_order"),
                        stop.get("stop_name"),
                        stop.get("lat"),
                        stop.get("lng"),
                    ],
                )
            )
            stop_id += 1

    lines.append("")
    lines.append("CREATE INDEX idx_prd_routes_route_number ON prd_routes(route_number);")
    lines.append("CREATE INDEX idx_prd_route_stops_route_id ON prd_route_stops(route_id);")
    lines.append("")
    lines.append("COMMIT;")

    PRD_SQL.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    if not INDEX_JSON.exists():
        raise FileNotFoundError(f"Missing {INDEX_JSON}")
    if not FULL_GUIDES_JSON.exists():
        raise FileNotFoundError(f"Missing {FULL_GUIDES_JSON}")

    index_payload = json.loads(INDEX_JSON.read_text(encoding="utf-8"))
    full_payload = json.loads(FULL_GUIDES_JSON.read_text(encoding="utf-8"))

    full_guides_by_route = {g.get("route_number"): g for g in full_payload.get("guides", [])}

    routes_out = []
    session = requests.Session()
    kml_cache = {}

    for route in sorted(index_payload.get("routes", []), key=lambda r: (r.get("route_number") is None, r.get("route_number") or 9999)):
        route_number = route.get("route_number")
        route_title = route.get("route_title")
        route_name = extract_route_name(route_title)
        route_code = f"ROUTE {route_number}" if route_number is not None else None

        guide = full_guides_by_route.get(route_number, {})
        fare_source_text = "\n".join((guide.get("paragraphs") or []) + (guide.get("headings") or []))
        fare_min, fare_max, fare_text = parse_fare_from_text(fare_source_text)

        map_mid = route.get("map_mid") or map_mid_from_embed(route.get("map_embed_url"))
        map_kml_url, markers, marker_error = fetch_markers_for_mid(map_mid, session=session, cache=kml_cache)

        stops = []
        if markers:
            for i, marker in enumerate(markers, start=1):
                stops.append(
                    {
                        "stop_order": i,
                        "stop_name": marker.get("marker_name"),
                        "lat": marker.get("lat"),
                        "lng": marker.get("lng"),
                        "source_type": "map_marker",
                        "has_coordinates": True,
                    }
                )
        else:
            for i, stop_name in enumerate(route.get("stops", []), start=1):
                stops.append(
                    {
                        "stop_order": i,
                        "stop_name": stop_name,
                        "lat": None,
                        "lng": None,
                        "source_type": "text_stop",
                        "has_coordinates": False,
                    }
                )

        routes_out.append(
            {
                "route_number": route_number,
                "route_code": route_code,
                "route_name": route_name,
                "route_title": route_title,
                "fare_min_php": fare_min,
                "fare_max_php": fare_max,
                "fare_text": fare_text,
                "fare_source_url": guide.get("full_guide_url"),
                "map_embed_url": route.get("map_embed_url"),
                "map_mid": map_mid,
                "map_kml_url": map_kml_url or route.get("map_kml_url"),
                "map_polyline_count": route.get("map_polyline_count", 0),
                "map_point_count": route.get("map_point_count", 0),
                "map_marker_count": len(markers),
                "map_marker_error": marker_error,
                "stop_count": len(stops),
                "stops": stops,
                "map_polylines": route.get("map_polylines", []),
            }
        )

    session.close()

    payload = {
        "generated_at_utc": pd.Timestamp.utcnow().isoformat(),
        "source_route_index": str(INDEX_JSON.name),
        "source_full_guides": str(FULL_GUIDES_JSON.name),
        "route_count": len(routes_out),
        "routes_with_map_geometry": sum(1 for r in routes_out if (r.get("map_polyline_count") or 0) > 0),
        "routes_with_stop_coordinates": sum(1 for r in routes_out if any(s.get("has_coordinates") for s in r.get("stops", []))),
        "routes_with_fare": sum(1 for r in routes_out if r.get("fare_min_php") is not None),
        "routes": routes_out,
    }

    PRD_JSON.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")

    summary_rows = []
    for r in routes_out:
        summary_rows.append(
            {
                "route_number": r.get("route_number"),
                "route_code": r.get("route_code"),
                "route_name": r.get("route_name"),
                "fare_min_php": r.get("fare_min_php"),
                "fare_max_php": r.get("fare_max_php"),
                "stop_count": r.get("stop_count"),
                "stops_with_coordinates": sum(1 for s in r.get("stops", []) if s.get("has_coordinates")),
                "map_polyline_count": r.get("map_polyline_count"),
                "map_point_count": r.get("map_point_count"),
                "map_marker_count": r.get("map_marker_count"),
            }
        )
    pd.DataFrame(summary_rows).to_csv(PRD_SUMMARY_CSV, index=False, encoding="utf-8")

    build_sql_dump(payload)

    print(f"Saved: {PRD_JSON}")
    print(f"Saved: {PRD_SUMMARY_CSV}")
    print(f"Saved: {PRD_SQL}")
    print(f"Routes: {payload['route_count']}")
    print(f"Routes with map geometry: {payload['routes_with_map_geometry']}")
    print(f"Routes with stop coordinates: {payload['routes_with_stop_coordinates']}")
    print(f"Routes with fare: {payload['routes_with_fare']}")


if __name__ == "__main__":
    main()

