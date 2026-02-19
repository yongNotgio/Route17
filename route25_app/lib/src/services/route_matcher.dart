import 'dart:math';

import '../models/route_models.dart';

class OriginLocation {
  const OriginLocation({
    required this.lat,
    required this.lng,
  });

  final double lat;
  final double lng;
}

class RouteMatchResult {
  const RouteMatchResult({
    required this.route,
    required this.originStopIndex,
    required this.destinationStopIndex,
    required this.originDistanceMeters,
  });

  final JeepRoute route;
  final int? originStopIndex;
  final int destinationStopIndex;
  final double? originDistanceMeters;

  RouteStop get destinationStop => route.stops[destinationStopIndex];

  RouteStop get boardingStop {
    if (originStopIndex != null && originStopIndex! >= 0) {
      return route.stops[originStopIndex!];
    }
    return route.stops.first;
  }

  int get stopSpan {
    if (originStopIndex == null) {
      return destinationStopIndex + 1;
    }
    return (destinationStopIndex - originStopIndex!).abs() + 1;
  }

  bool get isDirect => originStopIndex != null;
}

class RouteMatcher {
  const RouteMatcher();

  List<RouteMatchResult> findRoutes({
    required List<JeepRoute> routes,
    required String destinationQuery,
    String? originQuery,
    OriginLocation? originLocation,
  }) {
    final dest = destinationQuery.trim();
    final origin = (originQuery ?? '').trim();

    if (dest.isEmpty) {
      return const <RouteMatchResult>[];
    }

    final results = <RouteMatchResult>[];

    for (final route in routes) {
      if (route.stops.isEmpty) {
        continue;
      }

      final destinationIndex = route.indexOfStop(dest);
      if (destinationIndex < 0) {
        continue;
      }

      int? originIndex;
      if (origin.isNotEmpty) {
        originIndex = route.indexOfStop(origin);
        if (originIndex < 0) {
          continue;
        }
      } else if (originLocation != null) {
        originIndex = _nearestStopIndexForLocation(
          route,
          originLocation,
          destinationIndex: destinationIndex,
        );
      }

      final originDistanceMeters = originLocation == null
          ? null
          : _nearestDistanceForLocation(route, originLocation);

      results.add(
        RouteMatchResult(
          route: route,
          originStopIndex: originIndex,
          destinationStopIndex: destinationIndex,
          originDistanceMeters: originDistanceMeters,
        ),
      );
    }

    results.sort((a, b) {
      final aDistance = a.originDistanceMeters;
      final bDistance = b.originDistanceMeters;
      if (aDistance != null && bDistance != null) {
        final distanceCmp = aDistance.compareTo(bDistance);
        if (distanceCmp != 0) {
          return distanceCmp;
        }
      } else if (aDistance != null && bDistance == null) {
        return -1;
      } else if (aDistance == null && bDistance != null) {
        return 1;
      }

      final aCoordScore = _coordinateScore(a.route);
      final bCoordScore = _coordinateScore(b.route);
      if (aCoordScore != bCoordScore) {
        return bCoordScore.compareTo(aCoordScore);
      }

      final aFare = a.route.fareMinPhp ?? double.infinity;
      final bFare = b.route.fareMinPhp ?? double.infinity;
      final fareCmp = aFare.compareTo(bFare);
      if (fareCmp != 0) {
        return fareCmp;
      }

      final spanCmp = a.stopSpan.compareTo(b.stopSpan);
      if (spanCmp != 0) {
        return spanCmp;
      }

      return a.route.routeNumber.compareTo(b.route.routeNumber);
    });

    return results;
  }

  int _coordinateScore(JeepRoute route) {
    final count = route.stops.where((s) => s.hasCoordinates).length;
    if (count == 0 && route.hasMapGeometry) {
      return 1;
    }
    return count;
  }

  int? _nearestStopIndexForLocation(
    JeepRoute route,
    OriginLocation location, {
    required int destinationIndex,
  }) {
    int? bestIndex = _nearestStopIndexInRange(
      route,
      location,
      minIndex: 0,
      maxIndex: destinationIndex,
    );

    bestIndex ??= _nearestStopIndexInRange(
      route,
      location,
      minIndex: 0,
      maxIndex: route.stops.length - 1,
    );

    return bestIndex;
  }

  int? _nearestStopIndexInRange(
    JeepRoute route,
    OriginLocation location, {
    required int minIndex,
    required int maxIndex,
  }) {
    double? bestDistance;
    int? bestIndex;

    for (var i = minIndex; i <= maxIndex; i++) {
      final stop = route.stops[i];
      if (!stop.hasCoordinates || stop.lat == null || stop.lng == null) {
        continue;
      }

      final distance = _distanceMeters(
        location.lat,
        location.lng,
        stop.lat!,
        stop.lng!,
      );

      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    return bestIndex;
  }

  double? _nearestDistanceForLocation(JeepRoute route, OriginLocation location) {
    double? bestDistance;

    for (final stop in route.stops) {
      if (!stop.hasCoordinates || stop.lat == null || stop.lng == null) {
        continue;
      }

      final distance = _distanceMeters(
        location.lat,
        location.lng,
        stop.lat!,
        stop.lng!,
      );
      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
      }
    }

    for (final segment in route.mapPolylines) {
      for (final coord in segment.coordinatesLatLng) {
        final distance = _distanceMeters(
          location.lat,
          location.lng,
          coord.lat,
          coord.lng,
        );
        if (bestDistance == null || distance < bestDistance) {
          bestDistance = distance;
        }
      }
    }

    return bestDistance;
  }

  double _distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusMeters = 6371000.0;

    final dLat = _degreesToRadians(lat2 - lat1);
    final dLng = _degreesToRadians(lng2 - lng1);
    final rLat1 = _degreesToRadians(lat1);
    final rLat2 = _degreesToRadians(lat2);

    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(rLat1) * cos(rLat2) * (sin(dLng / 2) * sin(dLng / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180.0);
  }
}
