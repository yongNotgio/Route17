import 'package:flutter/material.dart';

import '../models/route_models.dart';
import '../services/route_matcher.dart';
import '../services/route_repository.dart';
import 'route_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _originController = TextEditingController();
  final _destinationController = TextEditingController();
  final _repository = const RouteRepository();
  final _matcher = const RouteMatcher();

  late final Future<PrdDataset> _datasetFuture;
  List<RouteMatchResult> _matches = const <RouteMatchResult>[];
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _datasetFuture = _repository.loadDataset();
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

  void _runSearch(PrdDataset dataset) {
    final destination = _destinationController.text;
    final origin = _originController.text;
    final matches = _matcher.findRoutes(
      routes: dataset.routes,
      destinationQuery: destination,
      originQuery: origin,
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PrdDataset>(
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

        final dataset = snapshot.data!;
        final stopNames = _collectStopNames(dataset);

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Route25'),
                Text(
                  '${dataset.routeCount} Iloilo routes loaded',
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
                            decoration: const InputDecoration(
                              labelText: 'Origin (optional)',
                              hintText: 'e.g. Jaro Plaza',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          _buildSuggestionChips(
                            query: _originController.text,
                            stopNames: stopNames,
                            onSelect: (value) {
                              _originController.text = value;
                              _originController.selection =
                                  TextSelection.collapsed(offset: value.length);
                            },
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
                              onPressed: () => _runSearch(dataset),
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

                        return Card(
                          child: ListTile(
                            title: Text('${route.routeCode} - ${route.routeName}'),
                            subtitle: Text(
                              'Board: ${match.boardingStop.stopName}\n'
                              'Drop-off: ${match.destinationStop.stopName}\n'
                              '$fareText',
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => RouteDetailScreen(
                                    match: match,
                                    originQuery: _originController.text.trim(),
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
