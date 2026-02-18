import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parent
OUTPUT_DIR = ROOT / "output"
SQL_DUMP_PATH = OUTPUT_DIR / "route25_dataset_dump.sql"


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


def main():
    index_payload = json.loads((OUTPUT_DIR / "iloilo_routes_index.json").read_text(encoding="utf-8"))
    full_payload = json.loads((OUTPUT_DIR / "iloilo_full_guides.json").read_text(encoding="utf-8"))

    lines = []
    lines.append("-- Route25 dataset SQL dump (PostgreSQL / Supabase)")
    lines.append("BEGIN TRANSACTION;")
    lines.append("")
    lines.append("DROP TABLE IF EXISTS output_artifacts;")
    lines.append("DROP TABLE IF EXISTS full_guide_map_points;")
    lines.append("DROP TABLE IF EXISTS full_guide_map_polylines;")
    lines.append("DROP TABLE IF EXISTS full_guide_map_embeds;")
    lines.append("DROP TABLE IF EXISTS full_guide_headings;")
    lines.append("DROP TABLE IF EXISTS full_guide_paragraphs;")
    lines.append("DROP TABLE IF EXISTS full_guide_errors;")
    lines.append("DROP TABLE IF EXISTS full_guides;")
    lines.append("DROP TABLE IF EXISTS full_guides_meta;")
    lines.append("DROP TABLE IF EXISTS route_map_points;")
    lines.append("DROP TABLE IF EXISTS route_map_polylines;")
    lines.append("DROP TABLE IF EXISTS route_stops;")
    lines.append("DROP TABLE IF EXISTS routes;")
    lines.append("DROP TABLE IF EXISTS route_compilation_rows;")
    lines.append("DROP TABLE IF EXISTS route_index_meta;")
    lines.append("")
    lines.append(
        """
CREATE TABLE route_index_meta (
    id INTEGER PRIMARY KEY,
    source_url TEXT,
    scraped_at_utc TEXT,
    route_count INTEGER,
    routes_with_geometry INTEGER,
    total_polyline_segments INTEGER,
    total_polyline_points INTEGER
);
""".strip()
    )
    lines.append(
        """
CREATE TABLE route_compilation_rows (
    id INTEGER PRIMARY KEY,
    route_number INTEGER,
    route_title TEXT,
    route_link TEXT,
    full_guide_url TEXT,
    is_outside_iloilo_city INTEGER
);
""".strip()
    )
    lines.append(
        """
CREATE TABLE routes (
    route_id INTEGER PRIMARY KEY,
    route_number INTEGER NOT NULL UNIQUE,
    route_title TEXT NOT NULL,
    section_id TEXT,
    source_url TEXT,
    stop_description TEXT,
    full_guide_url TEXT,
    map_embed_url TEXT,
    map_mid TEXT,
    map_kml_url TEXT,
    map_polyline_count INTEGER,
    map_point_count INTEGER,
    map_scrape_error TEXT,
    faq_url TEXT
);
""".strip()
    )
    lines.append(
        """
CREATE TABLE route_stops (
    id INTEGER PRIMARY KEY,
    route_id INTEGER NOT NULL,
    stop_order INTEGER NOT NULL,
    stop_name TEXT NOT NULL,
    FOREIGN KEY (route_id) REFERENCES routes(route_id)
);
""".strip()
    )
    lines.append(
        """
CREATE TABLE route_map_polylines (
    id INTEGER PRIMARY KEY,
    route_id INTEGER NOT NULL,
    segment_index INTEGER NOT NULL,
    segment_name TEXT,
    point_count INTEGER,
    FOREIGN KEY (route_id) REFERENCES routes(route_id)
);
""".strip()
    )
    lines.append(
        """
CREATE TABLE route_map_points (
    id INTEGER PRIMARY KEY,
    polyline_id INTEGER NOT NULL,
    point_order INTEGER NOT NULL,
    lat REAL NOT NULL,
    lng REAL NOT NULL,
    FOREIGN KEY (polyline_id) REFERENCES route_map_polylines(id)
);
""".strip()
    )
    lines.append(
        """
CREATE TABLE full_guides_meta (
    id INTEGER PRIMARY KEY,
    source TEXT,
    scraped_at_utc TEXT,
    guide_count INTEGER,
    guides_with_geometry INTEGER,
    total_polyline_segments INTEGER,
    total_polyline_points INTEGER,
    error_count INTEGER
);
""".strip()
    )
    lines.append(
        """
CREATE TABLE full_guides (
    guide_id INTEGER PRIMARY KEY,
    route_number INTEGER,
    route_title TEXT,
    full_guide_url TEXT UNIQUE,
    canonical_url TEXT,
    article_title TEXT,
    date_published TEXT,
    date_modified TEXT,
    first_paragraph TEXT,
    guide_polyline_count INTEGER,
    guide_point_count INTEGER,
    scraped_at_utc TEXT
);
""".strip()
    )
    lines.append(
        """
CREATE TABLE full_guide_paragraphs (
    id INTEGER PRIMARY KEY,
    guide_id INTEGER NOT NULL,
    paragraph_order INTEGER NOT NULL,
    paragraph_text TEXT NOT NULL,
    FOREIGN KEY (guide_id) REFERENCES full_guides(guide_id)
);
""".strip()
    )
    lines.append(
        """
CREATE TABLE full_guide_headings (
    id INTEGER PRIMARY KEY,
    guide_id INTEGER NOT NULL,
    heading_order INTEGER NOT NULL,
    heading_text TEXT NOT NULL,
    FOREIGN KEY (guide_id) REFERENCES full_guides(guide_id)
);
""".strip()
    )
    lines.append(
        """
CREATE TABLE full_guide_map_embeds (
    id INTEGER PRIMARY KEY,
    guide_id INTEGER NOT NULL,
    embed_order INTEGER NOT NULL,
    map_embed_url TEXT,
    map_mid TEXT,
    map_kml_url TEXT,
    map_polyline_count INTEGER,
    map_point_count INTEGER,
    map_scrape_error TEXT,
    FOREIGN KEY (guide_id) REFERENCES full_guides(guide_id)
);
""".strip()
    )
    lines.append(
        """
CREATE TABLE full_guide_map_polylines (
    id INTEGER PRIMARY KEY,
    embed_id INTEGER NOT NULL,
    segment_index INTEGER NOT NULL,
    segment_name TEXT,
    point_count INTEGER,
    FOREIGN KEY (embed_id) REFERENCES full_guide_map_embeds(id)
);
""".strip()
    )
    lines.append(
        """
CREATE TABLE full_guide_map_points (
    id INTEGER PRIMARY KEY,
    polyline_id INTEGER NOT NULL,
    point_order INTEGER NOT NULL,
    lat REAL NOT NULL,
    lng REAL NOT NULL,
    FOREIGN KEY (polyline_id) REFERENCES full_guide_map_polylines(id)
);
""".strip()
    )
    lines.append(
        """
CREATE TABLE full_guide_errors (
    id INTEGER PRIMARY KEY,
    route_number INTEGER,
    route_title TEXT,
    full_guide_url TEXT,
    error_text TEXT
);
""".strip()
    )
    lines.append(
        """
CREATE TABLE output_artifacts (
    filename TEXT PRIMARY KEY,
    content_type TEXT,
    content_text TEXT
);
""".strip()
    )
    lines.append("")

    lines.append(
        insert_line(
            "route_index_meta",
            [
                "id",
                "source_url",
                "scraped_at_utc",
                "route_count",
                "routes_with_geometry",
                "total_polyline_segments",
                "total_polyline_points",
            ],
            [
                1,
                index_payload.get("source_url"),
                index_payload.get("scraped_at_utc"),
                index_payload.get("route_count"),
                index_payload.get("routes_with_geometry"),
                index_payload.get("total_polyline_segments"),
                index_payload.get("total_polyline_points"),
            ],
        )
    )

    for i, row in enumerate(index_payload.get("compilation_table_rows", []), start=1):
        lines.append(
            insert_line(
                "route_compilation_rows",
                ["id", "route_number", "route_title", "route_link", "full_guide_url", "is_outside_iloilo_city"],
                [
                    i,
                    row.get("route_number"),
                    row.get("route_title"),
                    row.get("route_link"),
                    row.get("full_guide_url"),
                    row.get("is_outside_iloilo_city"),
                ],
            )
        )

    route_rows = sorted(index_payload.get("routes", []), key=lambda r: (r.get("route_number") is None, r.get("route_number") or 9999))
    route_id_map = {}
    route_stop_id = 1
    route_polyline_id = 1
    route_point_id = 1

    for route_id, route in enumerate(route_rows, start=1):
        route_number = route.get("route_number")
        route_id_map[route_number] = route_id

        lines.append(
            insert_line(
                "routes",
                [
                    "route_id",
                    "route_number",
                    "route_title",
                    "section_id",
                    "source_url",
                    "stop_description",
                    "full_guide_url",
                    "map_embed_url",
                    "map_mid",
                    "map_kml_url",
                    "map_polyline_count",
                    "map_point_count",
                    "map_scrape_error",
                    "faq_url",
                ],
                [
                    route_id,
                    route_number,
                    route.get("route_title"),
                    route.get("section_id"),
                    route.get("source_url"),
                    route.get("stop_description"),
                    route.get("full_guide_url"),
                    route.get("map_embed_url"),
                    route.get("map_mid"),
                    route.get("map_kml_url"),
                    route.get("map_polyline_count"),
                    route.get("map_point_count"),
                    route.get("map_scrape_error"),
                    route.get("faq_url"),
                ],
            )
        )

        for stop_order, stop_name in enumerate(route.get("stops", []), start=1):
            lines.append(
                insert_line(
                    "route_stops",
                    ["id", "route_id", "stop_order", "stop_name"],
                    [route_stop_id, route_id, stop_order, stop_name],
                )
            )
            route_stop_id += 1

        for segment_index, polyline in enumerate(route.get("map_polylines", []), start=1):
            current_polyline_id = route_polyline_id
            lines.append(
                insert_line(
                    "route_map_polylines",
                    ["id", "route_id", "segment_index", "segment_name", "point_count"],
                    [
                        current_polyline_id,
                        route_id,
                        segment_index,
                        polyline.get("name"),
                        polyline.get("point_count"),
                    ],
                )
            )
            route_polyline_id += 1

            for point_order, lat_lng in enumerate(polyline.get("coordinates_lat_lng", []), start=1):
                if len(lat_lng) < 2:
                    continue
                lat, lng = lat_lng[0], lat_lng[1]
                lines.append(
                    insert_line(
                        "route_map_points",
                        ["id", "polyline_id", "point_order", "lat", "lng"],
                        [route_point_id, current_polyline_id, point_order, lat, lng],
                    )
                )
                route_point_id += 1

    lines.append(
        insert_line(
            "full_guides_meta",
            [
                "id",
                "source",
                "scraped_at_utc",
                "guide_count",
                "guides_with_geometry",
                "total_polyline_segments",
                "total_polyline_points",
                "error_count",
            ],
            [
                1,
                full_payload.get("source"),
                full_payload.get("scraped_at_utc"),
                full_payload.get("guide_count"),
                full_payload.get("guides_with_geometry"),
                full_payload.get("total_polyline_segments"),
                full_payload.get("total_polyline_points"),
                full_payload.get("error_count"),
            ],
        )
    )

    guide_rows = sorted(full_payload.get("guides", []), key=lambda g: (g.get("route_number") is None, g.get("route_number") or 9999))
    guide_id_map = {}
    guide_paragraph_id = 1
    guide_heading_id = 1
    guide_embed_id = 1
    guide_polyline_id = 1
    guide_point_id = 1

    for guide_id, guide in enumerate(guide_rows, start=1):
        route_number = guide.get("route_number")
        guide_id_map[route_number] = guide_id

        lines.append(
            insert_line(
                "full_guides",
                [
                    "guide_id",
                    "route_number",
                    "route_title",
                    "full_guide_url",
                    "canonical_url",
                    "article_title",
                    "date_published",
                    "date_modified",
                    "first_paragraph",
                    "guide_polyline_count",
                    "guide_point_count",
                    "scraped_at_utc",
                ],
                [
                    guide_id,
                    guide.get("route_number"),
                    guide.get("route_title"),
                    guide.get("full_guide_url"),
                    guide.get("canonical_url"),
                    guide.get("article_title"),
                    guide.get("date_published"),
                    guide.get("date_modified"),
                    guide.get("first_paragraph"),
                    guide.get("guide_polyline_count"),
                    guide.get("guide_point_count"),
                    guide.get("scraped_at_utc"),
                ],
            )
        )

        for paragraph_order, paragraph_text in enumerate(guide.get("paragraphs", []), start=1):
            lines.append(
                insert_line(
                    "full_guide_paragraphs",
                    ["id", "guide_id", "paragraph_order", "paragraph_text"],
                    [guide_paragraph_id, guide_id, paragraph_order, paragraph_text],
                )
            )
            guide_paragraph_id += 1

        for heading_order, heading_text in enumerate(guide.get("headings", []), start=1):
            lines.append(
                insert_line(
                    "full_guide_headings",
                    ["id", "guide_id", "heading_order", "heading_text"],
                    [guide_heading_id, guide_id, heading_order, heading_text],
                )
            )
            guide_heading_id += 1

        for embed_order, embed in enumerate(guide.get("map_geometry", []), start=1):
            current_embed_id = guide_embed_id
            lines.append(
                insert_line(
                    "full_guide_map_embeds",
                    [
                        "id",
                        "guide_id",
                        "embed_order",
                        "map_embed_url",
                        "map_mid",
                        "map_kml_url",
                        "map_polyline_count",
                        "map_point_count",
                        "map_scrape_error",
                    ],
                    [
                        current_embed_id,
                        guide_id,
                        embed_order,
                        embed.get("map_embed_url"),
                        embed.get("map_mid"),
                        embed.get("map_kml_url"),
                        embed.get("map_polyline_count"),
                        embed.get("map_point_count"),
                        embed.get("map_scrape_error"),
                    ],
                )
            )
            guide_embed_id += 1

            for segment_index, polyline in enumerate(embed.get("map_polylines", []), start=1):
                current_polyline_id = guide_polyline_id
                lines.append(
                    insert_line(
                        "full_guide_map_polylines",
                        ["id", "embed_id", "segment_index", "segment_name", "point_count"],
                        [
                            current_polyline_id,
                            current_embed_id,
                            segment_index,
                            polyline.get("name"),
                            polyline.get("point_count"),
                        ],
                    )
                )
                guide_polyline_id += 1

                for point_order, lat_lng in enumerate(polyline.get("coordinates_lat_lng", []), start=1):
                    if len(lat_lng) < 2:
                        continue
                    lat, lng = lat_lng[0], lat_lng[1]
                    lines.append(
                        insert_line(
                            "full_guide_map_points",
                            ["id", "polyline_id", "point_order", "lat", "lng"],
                            [guide_point_id, current_polyline_id, point_order, lat, lng],
                        )
                    )
                    guide_point_id += 1

    for err_id, err in enumerate(full_payload.get("errors", []), start=1):
        lines.append(
            insert_line(
                "full_guide_errors",
                ["id", "route_number", "route_title", "full_guide_url", "error_text"],
                [
                    err_id,
                    err.get("route_number"),
                    err.get("route_title"),
                    err.get("full_guide_url"),
                    err.get("error"),
                ],
            )
        )

    artifact_files = [
        "iloilo_routes_index.json",
        "iloilo_routes_index.csv",
        "iloilo_route_polylines.geojson",
        "iloilo_full_guides.json",
        "iloilo_full_guides_summary.csv",
        "iloilo_full_guides_polylines.geojson",
        "route_index_source.html",
    ]
    content_types = {
        ".json": "application/json",
        ".csv": "text/csv",
        ".geojson": "application/geo+json",
        ".html": "text/html",
    }
    for filename in artifact_files:
        path = OUTPUT_DIR / filename
        if not path.exists():
            continue
        content_text = path.read_text(encoding="utf-8")
        lines.append(
            insert_line(
                "output_artifacts",
                ["filename", "content_type", "content_text"],
                [filename, content_types.get(path.suffix, "text/plain"), content_text],
            )
        )

    lines.append("")
    lines.append("CREATE INDEX idx_routes_route_number ON routes(route_number);")
    lines.append("CREATE INDEX idx_route_stops_route_id ON route_stops(route_id);")
    lines.append("CREATE INDEX idx_route_map_polylines_route_id ON route_map_polylines(route_id);")
    lines.append("CREATE INDEX idx_route_map_points_polyline_id ON route_map_points(polyline_id);")
    lines.append("CREATE INDEX idx_full_guides_route_number ON full_guides(route_number);")
    lines.append("CREATE INDEX idx_full_guide_paragraphs_guide_id ON full_guide_paragraphs(guide_id);")
    lines.append("CREATE INDEX idx_full_guide_headings_guide_id ON full_guide_headings(guide_id);")
    lines.append("CREATE INDEX idx_full_guide_map_embeds_guide_id ON full_guide_map_embeds(guide_id);")
    lines.append("CREATE INDEX idx_full_guide_map_polylines_embed_id ON full_guide_map_polylines(embed_id);")
    lines.append("CREATE INDEX idx_full_guide_map_points_polyline_id ON full_guide_map_points(polyline_id);")
    lines.append("")
    lines.append("COMMIT;")

    SQL_DUMP_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Created SQL dump: {SQL_DUMP_PATH}")
    print(f"Routes inserted: {len(route_rows)}")
    print(f"Guides inserted: {len(guide_rows)}")


if __name__ == "__main__":
    main()

