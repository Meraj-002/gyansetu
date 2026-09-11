// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:convert';

import '../../../core/utils/app_logger.dart';
import '../../../data/flashcard_data.dart';
import '../../../models/flashcard.dart';
import '../../../services/storage/secure_storage_service.dart';

/// Where flashcards come from.
///
/// An interface so the bundled set can be replaced by a server catalogue, or by
/// cards a model writes for one lesson, without the screen noticing.
abstract interface class FlashcardDataSource {
  Future<List<Flashcard>> load();
}

/// The set bundled with the app.
///
/// DEVELOPMENT DATA behind an interface. It needs no connection, which is the
/// point: a teacher opens the flashcards in a classroom with no signal.
class LocalFlashcardDataSource implements FlashcardDataSource {
  const LocalFlashcardDataSource([this._cards]);

  final List<Flashcard>? _cards;

  @override
  Future<List<Flashcard>> load() async =>
      List<Flashcard>.unmodifiable(_cards ?? FlashcardData.all());
}

/// A source that fails, so the error state can be exercised.
class FailingFlashcardDataSource implements FlashcardDataSource {
  const FailingFlashcardDataSource();

  @override
  Future<List<Flashcard>> load() async =>
      throw StateError('flashcards unavailable');
}

/// Flashcards, and the small amount of state that belongs to this device.
abstract interface class FlashcardRepository {
  Future<List<Flashcard>> all();

  Future<List<Flashcard>> byCategory(FlashcardCategory category);

  Future<Flashcard?> byId(String id);

  Future<Set<String>> bookmarkedIds();

  Future<List<Flashcard>> bookmarked();

  /// Returns the new state, so a caller does not have to guess.
  Future<bool> toggleBookmark(String id);

  /// Adds a card to a lesson. Doing it twice is not an error and does not
  /// duplicate the record.
  Future<ClassroomFlashcard> addToClassroom({
    required String flashcardId,
    required String lessonId,
    required int classNumber,
  });

  Future<List<ClassroomFlashcard>> classroomCards({String? lessonId});

  Future<bool> isInClassroom(String flashcardId, String lessonId);

  /// Where the teacher had got to in a category, so reopening lands there.
  Future<int> lastIndexFor(FlashcardCategory category);

  Future<void> setLastIndex(FlashcardCategory category, int index);

  /// Clears bookmarks and remembered positions. Leaves lesson and classroom
  /// data alone.
  Future<void> resetProgress();
}

/// Cards from a data source, per-device state in the app's secure store.
class LocalFlashcardRepository implements FlashcardRepository {
  LocalFlashcardRepository({
    required SecureStorageService storage,
    FlashcardDataSource? source,
  })  : _storage = storage,
        _source = source ?? const LocalFlashcardDataSource();

  static const String _bookmarksKey = 'flashcards.bookmarks';
  static const String _classroomKey = 'flashcards.classroom';
  static const String _progressKey = 'flashcards.progress';

  final SecureStorageService _storage;
  final FlashcardDataSource _source;

  List<Flashcard>? _cards;
  Set<String>? _bookmarks;
  Map<String, ClassroomFlashcard>? _classroom;
  Map<String, int>? _progress;

  @override
  Future<List<Flashcard>> all() async {
    final List<Flashcard>? held = _cards;
    if (held != null) return held;
    final List<Flashcard> loaded = await _source.load();
    return _cards = (loaded.toList()
      ..sort((Flashcard a, Flashcard b) {
        final int byCategory = a.category.index.compareTo(b.category.index);
        return byCategory != 0 ? byCategory : a.order.compareTo(b.order);
      }));
  }

  @override
  Future<List<Flashcard>> byCategory(FlashcardCategory category) async =>
      (await all())
          .where((Flashcard c) => c.category == category)
          .toList(growable: false);

  @override
  Future<Flashcard?> byId(String id) async {
    for (final Flashcard card in await all()) {
      if (card.id == id) return card;
    }
    return null;
  }

  // --- Bookmarks -----------------------------------------------------------

  @override
  Future<Set<String>> bookmarkedIds() async {
    final Set<String>? held = _bookmarks;
    if (held != null) return held;

    final String? raw = await _storage.read(_bookmarksKey);
    if (raw == null || raw.isEmpty) return _bookmarks = <String>{};
    return _bookmarks =
        raw.split(';').where((String s) => s.isNotEmpty).toSet();
  }

  @override
  Future<List<Flashcard>> bookmarked() async {
    final Set<String> ids = await bookmarkedIds();
    return (await all())
        .where((Flashcard c) => ids.contains(c.id))
        .toList(growable: false);
  }

  @override
  Future<bool> toggleBookmark(String id) async {
    final Set<String> ids = Set<String>.from(await bookmarkedIds());
    final bool nowBookmarked = !ids.contains(id);
    if (nowBookmarked) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    _bookmarks = ids;
    await _storage.write(_bookmarksKey, ids.join(';'));
    return nowBookmarked;
  }

  // --- Classroom -----------------------------------------------------------

  Future<Map<String, ClassroomFlashcard>> _classroomRecords() async {
    final Map<String, ClassroomFlashcard>? held = _classroom;
    if (held != null) return held;

    final String? raw = await _storage.read(_classroomKey);
    if (raw == null || raw.isEmpty) {
      return _classroom = <String, ClassroomFlashcard>{};
    }
    try {
      final Map<String, dynamic> decoded =
          jsonDecode(raw) as Map<String, dynamic>;
      return _classroom = <String, ClassroomFlashcard>{
        for (final MapEntry<String, dynamic> e in decoded.entries)
          e.key: ClassroomFlashcard.fromJson(e.value as Map<String, dynamic>),
      };
    } on Object catch (error) {
      AppLogger.error('classroom flashcards could not be read', error: error);
      return _classroom = <String, ClassroomFlashcard>{};
    }
  }

  @override
  Future<ClassroomFlashcard> addToClassroom({
    required String flashcardId,
    required String lessonId,
    required int classNumber,
  }) async {
    final Map<String, ClassroomFlashcard> records =
        Map<String, ClassroomFlashcard>.from(await _classroomRecords());

    final String key = '$lessonId#$flashcardId';
    // Adding the same card twice is a no-op, not a second record.
    final ClassroomFlashcard record = records[key] ??
        ClassroomFlashcard(
          flashcardId: flashcardId,
          lessonId: lessonId,
          classNumber: classNumber,
          addedAt: DateTime.now(),
        );
    records[key] = record;
    _classroom = records;

    await _storage.write(
      _classroomKey,
      jsonEncode(<String, dynamic>{
        for (final MapEntry<String, ClassroomFlashcard> e in records.entries)
          e.key: e.value.toJson(),
      }),
    );
    return record;
  }

  @override
  Future<List<ClassroomFlashcard>> classroomCards({String? lessonId}) async {
    final Iterable<ClassroomFlashcard> records =
        (await _classroomRecords()).values;
    if (lessonId == null) return records.toList(growable: false);
    return records
        .where((ClassroomFlashcard r) => r.lessonId == lessonId)
        .toList(growable: false);
  }

  @override
  Future<bool> isInClassroom(String flashcardId, String lessonId) async =>
      (await _classroomRecords()).containsKey('$lessonId#$flashcardId');

  // --- Where the teacher had got to ----------------------------------------

  Future<Map<String, int>> _progressRecords() async {
    final Map<String, int>? held = _progress;
    if (held != null) return held;

    final String? raw = await _storage.read(_progressKey);
    if (raw == null || raw.isEmpty) return _progress = <String, int>{};
    return _progress = <String, int>{
      for (final String pair in raw.split(';'))
        if (pair.contains('='))
          pair.split('=').first: int.tryParse(pair.split('=').last) ?? 0,
    };
  }

  @override
  Future<int> lastIndexFor(FlashcardCategory category) async =>
      (await _progressRecords())[category.name] ?? 0;

  @override
  Future<void> setLastIndex(FlashcardCategory category, int index) async {
    final Map<String, int> records = Map<String, int>.from(
      await _progressRecords(),
    );
    records[category.name] = index < 0 ? 0 : index;
    _progress = records;
    await _storage.write(
      _progressKey,
      records.entries
          .map((MapEntry<String, int> e) => '${e.key}=${e.value}')
          .join(';'),
    );
  }

  @override
  Future<void> resetProgress() async {
    _bookmarks = <String>{};
    _progress = <String, int>{};
    await _storage.delete(_bookmarksKey);
    await _storage.delete(_progressKey);
    // Classroom records are the teacher's lesson plan, not progress, and are
    // deliberately left alone.
  }
}
