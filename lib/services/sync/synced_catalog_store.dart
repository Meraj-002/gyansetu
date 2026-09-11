import 'dart:convert';

import '../../models/lesson.dart';
import '../storage/secure_storage_service.dart';

/// The server's lesson catalogue, cached whenever a pull returns it.
///
/// Written as a whole document on every pull so a stale lesson can never
/// survive; the lesson grid reads it opportunistically. It is a cache, never a
/// source of truth for a teacher's own records.
class SyncedCatalogStore {
  SyncedCatalogStore(this._storage);

  static const String _lessonsKey = 'sync.catalog.lessons';

  final SecureStorageService _storage;

  Future<List<Lesson>> lessons() async {
    final String? raw = await _storage.read(_lessonsKey);
    if (raw == null || raw.isEmpty) return const <Lesson>[];
    try {
      return <Lesson>[
        for (final dynamic e in jsonDecode(raw) as List<dynamic>)
          Lesson.fromJson(e as Map<String, dynamic>),
      ];
    } on FormatException {
      return const <Lesson>[];
    } on TypeError {
      return const <Lesson>[];
    }
  }

  Future<void> saveLessons(List<Lesson> lessons) async {
    await _storage.write(
      _lessonsKey,
      jsonEncode(<Object>[for (final Lesson lesson in lessons) lesson.toJson()]),
    );
  }
}