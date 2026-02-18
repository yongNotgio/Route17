import json
import textwrap
import uuid
from pathlib import Path


def set_code_cell(nb: dict, index: int, source: str) -> None:
    src = textwrap.dedent(source).strip("\n")
    nb["cells"][index]["source"] = [line + "\n" for line in src.splitlines()]


def ensure_cell_ids(nb: dict) -> None:
    for cell in nb.get("cells", []):
        if "id" not in cell:
            cell["id"] = uuid.uuid4().hex[:8]


root = Path(__file__).resolve().parent


nb1_path = root / "01_scrape_route_index.ipynb"
nb1 = json.loads(nb1_path.read_text(encoding="utf-8"))
ensure_cell_ids(nb1)

set_code_cell(
    nb1,
    1,
    """
    import json
    import re
    import time
    from datetime import datetime, timezone
    from pathlib import Path
    from urllib.parse import parse_qs, urljoin, urlparse

    import pandas as pd
    import requests
    from bs4 import BeautifulSoup, Tag

    BASE_URL = "https://shemaegomez.com/iloilo-city-jeepney-routes/"
    KML_URL_TEMPLATE = "https://www.google.com/maps/d/kml?mid={mid}&forcekml=1"
    OUTPUT_DIR = Path("output")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    HEADERS = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    }
    """,
)

set_code_cell(
    nb1,
    3,
    r"""
    ROUTE_HEADER_PATTERN = re.compile(r"^ROUTE\s*#?\s*(\d+)\b", flags=re.IGNORECASE)

    def normalize_text(text: str) -> str:
        if not text:
            return ""
        return " ".join(text.replace("\xa0", " ").split())

    def parse_route_number(text: str):
        match = re.search(r"\bROUTE\s*#?\s*(\d+)\b", text or "", flags=re.IGNORECASE)
        return int(match.group(1)) if match else None

    def split_stops(description: str):
        if not description:
            return []
        cleaned = description.replace(";", ",")
        stops = [normalize_text(part).strip(" .") for part in cleaned.split(",")]
        return [stop for stop in stops if stop]

    def extract_mid_from_url(url: str):
        if not url:
            return None
        parsed = urlparse(url)
        query = parse_qs(parsed.query)
        mids = query.get("mid")
        return mids[0] if mids else None

    def parse_kml_polylines(kml_text: str):
        kml_soup = BeautifulSoup(kml_text, "xml")
        polylines = []

        for idx, placemark in enumerate(kml_soup.find_all("Placemark"), start=1):
            line = placemark.find("LineString")
            if not line:
                continue

            coordinates_tag = line.find("coordinates")
            if not coordinates_tag:
                continue

            coordinate_tokens = normalize_text(coordinates_tag.get_text(" ", strip=True)).split()
            coordinates_lng_lat = []
            coordinates_lat_lng = []

            for token in coordinate_tokens:
                parts = token.split(",")
                if len(parts) < 2:
                    continue

                try:
                    lng = float(parts[0])
                    lat = float(parts[1])
                except ValueError:
                    continue

                coordinates_lng_lat.append([lng, lat])
                coordinates_lat_lng.append([lat, lng])

            if len(coordinates_lng_lat) < 2:
                continue

            name_tag = placemark.find("name")
            polyline_name = normalize_text(name_tag.get_text(" ", strip=True)) if name_tag else f"segment_{idx}"

            polylines.append(
                {
                    "name": polyline_name,
                    "point_count": len(coordinates_lng_lat),
                    "coordinates_lng_lat": coordinates_lng_lat,
                    "coordinates_lat_lng": coordinates_lat_lng,
                }
            )

        return polylines

    def fetch_map_geometry(map_mid: str, session: requests.Session, cache: dict):
        if not map_mid:
            return {
                "map_mid": None,
                "map_kml_url": None,
                "map_polylines": [],
                "map_polyline_count": 0,
                "map_point_count": 0,
                "map_scrape_error": None,
            }

        if map_mid in cache:
            return cache[map_mid]

        kml_url = KML_URL_TEMPLATE.format(mid=map_mid)
        try:
            kml_response = session.get(kml_url, headers=HEADERS, timeout=45)
            kml_response.raise_for_status()
            if not kml_response.encoding:
                kml_response.encoding = "utf-8"

            map_polylines = parse_kml_polylines(kml_response.text)
            result = {
                "map_mid": map_mid,
                "map_kml_url": kml_url,
                "map_polylines": map_polylines,
                "map_polyline_count": len(map_polylines),
                "map_point_count": sum(polyline["point_count"] for polyline in map_polylines),
                "map_scrape_error": None,
            }
        except Exception as exc:
            result = {
                "map_mid": map_mid,
                "map_kml_url": kml_url,
                "map_polylines": [],
                "map_polyline_count": 0,
                "map_point_count": 0,
                "map_scrape_error": str(exc),
            }

        cache[map_mid] = result
        time.sleep(0.35)
        return result
    """,
)

set_code_cell(
    nb1,
    5,
    """
    routes = []
    table_guide_lookup = {
        row["route_number"]: row["full_guide_url"]
        for row in table_rows
        if row.get("route_number") is not None and row.get("full_guide_url")
    }

    session = requests.Session()
    map_cache = {}

    for h2 in article.find_all("h2", class_="wp-block-heading"):
        route_title = normalize_text(h2.get_text(" ", strip=True))
        if not ROUTE_HEADER_PATTERN.match(route_title):
            continue

        route_data = {
            "route_number": parse_route_number(route_title),
            "route_title": route_title,
            "section_id": h2.get("id"),
            "source_url": BASE_URL,
            "stop_description": None,
            "stops": [],
            "full_guide_url": None,
            "map_embed_url": None,
            "map_mid": None,
            "map_kml_url": None,
            "map_polylines": [],
            "map_polyline_count": 0,
            "map_point_count": 0,
            "map_scrape_error": None,
            "faq_url": None,
        }

        node = h2.next_sibling
        while node:
            if isinstance(node, Tag):
                if node.name == "h2":
                    next_title = normalize_text(node.get_text(" ", strip=True))
                    if ROUTE_HEADER_PATTERN.match(next_title):
                        break

                if not route_data["full_guide_url"] and node.name in {"p", "h3", "h4"}:
                    node_text = normalize_text(node.get_text(" ", strip=True)).lower()
                    if "full guide" in node_text:
                        anchor = node.find("a", href=True)
                        if anchor:
                            route_data["full_guide_url"] = urljoin(BASE_URL, anchor["href"])

                if node.name == "p":
                    paragraph_text = normalize_text(node.get_text(" ", strip=True))
                    lowered = paragraph_text.lower()

                    if paragraph_text and not lowered.startswith("full guide") and not lowered.startswith("read also") and not route_data["stop_description"]:
                        route_data["stop_description"] = paragraph_text

                iframe = node.find("iframe", src=True)
                if iframe and not route_data["map_embed_url"]:
                    route_data["map_embed_url"] = urljoin(BASE_URL, iframe["src"])

                if node.name in {"h4", "p"}:
                    node_text = normalize_text(node.get_text(" ", strip=True)).lower()
                    if "faq" in node_text and not route_data["faq_url"]:
                        faq_anchor = node.find("a", href=True)
                        if faq_anchor:
                            route_data["faq_url"] = urljoin(BASE_URL, faq_anchor["href"])

            node = node.next_sibling

        if not route_data["full_guide_url"] and route_data["route_number"] in table_guide_lookup:
            route_data["full_guide_url"] = table_guide_lookup[route_data["route_number"]]

        if route_data["map_embed_url"]:
            map_mid = extract_mid_from_url(route_data["map_embed_url"])
            route_data.update(fetch_map_geometry(map_mid, session=session, cache=map_cache))

        route_data["stops"] = split_stops(route_data["stop_description"])
        routes.append(route_data)

    session.close()

    routes.sort(key=lambda row: (row["route_number"] is None, row["route_number"] or 9999))
    print(f"Route sections scraped: {len(routes)}")
    print(f"Routes with extracted polylines: {sum(1 for r in routes if r['map_polyline_count'] > 0)}")
    """,
)

set_code_cell(
    nb1,
    6,
    """
    output_payload = {
        "source_url": BASE_URL,
        "scraped_at_utc": datetime.now(timezone.utc).isoformat(),
        "route_count": len(routes),
        "routes_with_geometry": sum(1 for route in routes if route.get("map_polyline_count", 0) > 0),
        "total_polyline_segments": sum(route.get("map_polyline_count", 0) for route in routes),
        "total_polyline_points": sum(route.get("map_point_count", 0) for route in routes),
        "routes": routes,
        "compilation_table_rows": table_rows,
    }

    json_path = OUTPUT_DIR / "iloilo_routes_index.json"
    json_path.write_text(json.dumps(output_payload, indent=2, ensure_ascii=False), encoding="utf-8")

    csv_rows = []
    for route in routes:
        csv_rows.append(
            {
                "route_number": route["route_number"],
                "route_title": route["route_title"],
                "section_id": route["section_id"],
                "full_guide_url": route["full_guide_url"],
                "map_embed_url": route["map_embed_url"],
                "map_mid": route["map_mid"],
                "map_kml_url": route["map_kml_url"],
                "map_polyline_count": route["map_polyline_count"],
                "map_point_count": route["map_point_count"],
                "map_scrape_error": route["map_scrape_error"],
                "faq_url": route["faq_url"],
                "stop_description": route["stop_description"],
                "stops_pipe_delimited": " | ".join(route["stops"]),
                "stop_count": len(route["stops"]),
            }
        )

    pd.DataFrame(csv_rows).to_csv(OUTPUT_DIR / "iloilo_routes_index.csv", index=False, encoding="utf-8")

    features = []
    for route in routes:
        for segment_index, polyline in enumerate(route.get("map_polylines", []), start=1):
            if len(polyline.get("coordinates_lng_lat", [])) < 2:
                continue
            features.append(
                {
                    "type": "Feature",
                    "properties": {
                        "route_number": route.get("route_number"),
                        "route_title": route.get("route_title"),
                        "map_mid": route.get("map_mid"),
                        "segment_index": segment_index,
                        "segment_name": polyline.get("name"),
                        "point_count": polyline.get("point_count"),
                    },
                    "geometry": {
                        "type": "LineString",
                        "coordinates": polyline.get("coordinates_lng_lat", []),
                    },
                }
            )

    geojson_payload = {"type": "FeatureCollection", "features": features}
    geojson_path = OUTPUT_DIR / "iloilo_route_polylines.geojson"
    geojson_path.write_text(json.dumps(geojson_payload, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"Saved: {json_path}")
    print("Saved: output/iloilo_routes_index.csv")
    print(f"Saved: {geojson_path}")
    """,
)

set_code_cell(
    nb1,
    7,
    """
    pd.DataFrame(
        [
            {
                "route_number": r["route_number"],
                "route_title": r["route_title"],
                "stop_count": len(r["stops"]),
                "has_map": bool(r["map_embed_url"]),
                "polyline_segments": r["map_polyline_count"],
                "polyline_points": r["map_point_count"],
                "has_full_guide": bool(r["full_guide_url"]),
            }
            for r in routes
        ]
    ).head(15)
    """,
)

nb1_path.write_text(json.dumps(nb1, indent=2, ensure_ascii=False), encoding="utf-8")


nb2_path = root / "02_scrape_full_guides.ipynb"
nb2 = json.loads(nb2_path.read_text(encoding="utf-8"))
ensure_cell_ids(nb2)

set_code_cell(
    nb2,
    1,
    """
    import json
    import re
    import time
    from datetime import datetime, timezone
    from pathlib import Path
    from urllib.parse import parse_qs, urljoin, urlparse

    import pandas as pd
    import requests
    from bs4 import BeautifulSoup

    OUTPUT_DIR = Path("output")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    INDEX_JSON = OUTPUT_DIR / "iloilo_routes_index.json"
    if not INDEX_JSON.exists():
        raise FileNotFoundError("Run 01_scrape_route_index.ipynb first.")

    KML_URL_TEMPLATE = "https://www.google.com/maps/d/kml?mid={mid}&forcekml=1"

    HEADERS = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    }
    """,
)

set_code_cell(
    nb2,
    2,
    """
    def normalize_text(text: str) -> str:
        if not text:
            return ""
        return " ".join(text.replace("\\xa0", " ").split())

    def unique_in_order(items):
        seen = set()
        out = []
        for item in items:
            if item and item not in seen:
                seen.add(item)
                out.append(item)
        return out

    def extract_article_dates(soup: BeautifulSoup):
        date_published = None
        date_modified = None

        for script in soup.find_all("script", attrs={"type": "application/ld+json"}):
            raw = script.string or script.get_text(strip=True)
            if not raw:
                continue

            try:
                payload = json.loads(raw)
            except Exception:
                continue

            candidates = []
            if isinstance(payload, dict):
                if isinstance(payload.get("@graph"), list):
                    candidates.extend(payload["@graph"])
                candidates.append(payload)
            elif isinstance(payload, list):
                candidates.extend(payload)

            for candidate in candidates:
                if not isinstance(candidate, dict):
                    continue

                candidate_type = candidate.get("@type")
                if isinstance(candidate_type, list):
                    type_match = any(t in {"Article", "BlogPosting", "NewsArticle"} for t in candidate_type)
                else:
                    type_match = candidate_type in {"Article", "BlogPosting", "NewsArticle"}

                if type_match:
                    date_published = date_published or candidate.get("datePublished")
                    date_modified = date_modified or candidate.get("dateModified")

            if date_published and date_modified:
                break

        return date_published, date_modified

    def extract_mid_from_url(url: str):
        if not url:
            return None
        parsed = urlparse(url)
        query = parse_qs(parsed.query)
        mids = query.get("mid")
        return mids[0] if mids else None

    def parse_kml_polylines(kml_text: str):
        kml_soup = BeautifulSoup(kml_text, "xml")
        polylines = []

        for idx, placemark in enumerate(kml_soup.find_all("Placemark"), start=1):
            line = placemark.find("LineString")
            if not line:
                continue

            coordinates_tag = line.find("coordinates")
            if not coordinates_tag:
                continue

            coordinate_tokens = normalize_text(coordinates_tag.get_text(" ", strip=True)).split()
            coordinates_lng_lat = []
            coordinates_lat_lng = []

            for token in coordinate_tokens:
                parts = token.split(",")
                if len(parts) < 2:
                    continue

                try:
                    lng = float(parts[0])
                    lat = float(parts[1])
                except ValueError:
                    continue

                coordinates_lng_lat.append([lng, lat])
                coordinates_lat_lng.append([lat, lng])

            if len(coordinates_lng_lat) < 2:
                continue

            name_tag = placemark.find("name")
            polyline_name = normalize_text(name_tag.get_text(" ", strip=True)) if name_tag else f"segment_{idx}"

            polylines.append(
                {
                    "name": polyline_name,
                    "point_count": len(coordinates_lng_lat),
                    "coordinates_lng_lat": coordinates_lng_lat,
                    "coordinates_lat_lng": coordinates_lat_lng,
                }
            )

        return polylines

    def fetch_map_geometry(map_mid: str, session: requests.Session, cache: dict):
        if not map_mid:
            return {
                "map_mid": None,
                "map_kml_url": None,
                "map_polylines": [],
                "map_polyline_count": 0,
                "map_point_count": 0,
                "map_scrape_error": None,
            }

        if map_mid in cache:
            return cache[map_mid]

        kml_url = KML_URL_TEMPLATE.format(mid=map_mid)
        try:
            response = session.get(kml_url, headers=HEADERS, timeout=45)
            response.raise_for_status()
            if not response.encoding:
                response.encoding = "utf-8"

            map_polylines = parse_kml_polylines(response.text)
            result = {
                "map_mid": map_mid,
                "map_kml_url": kml_url,
                "map_polylines": map_polylines,
                "map_polyline_count": len(map_polylines),
                "map_point_count": sum(polyline["point_count"] for polyline in map_polylines),
                "map_scrape_error": None,
            }
        except Exception as exc:
            result = {
                "map_mid": map_mid,
                "map_kml_url": kml_url,
                "map_polylines": [],
                "map_polyline_count": 0,
                "map_point_count": 0,
                "map_scrape_error": str(exc),
            }

        cache[map_mid] = result
        time.sleep(0.35)
        return result

    def scrape_full_guide(route_row: dict, session: requests.Session, map_cache: dict):
        url = route_row.get("full_guide_url")
        if not url:
            return None

        response = session.get(url, headers=HEADERS, timeout=30)
        response.raise_for_status()

        if not response.encoding or response.encoding.lower() == "iso-8859-1":
            response.encoding = response.apparent_encoding or "utf-8"

        soup = BeautifulSoup(response.text, "lxml")
        article = soup.select_one("article .entry-content") or soup.select_one(".entry-content") or soup

        title_tag = soup.find("h1", class_=re.compile("entry-title")) or soup.find("h1")
        article_title = normalize_text(title_tag.get_text(" ", strip=True)) if title_tag else ""

        canonical_tag = soup.find("link", rel="canonical")
        canonical_url = canonical_tag.get("href") if canonical_tag and canonical_tag.get("href") else url

        paragraphs = []
        for p in article.select("p"):
            text = normalize_text(p.get_text(" ", strip=True))
            if not text:
                continue
            if text.lower().startswith("read also"):
                continue
            paragraphs.append(text)

        headings = [
            normalize_text(h.get_text(" ", strip=True))
            for h in article.select("h2, h3, h4")
            if normalize_text(h.get_text(" ", strip=True))
        ]

        map_embed_urls = unique_in_order([urljoin(url, iframe.get("src")) for iframe in article.select("iframe[src]")])
        map_geometry = []
        for embed_url in map_embed_urls:
            map_mid = extract_mid_from_url(embed_url)
            geometry = fetch_map_geometry(map_mid, session=session, cache=map_cache)
            map_geometry.append({"map_embed_url": embed_url, **geometry})

        date_published, date_modified = extract_article_dates(soup)

        return {
            "route_number": route_row.get("route_number"),
            "route_title": route_row.get("route_title"),
            "full_guide_url": url,
            "canonical_url": canonical_url,
            "article_title": article_title,
            "date_published": date_published,
            "date_modified": date_modified,
            "first_paragraph": paragraphs[0] if paragraphs else None,
            "paragraphs": paragraphs,
            "headings": headings,
            "map_embed_urls": map_embed_urls,
            "map_geometry": map_geometry,
            "guide_polyline_count": sum(item["map_polyline_count"] for item in map_geometry),
            "guide_point_count": sum(item["map_point_count"] for item in map_geometry),
            "scraped_at_utc": datetime.now(timezone.utc).isoformat(),
        }
    """,
)

set_code_cell(
    nb2,
    4,
    """
    full_guides = []
    errors = []

    session = requests.Session()
    map_cache = {}

    for route in full_guide_candidates:
        try:
            record = scrape_full_guide(route, session=session, map_cache=map_cache)
            if record:
                full_guides.append(record)
            time.sleep(0.6)
        except Exception as exc:
            errors.append(
                {
                    "route_number": route.get("route_number"),
                    "route_title": route.get("route_title"),
                    "full_guide_url": route.get("full_guide_url"),
                    "error": str(exc),
                }
            )

    session.close()

    print(f"Guides scraped: {len(full_guides)}")
    print(f"Errors: {len(errors)}")
    print(f"Guides with geometry: {sum(1 for g in full_guides if g['guide_polyline_count'] > 0)}")
    """,
)

set_code_cell(
    nb2,
    5,
    """
    full_guides_path = OUTPUT_DIR / "iloilo_full_guides.json"
    payload = {
        "source": "shemaegomez full guide pages",
        "scraped_at_utc": datetime.now(timezone.utc).isoformat(),
        "guide_count": len(full_guides),
        "guides_with_geometry": sum(1 for guide in full_guides if guide.get("guide_polyline_count", 0) > 0),
        "total_polyline_segments": sum(guide.get("guide_polyline_count", 0) for guide in full_guides),
        "total_polyline_points": sum(guide.get("guide_point_count", 0) for guide in full_guides),
        "error_count": len(errors),
        "guides": full_guides,
        "errors": errors,
    }

    full_guides_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")

    summary_rows = []
    for guide in full_guides:
        summary_rows.append(
            {
                "route_number": guide.get("route_number"),
                "route_title": guide.get("route_title"),
                "full_guide_url": guide.get("full_guide_url"),
                "article_title": guide.get("article_title"),
                "date_published": guide.get("date_published"),
                "date_modified": guide.get("date_modified"),
                "paragraph_count": len(guide.get("paragraphs") or []),
                "heading_count": len(guide.get("headings") or []),
                "map_embed_count": len(guide.get("map_embed_urls") or []),
                "guide_polyline_count": guide.get("guide_polyline_count"),
                "guide_point_count": guide.get("guide_point_count"),
            }
        )

    pd.DataFrame(summary_rows).to_csv(
        OUTPUT_DIR / "iloilo_full_guides_summary.csv",
        index=False,
        encoding="utf-8",
    )

    features = []
    for guide in full_guides:
        for map_item in guide.get("map_geometry", []):
            for segment_index, polyline in enumerate(map_item.get("map_polylines", []), start=1):
                if len(polyline.get("coordinates_lng_lat", [])) < 2:
                    continue
                features.append(
                    {
                        "type": "Feature",
                        "properties": {
                            "route_number": guide.get("route_number"),
                            "route_title": guide.get("route_title"),
                            "full_guide_url": guide.get("full_guide_url"),
                            "map_mid": map_item.get("map_mid"),
                            "segment_index": segment_index,
                            "segment_name": polyline.get("name"),
                            "point_count": polyline.get("point_count"),
                        },
                        "geometry": {
                            "type": "LineString",
                            "coordinates": polyline.get("coordinates_lng_lat", []),
                        },
                    }
                )

    geojson_path = OUTPUT_DIR / "iloilo_full_guides_polylines.geojson"
    geojson_payload = {"type": "FeatureCollection", "features": features}
    geojson_path.write_text(json.dumps(geojson_payload, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"Saved: {full_guides_path}")
    print("Saved: output/iloilo_full_guides_summary.csv")
    print(f"Saved: {geojson_path}")
    """,
)

set_code_cell(
    nb2,
    6,
    """
    pd.DataFrame(
        [
            {
                "route_number": g["route_number"],
                "article_title": g["article_title"],
                "paragraph_count": len(g["paragraphs"]),
                "map_embed_count": len(g["map_embed_urls"]),
                "guide_polyline_count": g["guide_polyline_count"],
                "guide_point_count": g["guide_point_count"],
            }
            for g in full_guides
        ]
    ).sort_values("route_number").head(15)
    """,
)

nb2_path.write_text(json.dumps(nb2, indent=2, ensure_ascii=False), encoding="utf-8")

print("Updated 01_scrape_route_index.ipynb with map geometry extraction.")
print("Updated 02_scrape_full_guides.ipynb with map geometry extraction.")
