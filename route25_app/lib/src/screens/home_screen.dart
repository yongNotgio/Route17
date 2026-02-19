import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/route_models.dart';
import '../services/route_matcher.dart';
import '../services/route_repository.dart';
import 'route_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
  });

  final RouteRepository repository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _originController = TextEditingController();
  final _destinationController = TextEditingController();
  final _matcher = const RouteMatcher();

  late final Future<DatasetLoadResult> _datasetFuture;
  List<RouteMatchResult> _matches = const <RouteMatchResult>[];
  bool _hasSearched = false;
  bool _useCurrentLocation = false;
  OriginLocation? _originLocation;
  bool _isLocating = false;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    _datasetFuture = widget.repository.loadDataset();
    _originController.addListener(_onInputChanged);
    _destinationController.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _originController.removeListener(_onInputChanged);
    _destinationController.removeListener(_onInputChanged);
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    setState(() {});
  }

  Future<void> _refreshCurrentLocation() async {
    setState(() {
      _isLocating = true;
      _locationError = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled on this device.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission is required to set your origin.');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _originLocation = OriginLocation(
          lat: position.latitude,
          lng: position.longitude,
        );
        _isLocating = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _originLocation = null;
        _isLocating = false;
        _locationError = error.toString();
      });
    }
  }

  void _runSearch(PrdDataset dataset) {
    final originQuery = _originController.text.trim();
    final originLocation = _useCurrentLocation ? _originLocation : null;
    final destination = _destinationController.text;
    final matches = _matcher.findRoutes(
      routes: dataset.routes,
      destinationQuery: destination,
      originQuery: originLocation == null ? originQuery : null,
      originLocation: originLocation,
    );

    setState(() {
      _matches = matches;
      _hasSearched = true;
    });
  }

  List<String> _collectStopNames(PrdDataset dataset) {
    final names = <String>{};
    for (final route in dataset.routes) {
      for (final stop in route.stops) {
        if (stop.stopName.trim().isNotEmpty) {
          names.add(stop.stopName.trim());
        }
      }
    }
    final sorted = names.toList()..sort((a, b) => a.compareTo(b));
    return sorted;
  }

  List<String> _suggestions(String query, List<String> stopNames) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return const <String>[];
    }
    return stopNames
        .where((name) => name.toLowerCase().contains(q))
        .take(8)
        .toList(growable: false);
  }

  Widget _buildSuggestionChips({
    required String query,
    required List<String> stopNames,
    required ValueChanged<String> onSelect,
  }) {
    final suggestions = _suggestions(query, stopNames);
    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: suggestions
            .map(
              (value) => ActionChip(
                label: Text(value, overflow: TextOverflow.ellipsis),
                onPressed: () => onSelect(value),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  String _formatLocation(OriginLocation location) {
    return '${location.lat.toStringAsFixed(5)}, ${location.lng.toStringAsFixed(5)}';
  }

  String _formatDistance(double? meters) {
    if (meters == null) {
      return 'Distance from current location: not available';
    }
    if (meters < 1000) {
      return 'Distance from current location: ${meters.round()} m';
    }
    return 'Distance from current location: ${(meters / 1000).toStringAsFixed(2)} km';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DatasetLoadResult>(
      future: _datasetFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Route25')),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Failed to load route data: ${snapshot.error}'),
            ),
          );
        }

        final loadResult = snapshot.data!;
        final dataset = loadResult.dataset;
        final stopNames = _collectStopNames(dataset);
        final sourceLabel = loadResult.source == RouteDataSource.database ? 'Database' : 'Embedded JSON';
        final canSearch = _destinationController.text.trim().isNotEmpty &&
            (!_useCurrentLocation || (_originLocation != null && !_isLocating));

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Route25'),
                Text(
                  '${dataset.routeCount} Iloilo routes loaded - $sourceLabel',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (loadResult.warning != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: const Color(0xFFFFF3CD),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            'Using embedded dataset fallback: ${loadResult.warning}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Find Jeepney Route', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _originController,
                            enabled: !_useCurrentLocation,
                            decoration: const InputDecoration(
                              labelText: 'Origin (optional)',
                              hintText: 'e.g. Jaro Plaza',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          if (!_useCurrentLocation)
                            _buildSuggestionChips(
                              query: _originController.text,
                              stopNames: stopNames,
                              onSelect: (value) {
                                _originController.text = value;
                                _originController.selection =
                                    TextSelection.collapsed(offset: value.length);
                              },
                            ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Use current location as origin'),
                            value: _useCurrentLocation,
                            onChanged: (value) {
                              setState(() {
                                _useCurrentLocation = value;
                              });
                              if (value && _originLocation == null && !_isLocating) {
                                _refreshCurrentLocation();
                              }
                            },
                          ),
                          if (_useCurrentLocation)
                            Material(
                              color: const Color(0xFFE2F4F1),
                              borderRadius: BorderRadius.circular(8),
                              child: ListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                leading: _isLocating
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.my_location),
                                title: const Text('Current location'),
                                subtitle: Text(
                                  _originLocation != null
                                      ? _formatLocation(_originLocation!)
                                      : (_locationError ?? 'Tap refresh to detect your location.'),
                                ),
                                trailing: IconButton(
                                  onPressed: _isLocating ? null : _refreshCurrentLocation,
                                  icon: const Icon(Icons.refresh),
                                  tooltip: 'Refresh location',
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _destinationController,
                            decoration: const InputDecoration(
                              labelText: 'Destination',
                              hintText: 'e.g. SM City Iloilo',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          _buildSuggestionChips(
                            query: _destinationController.text,
                            stopNames: stopNames,
                            onSelect: (value) {
                              _destinationController.text = value;
                              _destinationController.selection =
                                  TextSelection.collapsed(offset: value.length);
                            },
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: canSearch ? () => _runSearch(dataset) : null,
                              icon: const Icon(Icons.route),
                              label: const Text('Find Routes'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Results',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (!_hasSearched)
                    const Text('Enter destination and tap Find Routes.')
                  else if (_matches.isEmpty)
                    const Text('No direct route match found for this destination.')
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _matches.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final match = _matches[index];
                        final route = match.route;

                        final fareText = route.hasFare
                            ? 'Fare: PHP ${route.fareMinPhp?.toStringAsFixed(2) ?? '-'}'
                            : 'Fare: not available in source data';
                        final extraInfo = _useCurrentLocation
                            ? '$fareText\n${_formatDistance(match.originDistanceMeters)}'
                            : fareText;

                        return Card(
                          child: ListTile(
                            title: Text('${route.routeCode} - ${route.routeName}'),
                            subtitle: Text(
                              'Board: ${match.boardingStop.stopName}\n'
                              'Drop-off: ${match.destinationStop.stopName}\n'
                              '$extraInfo',
                            ),
                            isThreeLine: _useCurrentLocation,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              final originSummary = _useCurrentLocation
                                  ? (_originLocation != null
                                      ? 'Current location (${_formatLocation(_originLocation!)})'
                                      : 'Current location unavailable')
                                  : _originController.text.trim();
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => RouteDetailScreen(
                                    match: match,
                                    originQuery: originSummary,
                                    destinationQuery: _destinationController.text.trim(),
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
