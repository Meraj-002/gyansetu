import 'dart:convert';

import '../../../core/utils/app_logger.dart';
import '../../../models/worksheet.dart';
import '../../../services/storage/secure_storage_service.dart';

/// Where generated worksheets live.
///
/// A worksheet is made to be used later — printed, read out, handed round — so
/// it is written to the device the moment it exists and needs no connection to
/// be read back. The Resources screen will list what is in here.
abstract interface class WorksheetRepository {
  Future<void> save(Worksheet worksheet);

  Future<Worksheet?> byId(String id);

  /// Newest first.
  Future<List<Worksheet>> all({int limit = 30});

  Future<List<Worksheet>> forLesson(String lessonId);

  Future<void> delete(String id);
}

/// Worksheets in the app's existing secure store.
///
/// Bounded, because this runs on a phone with little free space and a term of
/// worksheets would otherwise grow without limit.
class LocalWorksheetRepository implements WorksheetRepository {
  LocalWorksheetRepository(this._storage, {this.maxWorksheets = 40});

  static const String _key = 'worksheets.saved';

  final SecureStorageService _storage;
  final int maxWorksheets;

  Map<String, Worksheet>? _cache;

  Future<Map<String, Worksheet>> _load() async {
    final Map<String, Worksheet>? held = _cache;
    if (held != null) return held;

    final String? raw = await _storage.read(_key);
    if (raw == null || raw.isEmpty) return _cache = <String, Worksheet>{};
    try {
      final Map<String, dynamic> decoded =
          jsonDecode(raw) as Map<String, dynamic>;
      return _cache = <String, Worksheet>{
        for (final MapEntry<String, dynamic> e in decoded.entries)
          e.key: Worksheet.fromJson(e.value as Map<String, dynamic>),
      };
    } on Object catch (error) {
      AppLogger.error('saved worksheets could not be read', error: error);
      return _cache = <String, Worksheet>{};
    }
  }

  Future<void> _flush(Map<String, Worksheet> values) async {
    _cache = values;
    await _storage.write(
      _key,
      jsonEncode(<String, dynamic>{
        for (final MapEntry<String, Worksheet> e in values.entries)
          e.key: e.value.toJson(),
      }),
    );
  }

  @override
  Future<void> save(Worksheet worksheet) async {
    final Map<String, Worksheet> values =
        Map<String, Worksheet>.from(await _load());
    values[worksheet.id] = worksheet;

    while (values.length > maxWorksheets) {
      final String oldest = values.entries
          .reduce(
            (MapEntry<String, Worksheet> a, MapEntry<String, Worksheet> b) =>
                a.value.generatedAt.isBefore(b.value.generatedAt) ? a : b,
          )
          .key;
      if (oldest == worksheet.id) break;
      values.remove(oldest);
    }

    await _flush(values);
  }

  @override
  Future<Worksheet?> byId(String id) async => (await _load())[id];

  @override
  Future<List<Worksheet>> all({int limit = 30}) async {
    final List<Worksheet> values = (await _load()).values.toList()
      ..sort(
        (Worksheet a, Worksheet b) => b.generatedAt.compareTo(a.generatedAt),
      );
    return values.take(limit).toList(growable: false);
  }

  @override
  Future<List<Worksheet>> forLesson(String lessonId) async {
    final List<Worksheet> values = (await _load())
        .values
        .where((Worksheet w) => w.lessonId == lessonId)
        .toList()
      ..sort(
        (Worksheet a, Worksheet b) => b.generatedAt.compareTo(a.generatedAt),
      );
    return values;
  }

  @override
  Future<void> delete(String id) async {
    final Map<String, Worksheet> values =
        Map<String, Worksheet>.from(await _load());
    values.remove(id);
    await _flush(values);
  }
}

/// Worksheets in memory, for tests.
class InMemoryWorksheetRepository implements WorksheetRepository {
  final Map<String, Worksheet> values = <String, Worksheet>{};

  int saveCalls = 0;
  bool failOnSave = false;

  @override
  Future<void> save(Worksheet worksheet) async {
    saveCalls++;
    if (failOnSave) throw StateError('storage unavailable');
    values[worksheet.id] = worksheet;
  }

  @override
  Future<Worksheet?> byId(String id) async => values[id];

  @override
  Future<List<Worksheet>> all({int limit = 30}) async =>
      values.values.take(limit).toList();

  @override
  Future<List<Worksheet>> forLesson(String lessonId) async =>
      values.values.where((Worksheet w) => w.lessonId == lessonId).toList();

  @override
  Future<void> delete(String id) async => values.remove(id);
}
