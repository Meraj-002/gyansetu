import 'dart:convert';

import '../../../services/storage/secure_storage_service.dart';
import '../models/support_report.dart';

/// Where offline-held translation issue reports wait until they can be sent.
abstract interface class SupportReportStore {
  Future<List<SupportReport>> reports();

  /// Appends a report, returning false when it could not be persisted.
  Future<bool> add(SupportReport report);
}

/// Device-persisted implementation via secure storage.
class LocalSupportReportStore implements SupportReportStore {
  const LocalSupportReportStore(this._storage);

  static const String _key = 'profile.support.reports';

  final SecureStorageService _storage;

  @override
  Future<List<SupportReport>> reports() async {
    final String? raw = await _storage.read(_key);
    if (raw == null || raw.isEmpty) return const <SupportReport>[];
    try {
      return <SupportReport>[
        for (final dynamic r in jsonDecode(raw) as List<dynamic>)
          SupportReport.fromJson(r as Map<String, dynamic>),
      ];
    } on FormatException {
      return const <SupportReport>[];
    } on TypeError {
      return const <SupportReport>[];
    }
  }

  @override
  Future<bool> add(SupportReport report) async {
    final List<SupportReport> all = await reports();
    final String next = jsonEncode(<Object>[
      for (final SupportReport r in <SupportReport>[...all, report]) r.toJson(),
    ]);
    return _storage.write(_key, next);
  }
}