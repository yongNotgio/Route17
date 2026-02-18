class PrdDataset {
  const PrdDataset({
    required this.generatedAtUtc,
    required this.routeCount,
    required this.routes,
  });

  final String generatedAtUtc;
  final int routeCount;
  final List<JeepRoute> routes;

  factory PrdDataset.fromJson(Map<String, dynamic> json) {
    final routeJson = (json['routes'] as List<dynamic>? ?? const <dynamic>[]);

    return PrdDataset(
      generatedAtUtc: json['generated_at_utc'] as String? ?? '',
      routeCount: json['route_count'] as int? ?? routeJson.length,
      routes: routeJson
          .whereType<Map<String, dynamic>>()
          .map(JeepRoute.fromJson)
          .toList(growable: false),
    );
  }
}

class JeepRoute {
  const JeepRoute({
    required this.routeNumber,
    required this.routeCode,
    required this.routeName,
    required this.routeTitle,
    required this.fareMinPhp,
    required this.fareMaxPhp,
    required this.fareText,
    required this.mapEmbedUrl,
    required this.mapMid,
    required this.mapKmlUrl,
    required this.mapPolylineCount,
    required this.mapPointCount,
    required this.stopCount,
    required this.stops,
    required this.mapPolylines,
  });

  final int routeNumber;
  final String routeCode;
  final String routeName;
  final String routeTitle;
  final double? fareMinPhp;
  final double? fareMaxPhp;
  final String? fareText;
  final String? mapEmbedUrl;
  final String? mapMid;
  final String? mapKmlUrl;
  final int mapPolylineCount;
  final int mapPointCount;
  final int stopCount;
  final List<RouteStop> stops;
  final List<RoutePolylineSegment> mapPolylines;

  factory JeepRoute.fromJson(Map<String, dynamic> json) {
    final stopJson = (json['stops'] as List<dynamic>? ?? const <dynamic>[]);
    final polylineJson =
        (json['map_polylines'] as List<dynamic>? ?? const <dynamic>[]);

    return JeepRoute(
      routeNumber: json['route_number'] as int? ?? 0,
      routeCode: json['route_code'] as String? ?? '',
      routeName: json['route_name'] as String? ?? '',
      routeTitle: json['route_title'] as String? ?? '',
      fareMinPhp: _toDouble(json['fare_min_php']),
      fareMaxPhp: _toDouble(json['fare_max_php']),
      fareText: json['fare_text'] as String?,
      mapEmbedUrl: json['map_embed_url'] as String?,
      mapMid: json['map_mid'] as String?,
      mapKmlUrl: json['map_kml_url'] as String?,
      mapPolylineCount: json['map_polyline_count'] as int? ?? 0,
      mapPointCount: json['map_point_count'] as int? ?? 0,
      stopCount: json['stop_count'] as int? ?? stopJson.length,
      stops: stopJson
          .whereType<Map<String, dynamic>>()
          .map(RouteStop.fromJson)
          .toList(growable: false),
      mapPolylines: polylineJson
          .whereType<Map<String, dynamic>>()
          .map(RoutePolylineSegment.fromJson)
          .toList(growable: false),
    );
  }

  bool get hasMapGeometry => mapPolylineCount > 0 && mapPolylines.isNotEmpty;

  bool get hasFare => fareMinPhp != null || fareMaxPhp != null;

  int indexOfStop(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return -1;
    }
    for (var i = 0; i < stops.length; i++) {
      if (stops[i].stopName.toLowerCase().contains(q)) {
        return i;
      }
    }
    return -1;
  }
}

class RouteStop {
  const RouteStop({
    required this.stopOrder,
    required this.stopName,
    required this.lat,
    required this.lng,
    required this.sourceType,
    required this.hasCoordinates,
  });

  final int stopOrder;
  final String stopName;
  final double? lat;
  final double? lng;
  final String sourceType;
  final bool hasCoordinates;

  factory RouteStop.fromJson(Map<String, dynamic> json) {
    return RouteStop(
      stopOrder: json['stop_order'] as int? ?? 0,
      stopName: json['stop_name'] as String? ?? '',
      lat: _toDouble(json['lat']),
      lng: _toDouble(json['lng']),
      sourceType: json['source_type'] as String? ?? '',
      hasCoordinates: json['has_coordinates'] as bool? ?? false,
    );
  }
}

class RoutePolylineSegment {
  const RoutePolylineSegment({
    required this.name,
    required this.pointCount,
    required this.coordinatesLatLng,
  });

  final String name;
  final int pointCount;
  final List<RouteCoordinate> coordinatesLatLng;

  factory RoutePolylineSegment.fromJson(Map<String, dynamic> json) {
    final coordsJson =
        (json['coordinates_lat_lng'] as List<dynamic>? ?? const <dynamic>[]);
    return RoutePolylineSegment(
      name: json['name'] as String? ?? '',
      pointCount: json['point_count'] as int? ?? 0,
      coordinatesLatLng: coordsJson
          .whereType<List<dynamic>>()
          .map(RouteCoordinate.fromArray)
          .where((coord) => coord != null)
          .cast<RouteCoordinate>()
          .toList(growable: false),
    );
  }
}

class RouteCoordinate {
  const RouteCoordinate({
    required this.lat,
    required this.lng,
  });

  final double lat;
  final double lng;

  static RouteCoordinate? fromArray(List<dynamic> values) {
    if (values.length < 2) {
      return null;
    }
    final lat = _toDouble(values[0]);
    final lng = _toDouble(values[1]);
    if (lat == null || lng == null) {
      return null;
    }
    return RouteCoordinate(lat: lat, lng: lng);
  }
}

double? _toDouble(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value.toString());
}

