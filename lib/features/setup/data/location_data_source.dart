import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/location.dart';

/// Where districts and their blocks come from.
///
/// An interface so the bundled JSON can be swapped for a FastAPI district/block
/// endpoint later without the screen noticing. Note the shape: blocks arrive
/// nested under their district, which is what makes it impossible to offer a
/// block that belongs somewhere else.
abstract interface class LocationDataSource {
  Future<List<District>> districts();
}

/// Reads the dataset bundled with the app.
///
/// Bundled on purpose: a teacher must be able to fill this form with no
/// connection, so the list cannot be a network call.
class AssetLocationDataSource implements LocationDataSource {
  AssetLocationDataSource({this.assetPath = defaultAssetPath});

  static const String defaultAssetPath = 'assets/data/jharkhand_districts.json';

  final String assetPath;

  /// Parsed once and held: 24 districts and ~260 blocks is small, and reparsing
  /// on every rebuild would be wasted work on a low-end device.
  List<District>? _cache;

  @override
  Future<List<District>> districts() async {
    final List<District>? cached = _cache;
    if (cached != null) return cached;

    final String raw = await rootBundle.loadString(assetPath);
    final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
    final List<District> parsed = <District>[
      for (final dynamic d in json['districts'] as List<dynamic>)
        District.fromJson(d as Map<String, dynamic>),
    ]..sort((District a, District b) => a.name.compareTo(b.name));

    return _cache = parsed;
  }
}

/// Fixed list for tests and previews.
class StaticLocationDataSource implements LocationDataSource {
  const StaticLocationDataSource(this._districts);

  final List<District> _districts;

  @override
  Future<List<District>> districts() async => _districts;
}
