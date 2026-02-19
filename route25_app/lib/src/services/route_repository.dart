import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/route_models.dart';

enum RouteDataSource {
  asset,
  database,
}

class DatasetLoadResult {
  const DatasetLoadResult({
    required this.dataset,
    required this.source,
    this.warning,
  });

  final PrdDataset dataset;
  final RouteDataSource source;
  final Object? warning;
}

class RouteRepository {
  const RouteRepository({
    this.supabaseClient,
  });

  final SupabaseClient? supabaseClient;

  static const _assetPath = 'assets/data/prd_routes_dataset.json';

  Future<DatasetLoadResult> loadDataset() async {
    final client = supabaseClient;
    if (client != null) {
      try {
        final dataset = await _loadDatasetFromSupabase(client);
        if (dataset.routes.isNotEmpty) {
          return DatasetLoadResult(
            dataset: dataset,
            source: RouteDataSource.database,
          );
        }
        final fallback = await _loadDatasetFromAsset();
        return DatasetLoadResult(
          dataset: fallback,
          source: RouteDataSource.asset,
          warning: const FormatException(
            'Database returned no routes. Using embedded dataset instead.',
          ),
        );
      } catch (error) {
        final fallback = await _loadDatasetFromAsset();
        return DatasetLoadResult(
          dataset: fallback,
          source: RouteDataSource.asset,
          warning: error,
        );
      }
    }

    final dataset = await _loadDatasetFromAsset();
    return DatasetLoadResult(
      dataset: dataset,
      source: RouteDataSource.asset,
    );
  }

  Future<PrdDataset> _loadDatasetFromAsset() async {
    final raw = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid dataset JSON format.');
    }
    return PrdDataset.fromJson(decoded);
  }

  Future<PrdDataset> _loadDatasetFromSupabase(SupabaseClient client) async {
    try {
      final fromRpc = await _loadDatasetFromSupabaseRpc(client);
      if (fromRpc.routes.isNotEmpty) {
        return fromRpc;
      }
    } catch (_) {
      // Fall through to direct table reads for compatibility with different schemas.
    }

    try {
      final fromPrdTables = await _loadDatasetFromSupabasePrdTables(client);
      if (fromPrdTables.routes.isNotEmpty) {
        return fromPrdTables;
      }
    } catch (_) {
      // Fall through to legacy table reads.
    }

    return _loadDatasetFromSupabaseLegacyTables(client);
  }

  Future<PrdDataset> _loadDatasetFromSupabasePrdTables(SupabaseClient client) async {
    final responses = await Future.wait<dynamic>([
      client.from('prd_meta').select(
        'generated_at_utc, route_count',
      ).limit(1),
      client.from('prd_routes').select(
        'route_id, route_number, route_code, route_name, fare_min_php, fare_max_php, fare_text, stop_count',
      ),
      client.from('prd_route_stops').select(
        'route_id, stop_order, stop_name, lat, lng',
      ),
    ]);

    final metaRows = _toMapList(responses[0]);
    final routeRows = _toMapList(responses[1]);
    final stopRows = _toMapList(responses[2]);

    final stopsByRoute = <int, List<Map<String, dynamic>>>{};
    for (final row in stopRows) {
      final routeId = _toInt(row['route_id']);
      if (routeId == null) {
        continue;
      }
      stopsByRoute.putIfAbsent(routeId, () => <Map<String, dynamic>>[]).add(row);
    }
    for (final routeStops in stopsByRoute.values) {
      routeStops.sort(
        (a, b) => (_toInt(a['stop_order']) ?? 0).compareTo(_toInt(b['stop_order']) ?? 0),
      );
    }

    final routes = <JeepRoute>[];
    for (final row in routeRows) {
      final routeId = _toInt(row['route_id']);
      final routeNumber = _toInt(row['route_number']);
      if (routeId == null || routeNumber == null || routeNumber <= 0) {
        continue;
      }

      final routeCodeRaw = (row['route_code'] as String?)?.trim() ?? '';
      final routeCode = routeCodeRaw.isEmpty ? 'ROUTE $routeNumber' : routeCodeRaw;
      final routeNameRaw = (row['route_name'] as String?)?.trim() ?? '';
      final routeName = routeNameRaw.isEmpty ? routeCode : routeNameRaw;
      final stopRowsForRoute = stopsByRoute[routeId] ?? const <Map<String, dynamic>>[];

      final stops = stopRowsForRoute
          .map(
            (stop) {
              final lat = _toDouble(stop['lat']);
              final lng = _toDouble(stop['lng']);
              return RouteStop(
                stopOrder: _toInt(stop['stop_order']) ?? 0,
                stopName: (stop['stop_name'] as String?) ?? '',
                lat: lat,
                lng: lng,
                sourceType: 'prd_route_stops',
                hasCoordinates: lat != null && lng != null,
              );
            },
          )
          .toList(growable: false);

      routes.add(
        JeepRoute(
          routeNumber: routeNumber,
          routeCode: routeCode,
          routeName: routeName,
          routeTitle: routeNameRaw.isEmpty ? routeCode : '$routeCode $routeNameRaw',
          fareMinPhp: _toDouble(row['fare_min_php']),
          fareMaxPhp: _toDouble(row['fare_max_php']),
          fareText: row['fare_text'] as String?,
          mapEmbedUrl: null,
          mapMid: null,
          mapKmlUrl: null,
          mapPolylineCount: 0,
          mapPointCount: 0,
          stopCount: _toInt(row['stop_count']) ?? stops.length,
          stops: stops,
          mapPolylines: const <RoutePolylineSegment>[],
        ),
      );
    }

    routes.sort((a, b) => a.routeNumber.compareTo(b.routeNumber));

    final generatedAtUtc = (metaRows.isNotEmpty ? metaRows.first['generated_at_utc'] as String? : null) ??
        DateTime.now().toUtc().toIso8601String();
    final routeCount =
        (metaRows.isNotEmpty ? _toInt(metaRows.first['route_count']) : null) ?? routes.length;

    return PrdDataset(
      generatedAtUtc: generatedAtUtc,
      routeCount: routeCount,
      routes: routes,
    );
  }

  Future<PrdDataset> _loadDatasetFromSupabaseLegacyTables(SupabaseClient client) async {
    final responses = await Future.wait<dynamic>([
      client.from('routes').select(
        'route_id, route_number, route_title, map_embed_url, map_mid, map_kml_url, '
        'map_polyline_count, map_point_count',
      ),
      client.from('route_stops').select(
        'route_id, stop_order, stop_name',
      ),
      client.from('route_map_polylines').select(
        'id, route_id, segment_index, segment_name, point_count',
      ),
      client.from('route_map_points').select(
        'polyline_id, point_order, lat, lng',
      ),
    ]);

    final routeRows = _toMapList(responses[0]);
    final stopRows = _toMapList(responses[1]);
    final polylineRows = _toMapList(responses[2]);
    final pointRows = _toMapList(responses[3]);

    final stopsByRoute = <int, List<Map<String, dynamic>>>{};
    for (final row in stopRows) {
      final routeId = _toInt(row['route_id']);
      if (routeId == null) {
        continue;
      }
      stopsByRoute.putIfAbsent(routeId, () => <Map<String, dynamic>>[]).add(row);
    }
    for (final routeStops in stopsByRoute.values) {
      routeStops.sort(
        (a, b) => (_toInt(a['stop_order']) ?? 0).compareTo(_toInt(b['stop_order']) ?? 0),
      );
    }

    final pointsByPolyline = <int, List<Map<String, dynamic>>>{};
    for (final row in pointRows) {
      final polylineId = _toInt(row['polyline_id']);
      if (polylineId == null) {
        continue;
      }
      pointsByPolyline.putIfAbsent(polylineId, () => <Map<String, dynamic>>[]).add(row);
    }
    for (final polylinePoints in pointsByPolyline.values) {
      polylinePoints.sort(
        (a, b) => (_toInt(a['point_order']) ?? 0).compareTo(_toInt(b['point_order']) ?? 0),
      );
    }

    final polylineRowsByRoute = <int, List<Map<String, dynamic>>>{};
    for (final row in polylineRows) {
      final routeId = _toInt(row['route_id']);
      if (routeId == null) {
        continue;
      }
      polylineRowsByRoute.putIfAbsent(routeId, () => <Map<String, dynamic>>[]).add(row);
    }
    for (final routePolylineRows in polylineRowsByRoute.values) {
      routePolylineRows.sort(
        (a, b) => (_toInt(a['segment_index']) ?? 0).compareTo(_toInt(b['segment_index']) ?? 0),
      );
    }

    final routes = <JeepRoute>[];
    for (final row in routeRows) {
      final routeId = _toInt(row['route_id']);
      final routeNumber = _toInt(row['route_number']);
      if (routeId == null || routeNumber == null || routeNumber <= 0) {
        continue;
      }

      final routeTitle = (row['route_title'] as String?) ?? '';
      final stopRowsForRoute = stopsByRoute[routeId] ?? const <Map<String, dynamic>>[];
      final stops = stopRowsForRoute
          .map(
            (stop) => RouteStop(
              stopOrder: _toInt(stop['stop_order']) ?? 0,
              stopName: (stop['stop_name'] as String?) ?? '',
              lat: null,
              lng: null,
              sourceType: 'route_stops',
              hasCoordinates: false,
            ),
          )
          .toList(growable: false);

      final polylineSegments = <RoutePolylineSegment>[];
      for (final polylineRow in polylineRowsByRoute[routeId] ?? const <Map<String, dynamic>>[]) {
        final polylineId = _toInt(polylineRow['id']);
        if (polylineId == null) {
          continue;
        }

        final points = pointsByPolyline[polylineId] ?? const <Map<String, dynamic>>[];
        final coordinates = <RouteCoordinate>[];
        for (final point in points) {
          final lat = _toDouble(point['lat']);
          final lng = _toDouble(point['lng']);
          if (lat == null || lng == null) {
            continue;
          }
          coordinates.add(RouteCoordinate(lat: lat, lng: lng));
        }

        polylineSegments.add(
          RoutePolylineSegment(
            name: (polylineRow['segment_name'] as String?) ?? '',
            pointCount: _toInt(polylineRow['point_count']) ?? coordinates.length,
            coordinatesLatLng: coordinates,
          ),
        );
      }

      final mapPointCount = _toInt(row['map_point_count']) ??
          polylineSegments.fold<int>(0, (sum, segment) => sum + segment.pointCount);
      final routeCode = 'ROUTE $routeNumber';
      final routeName = routeTitle
          .replaceFirst(RegExp(r'^ROUTE\s+\d+\s*', caseSensitive: false), '')
          .trim();

      routes.add(
        JeepRoute(
          routeNumber: routeNumber,
          routeCode: routeCode,
          routeName: routeName.isEmpty ? routeTitle : routeName,
          routeTitle: routeTitle,
          fareMinPhp: null,
          fareMaxPhp: null,
          fareText: null,
          mapEmbedUrl: row['map_embed_url'] as String?,
          mapMid: row['map_mid'] as String?,
          mapKmlUrl: row['map_kml_url'] as String?,
          mapPolylineCount: _toInt(row['map_polyline_count']) ?? polylineSegments.length,
          mapPointCount: mapPointCount,
          stopCount: stops.length,
          stops: stops,
          mapPolylines: polylineSegments,
        ),
      );
    }

    routes.sort((a, b) => a.routeNumber.compareTo(b.routeNumber));

    return PrdDataset(
      generatedAtUtc: DateTime.now().toUtc().toIso8601String(),
      routeCount: routes.length,
      routes: routes,
    );
  }

  Future<PrdDataset> _loadDatasetFromSupabaseRpc(SupabaseClient client) async {
    final response = await client.rpc('get_route25_dataset');

    final map = _toJsonMap(response);
    if (map == null) {
      throw const FormatException('RPC get_route25_dataset returned invalid JSON payload.');
    }

    return PrdDataset.fromJson(map);
  }

  Map<String, dynamic>? _toJsonMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    if (value is String) {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _toMapList(dynamic data) {
    if (data is! List) {
      return const <Map<String, dynamic>>[];
    }
    return data.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  }

  int? _toInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
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
}
