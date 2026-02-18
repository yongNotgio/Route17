import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/route_models.dart';
import '../services/route_matcher.dart';

class RouteDetailScreen extends StatelessWidget {
  const RouteDetailScreen({
    super.key,
    required this.match,
    required this.originQuery,
    required this.destinationQuery,
  });

  final RouteMatchResult match;
  final String originQuery;
  final String destinationQuery;

  static const LatLng _iloiloCenter = LatLng(10.7202, 122.5621);

  @override
  Widget build(BuildContext context) {
    final route = match.route;
    final polylines = _buildPolylines(route);
    final markers = _buildMarkers(route.stops);
    final center = _initialCenter(route);

    return Scaffold(
      appBar: AppBar(
        title: Text(route.routeCode),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 13.2,
                minZoom: 10,
                maxZoom: 18,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.route25.app',
                ),
                if (polylines.isNotEmpty)
                  PolylineLayer(
                    polylines: polylines,
                  ),
                if (markers.isNotEmpty)
                  MarkerLayer(
                    markers: markers,
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(route.routeTitle, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('Boarding: ${match.boardingStop.stopName}'),
                Text('Drop-off: ${match.destinationStop.stopName}'),
                if (originQuery.isNotEmpty || destinationQuery.isNotEmpty)
                  Text('Search: $originQuery -> $destinationQuery'),
                const SizedBox(height: 8),
                Text(
                  route.hasFare
                      ? 'Estimated fare: PHP ${route.fareMinPhp?.toStringAsFixed(2)}'
                      : 'Estimated fare: not available in source data',
                ),
                Text('Map segments: ${route.mapPolylineCount}'),
                Text('Map points: ${route.mapPointCount}'),
                const SizedBox(height: 10),
                Text(
                  'Stops',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                ..._buildStopTiles(route.stops),
              ],
            ),
          ),
        ],
      ),
    );
  }

  LatLng _initialCenter(JeepRoute route) {
    for (final stop in route.stops) {
      if (stop.hasCoordinates && stop.lat != null && stop.lng != null) {
        return LatLng(stop.lat!, stop.lng!);
      }
    }
    for (final segment in route.mapPolylines) {
      if (segment.coordinatesLatLng.isNotEmpty) {
        final coord = segment.coordinatesLatLng.first;
        return LatLng(coord.lat, coord.lng);
      }
    }
    return _iloiloCenter;
  }

  List<Polyline> _buildPolylines(JeepRoute route) {
    final lines = <Polyline>[];
    for (final segment in route.mapPolylines) {
      if (segment.coordinatesLatLng.length < 2) {
        continue;
      }
      lines.add(
        Polyline(
          points: segment.coordinatesLatLng
              .map((coord) => LatLng(coord.lat, coord.lng))
              .toList(growable: false),
          strokeWidth: 4,
          color: const Color(0xFF0F766E),
        ),
      );
    }
    return lines;
  }

  List<Marker> _buildMarkers(List<RouteStop> stops) {
    final markers = <Marker>[];
    for (final stop in stops) {
      if (!stop.hasCoordinates || stop.lat == null || stop.lng == null) {
        continue;
      }
      markers.add(
        Marker(
          width: 30,
          height: 30,
          point: LatLng(stop.lat!, stop.lng!),
          child: const Icon(
            Icons.location_on,
            color: Color(0xFF0EA5E9),
            size: 26,
          ),
        ),
      );
    }
    return markers;
  }

  List<Widget> _buildStopTiles(List<RouteStop> stops) {
    if (stops.isEmpty) {
      return const [Text('No stop data available.')];
    }

    final tiles = <Widget>[];
    for (final stop in stops) {
      final isBoarding = stop.stopName == match.boardingStop.stopName;
      final isDropOff = stop.stopName == match.destinationStop.stopName;

      tiles.add(
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            isBoarding
                ? Icons.play_circle_fill
                : isDropOff
                    ? Icons.flag
                    : Icons.radio_button_unchecked,
            color: isBoarding || isDropOff ? const Color(0xFF0F766E) : null,
          ),
          title: Text(stop.stopName),
          subtitle: stop.hasCoordinates && stop.lat != null && stop.lng != null
              ? Text('${stop.lat!.toStringAsFixed(5)}, ${stop.lng!.toStringAsFixed(5)}')
              : null,
        ),
      );
    }
    return tiles;
  }
}
