// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:convert';

import '../../../core/utils/app_logger.dart';
import '../../../data/assessment_questions.dart';
import '../../../models/assessment_answer.dart';
import '../../../models/assessment_question.dart';
import '../../../models/assessment_result.dart';
import '../../../services/storage/secure_storage_service.dart';

/// Where quiz questions come from.
///
/// An interface so the bundled set can be replaced by a catalogue the backend
/// serves, without the screen or the controller noticing.
abstract interface class QuizQuestionSource {
  Future<List<QuizQuestion>> forLesson(String lessonId);
}

/// The questions bundled with the app.
class LocalQuizQuestionSource implements QuizQuestionSource {
  const LocalQuizQuestionSource([this._questions]);

  /// Supplied by tests. Null means the bundled dataset.
  final List<QuizQuestion>? _questions;

  @override
  Future<List<QuizQuestion>> forLesson(String lessonId) async =>
      List<QuizQuestion>.unmodifiable(
        _questions ?? AssessmentQuestionData.forLesson(lessonId),
      );
}

/// A source that fails, so the error state can be exercised.
class FailingQuizQuestionSource implements QuizQuestionSource {
  const FailingQuizQuestionSource();

  @override
  Future<List<QuizQuestion>> forLesson(String lessonId) async =>
      throw StateError('quiz questions unavailable');
}

/// Questions, answers in progress, and finished results.
///
/// Answers are saved as they are given rather than only at the end. A phone
/// that runs out of battery halfway through a Class 1 assessment should not
/// cost the child the six questions they already did.
abstract interface class QuizRepository {
  Future<List<QuizQuestion>> questionsFor(String lessonId);

  /// Answers already given for an assessment that was not finished.
  Future<Map<String, QuizAnswer>> answersFor(String lessonId);

  Future<void> saveAnswer(String lessonId, QuizAnswer answer);

  /// Clears answers in progress. Called once a result has been recorded, and
  /// when a teacher restarts the assessment.
  Future<void> clearAnswers(String lessonId);

  Future<void> saveResult(QuizResult result);

  Future<QuizResult?> latestResult(String lessonId);

  Future<List<QuizResult>> allResults();
}

/// Questions from a source, everything else in the app's secure store.
class LocalQuizRepository implements QuizRepository {
  LocalQuizRepository({
    required SecureStorageService storage,
    QuizQuestionSource? source,
  })  : _storage = storage,
        _source = source ?? const LocalQuizQuestionSource();

  static const String _answersKey = 'assessment.answers';
  static const String _resultsKey = 'assessment.results';

  final SecureStorageService _storage;
  final QuizQuestionSource _source;

  final Map<String, List<QuizQuestion>> _questions =
      <String, List<QuizQuestion>>{};

  Map<String, Map<String, QuizAnswer>>? _answers;
  Map<String, QuizResult>? _results;

  @override
  Future<List<QuizQuestion>> questionsFor(String lessonId) async {
    final List<QuizQuestion>? held = _questions[lessonId];
    if (held != null) return held;
    return _questions[lessonId] = await _source.forLesson(lessonId);
  }

  // --- Answers in progress -------------------------------------------------

  Future<Map<String, Map<String, QuizAnswer>>> _loadAnswers() async {
    final Map<String, Map<String, QuizAnswer>>? held = _answers;
    if (held != null) return held;

    final String? raw = await _storage.read(_answersKey);
    if (raw == null || raw.isEmpty) {
      return _answers = <String, Map<String, QuizAnswer>>{};
    }
    try {
      final Map<String, dynamic> decoded =
          jsonDecode(raw) as Map<String, dynamic>;
      return _answers = <String, Map<String, QuizAnswer>>{
        for (final MapEntry<String, dynamic> lesson in decoded.entries)
          lesson.key: <String, QuizAnswer>{
            for (final MapEntry<String, dynamic> a
                in (lesson.value as Map<String, dynamic>).entries)
              a.key: QuizAnswer.fromJson(a.value as Map<String, dynamic>),
          },
      };
    } on Object catch (error) {
      AppLogger.error('assessment answers could not be read', error: error);
      return _answers = <String, Map<String, QuizAnswer>>{};
    }
  }

  Future<void> _writeAnswers(
    Map<String, Map<String, QuizAnswer>> values,
  ) async {
    _answers = values;
    await _storage.write(
      _answersKey,
      jsonEncode(<String, dynamic>{
        for (final MapEntry<String, Map<String, QuizAnswer>> lesson
            in values.entries)
          lesson.key: <String, dynamic>{
            for (final MapEntry<String, QuizAnswer> a in lesson.value.entries)
              a.key: a.value.toJson(),
          },
      }),
    );
  }

  @override
  Future<Map<String, QuizAnswer>> answersFor(String lessonId) async =>
      Map<String, QuizAnswer>.from(
        (await _loadAnswers())[lessonId] ?? const <String, QuizAnswer>{},
      );

  @override
  Future<void> saveAnswer(String lessonId, QuizAnswer answer) async {
    final Map<String, Map<String, QuizAnswer>> all =
        Map<String, Map<String, QuizAnswer>>.from(await _loadAnswers());
    final Map<String, QuizAnswer> forLesson = Map<String, QuizAnswer>.from(
      all[lessonId] ?? const <String, QuizAnswer>{},
    );
    // Changing a mind replaces the answer; it does not add a second one.
    forLesson[answer.questionId] = answer;
    all[lessonId] = forLesson;
    await _writeAnswers(all);
  }

  @override
  Future<void> clearAnswers(String lessonId) async {
    final Map<String, Map<String, QuizAnswer>> all =
        Map<String, Map<String, QuizAnswer>>.from(await _loadAnswers());
    if (all.remove(lessonId) == null) return;
    await _writeAnswers(all);
  }

  // --- Finished results ----------------------------------------------------

  Future<Map<String, QuizResult>> _loadResults() async {
    final Map<String, QuizResult>? held = _results;
    if (held != null) return held;

    final String? raw = await _storage.read(_resultsKey);
    if (raw == null || raw.isEmpty) return _results = <String, QuizResult>{};
    try {
      final Map<String, dynamic> decoded =
          jsonDecode(raw) as Map<String, dynamic>;
      return _results = <String, QuizResult>{
        for (final MapEntry<String, dynamic> e in decoded.entries)
          e.key: QuizResult.fromJson(e.value as Map<String, dynamic>),
      };
    } on Object catch (error) {
      AppLogger.error('assessment results could not be read', error: error);
      return _results = <String, QuizResult>{};
    }
  }

  @override
  Future<void> saveResult(QuizResult result) async {
    final Map<String, QuizResult> values =
        Map<String, QuizResult>.from(await _loadResults());
    // Only the latest run per lesson is kept: a per-child history belongs in
    // the pupil records table, which does not exist yet, and a growing list in
    // a key-value store would quietly become the wrong shape.
    values[result.lessonId] = result;
    _results = values;
    await _storage.write(
      _resultsKey,
      jsonEncode(<String, dynamic>{
        for (final MapEntry<String, QuizResult> e in values.entries)
          e.key: e.value.toJson(),
      }),
    );
  }

  @override
  Future<QuizResult?> latestResult(String lessonId) async =>
      (await _loadResults())[lessonId];

  @override
  Future<List<QuizResult>> allResults() async =>
      (await _loadResults()).values.toList(growable: false);
}

/// Everything in memory, for tests.
class InMemoryQuizRepository implements QuizRepository {
  InMemoryQuizRepository({List<QuizQuestion>? questions})
      : _source = LocalQuizQuestionSource(questions);

  final QuizQuestionSource _source;
  final Map<String, Map<String, QuizAnswer>> _answers =
      <String, Map<String, QuizAnswer>>{};
  final Map<String, QuizResult> _results = <String, QuizResult>{};

  @override
  Future<List<QuizQuestion>> questionsFor(String lessonId) =>
      _source.forLesson(lessonId);

  @override
  Future<Map<String, QuizAnswer>> answersFor(String lessonId) async =>
      Map<String, QuizAnswer>.from(
        _answers[lessonId] ?? const <String, QuizAnswer>{},
      );

  @override
  Future<void> saveAnswer(String lessonId, QuizAnswer answer) async {
    (_answers[lessonId] ??= <String, QuizAnswer>{})[answer.questionId] = answer;
  }

  @override
  Future<void> clearAnswers(String lessonId) async => _answers.remove(lessonId);

  @override
  Future<void> saveResult(QuizResult result) async =>
      _results[result.lessonId] = result;

  @override
  Future<QuizResult?> latestResult(String lessonId) async => _results[lessonId];

  @override
  Future<List<QuizResult>> allResults() async => _results.values.toList();
}
