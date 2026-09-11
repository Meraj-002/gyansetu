// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:convert';

import '../../../core/utils/app_logger.dart';
import '../../../models/lesson_plan.dart';
import '../../../services/storage/secure_storage_service.dart';

/// Where completed quick assessments are kept.
///
/// Results are recorded on the device and never require a connection: a teacher
/// checking three children at the back of a classroom has no signal, and losing
/// what they recorded would be worse than not offering the feature.
abstract interface class AssessmentRepository {
  /// The most recent result for a lesson, or null if it has never been run.
  Future<AssessmentResult?> latestFor(String lessonId);

  Future<void> record(AssessmentResult result);

  Future<List<AssessmentResult>> all();
}

/// Results in the app's existing secure store, newest per lesson.
///
/// Only the latest result per lesson is kept. A per-child history belongs in
/// the lessons database alongside pupil records, which does not exist yet;
/// keeping a growing list in a key-value store would quietly become the wrong
/// shape.
class LocalAssessmentRepository implements AssessmentRepository {
  LocalAssessmentRepository(this._storage);

  static const String _key = 'lessons.assessments';

  final SecureStorageService _storage;

  Map<String, AssessmentResult>? _cache;

  Future<Map<String, AssessmentResult>> _load() async {
    final Map<String, AssessmentResult>? held = _cache;
    if (held != null) return held;

    final String? raw = await _storage.read(_key);
    if (raw == null || raw.isEmpty) return _cache = <String, AssessmentResult>{};
    try {
      final Map<String, dynamic> decoded =
          jsonDecode(raw) as Map<String, dynamic>;
      return _cache = <String, AssessmentResult>{
        for (final MapEntry<String, dynamic> e in decoded.entries)
          e.key: AssessmentResult.fromJson(e.value as Map<String, dynamic>),
      };
    } on Object catch (error) {
      AppLogger.error('assessment results could not be read', error: error);
      return _cache = <String, AssessmentResult>{};
    }
  }

  @override
  Future<AssessmentResult?> latestFor(String lessonId) async =>
      (await _load())[lessonId];

  @override
  Future<void> record(AssessmentResult result) async {
    final Map<String, AssessmentResult> values =
        Map<String, AssessmentResult>.from(await _load());
    values[result.lessonId] = result;
    _cache = values;
    await _storage.write(
      _key,
      jsonEncode(<String, dynamic>{
        for (final MapEntry<String, AssessmentResult> e in values.entries)
          e.key: e.value.toJson(),
      }),
    );
  }

  @override
  Future<List<AssessmentResult>> all() async =>
      (await _load()).values.toList(growable: false);
}

/// In-memory results, for tests.
class InMemoryAssessmentRepository implements AssessmentRepository {
  final Map<String, AssessmentResult> _values = <String, AssessmentResult>{};

  @override
  Future<AssessmentResult?> latestFor(String lessonId) async =>
      _values[lessonId];

  @override
  Future<void> record(AssessmentResult result) async =>
      _values[result.lessonId] = result;

  @override
  Future<List<AssessmentResult>> all() async => _values.values.toList();
}
