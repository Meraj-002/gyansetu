// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:convert';

import '../../../core/utils/app_logger.dart';
import '../../../models/progress_event.dart';
import '../../../services/storage/secure_storage_service.dart';
import '../models/learning_insights.dart';

/// The log of what a teacher did, and when.
///
/// Deliberately small. It does not store lesson state, assessment results or
/// classroom sessions — those already have their own stores, and analytics
/// reads them directly. What lives here is the timestamp trail that lets a
/// figure be attributed to a week.
abstract interface class LearningProgressRepository {
  /// Records [event]. Recording the same event twice is a no-op.
  Future<void> record(ProgressEvent event);

  Future<List<ProgressEvent>> all();

  Future<List<ProgressEvent>> inRange(DateRange range);

  Future<List<ProgressEvent>> ofType(ProgressEventType type);

  /// Clears the log. Used by "reset progress", never in normal use.
  Future<void> clear();
}

/// The log in the app's existing secure store.
///
/// Capped at [maxEvents], oldest dropped first. A Class 1 teacher generates a
/// few events a day; the cap exists so a phone in use for two years cannot
/// grow a key-value entry without bound.
class LocalLearningProgressRepository implements LearningProgressRepository {
  LocalLearningProgressRepository(this._storage);

  static const String _key = 'progress.events';

  /// Roughly two school years of ordinary use.
  static const int maxEvents = 2000;

  final SecureStorageService _storage;

  List<ProgressEvent>? _cache;

  Future<List<ProgressEvent>> _load() async {
    final List<ProgressEvent>? held = _cache;
    if (held != null) return held;

    final String? raw = await _storage.read(_key);
    if (raw == null || raw.isEmpty) return _cache = <ProgressEvent>[];
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      return _cache = <ProgressEvent>[
        for (final dynamic e in decoded)
          ProgressEvent.fromJson(e as Map<String, dynamic>),
      ];
    } on Object catch (error) {
      AppLogger.error('progress events could not be read', error: error);
      return _cache = <ProgressEvent>[];
    }
  }

  @override
  Future<void> record(ProgressEvent event) async {
    final List<ProgressEvent> events = List<ProgressEvent>.from(await _load());
    // The same milestone reached twice in one second is one event, not two.
    if (events.any((ProgressEvent e) => e.id == event.id)) return;

    events.add(event);
    events.sort(
      (ProgressEvent a, ProgressEvent b) =>
          a.occurredAt.compareTo(b.occurredAt),
    );
    if (events.length > maxEvents) {
      events.removeRange(0, events.length - maxEvents);
    }

    _cache = events;
    await _storage.write(
      _key,
      jsonEncode(<Map<String, dynamic>>[
        for (final ProgressEvent e in events) e.toJson(),
      ]),
    );
  }

  @override
  Future<List<ProgressEvent>> all() async =>
      List<ProgressEvent>.unmodifiable(await _load());

  @override
  Future<List<ProgressEvent>> inRange(DateRange range) async => <ProgressEvent>[
        for (final ProgressEvent e in await _load())
          if (range.contains(e.occurredAt)) e,
      ];

  @override
  Future<List<ProgressEvent>> ofType(ProgressEventType type) async =>
      <ProgressEvent>[
        for (final ProgressEvent e in await _load())
          if (e.type == type) e,
      ];

  @override
  Future<void> clear() async {
    _cache = <ProgressEvent>[];
    await _storage.delete(_key);
  }
}

/// The log in memory, for tests.
class InMemoryLearningProgressRepository implements LearningProgressRepository {
  InMemoryLearningProgressRepository([List<ProgressEvent>? seed])
      : _events = <ProgressEvent>[...?seed];

  final List<ProgressEvent> _events;

  @override
  Future<void> record(ProgressEvent event) async {
    if (_events.any((ProgressEvent e) => e.id == event.id)) return;
    _events
      ..add(event)
      ..sort(
        (ProgressEvent a, ProgressEvent b) =>
            a.occurredAt.compareTo(b.occurredAt),
      );
  }

  @override
  Future<List<ProgressEvent>> all() async =>
      List<ProgressEvent>.unmodifiable(_events);

  @override
  Future<List<ProgressEvent>> inRange(DateRange range) async => <ProgressEvent>[
        for (final ProgressEvent e in _events)
          if (range.contains(e.occurredAt)) e,
      ];

  @override
  Future<List<ProgressEvent>> ofType(ProgressEventType type) async =>
      <ProgressEvent>[
        for (final ProgressEvent e in _events)
          if (e.type == type) e,
      ];

  @override
  Future<void> clear() async => _events.clear();
}

/// A log that fails, so the error state can be exercised.
class FailingLearningProgressRepository implements LearningProgressRepository {
  const FailingLearningProgressRepository();

  Never _fail() => throw StateError('progress log unavailable');

  @override
  Future<void> record(ProgressEvent event) async => _fail();

  @override
  Future<List<ProgressEvent>> all() async => _fail();

  @override
  Future<List<ProgressEvent>> inRange(DateRange range) async => _fail();

  @override
  Future<List<ProgressEvent>> ofType(ProgressEventType type) async => _fail();

  @override
  Future<void> clear() async => _fail();
}

/// The one place a feature records that something happened.
///
/// Screens and controllers hold this rather than the repository, so recording
/// is always fire-and-forget and a storage failure can never take a lesson or
/// an assessment down with it.
class ProgressRecorder {
  const ProgressRecorder(this._log, {DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  /// A recorder that keeps nothing. The default wherever a caller has not been
  /// given a log — a test, for instance — so the calling code needs no null
  /// checks.
  const ProgressRecorder.none()
      : _log = null,
        _now = DateTime.now;

  final LearningProgressRepository? _log;
  final DateTime Function() _now;

  Future<void> record(
    ProgressEventType type, {
    String? lessonId,
    Map<String, String> metadata = const <String, String>{},
    DateTime? at,
  }) async {
    final LearningProgressRepository? log = _log;
    if (log == null) return;
    try {
      await log.record(
        ProgressEvent.of(
          type: type,
          occurredAt: at ?? _now(),
          lessonId: lessonId,
          metadata: metadata,
        ),
      );
    } on Object catch (error) {
      // Losing an analytics event must never break the thing being measured.
      AppLogger.error('progress event was not recorded', error: error);
    }
  }
}
