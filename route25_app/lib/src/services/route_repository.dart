import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/route_models.dart';

class RouteRepository {
  const RouteRepository();

  static const _assetPath = 'assets/data/prd_routes_dataset.json';

  Future<PrdDataset> loadDataset() async {
    final raw = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid dataset JSON format.');
    }
    return PrdDataset.fromJson(decoded);
  }
}

