import '../models/route_models.dart';

class RouteMatchResult {
  const RouteMatchResult({
    required this.route,
    required this.originStopIndex,
    required this.destinationStopIndex,
  });

  final JeepRoute route;
  final int? originStopIndex;
  final int destinationStopIndex;

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
      }

      results.add(
        RouteMatchResult(
          route: route,
          originStopIndex: originIndex,
          destinationStopIndex: destinationIndex,
        ),
      );
    }

    results.sort((a, b) {
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
}
