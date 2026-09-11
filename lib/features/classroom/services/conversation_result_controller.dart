// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/utils/app_logger.dart';
import '../../../models/lesson.dart';
import '../../../models/lesson_plan.dart';
import '../../../models/progress_event.dart';
import '../../../services/audio/lesson_audio_service.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../lessons/services/assessment_repository.dart';
import '../../lessons/services/lesson_content_repository.dart';
import '../../lessons/services/lesson_detail_controller.dart'
    show LessonMilestone;
import '../../lessons/services/lesson_repository.dart';
import '../../progress/services/learning_progress_repository.dart';
import '../../setup/models/classroom_setup.dart';
import '../models/classroom_insights.dart';
import '../models/classroom_session.dart';
import '../models/conversation_turn.dart';
import 'classroom_insight_service.dart';
import 'classroom_session_repository.dart';

/// Where the result screen is in its own small lifecycle.
enum ResultLoadState { loading, loaded, error }

/// What has happened to the teacher's explicit save.
enum SaveState { notSaved, saving, saved, failed }

/// One line of the rendered conversation.
///
/// A recorded [ConversationTurn] holds both what was said and what it became,
/// which the reference screen shows as two lines: the speaker's, then the AI's.
/// This class is that expansion, done once when the session loads rather than
/// on every rebuild.
class ResultTimelineEntry {
  const ResultTimelineEntry({
    required this.turnId,
    required this.speaker,
    required this.title,
    required this.text,
    required this.timestamp,
    this.secondaryText,
    this.confidence,
    this.playable = false,
    this.failed = false,
  });

  final String turnId;
  final TurnSpeaker speaker;

  /// 'Teacher — Hindi', 'GyanSetu AI — Santali Translation'.
  final String title;

  final String text;

  /// The pronounceable spelling under a translation, where one exists.
  final String? secondaryText;

  /// Null hides the badge. An absent confidence is not a high one.
  final double? confidence;

  final DateTime timestamp;

  /// True when this line has words the audio layer can voice.
  final bool playable;

  final bool failed;
}

/// Drives the conversation result screen.
///
/// It loads one session by id through the repository — it never receives a
/// copy of the session, so the screen and the live classroom cannot drift
/// apart — and computes nothing that the session did not record.
class ConversationResultController extends ChangeNotifier {
  ConversationResultController({
    required String sessionId,
    required ClassroomSessionRepository sessions,
    required ClassroomInsightService insights,
    required LessonRepository lessons,
    required LessonContentRepository content,
    required LessonProgressRepository progress,
    required AssessmentRepository assessments,
    required LessonAudioService audio,
    required ConnectivityService connectivity,
    ProgressRecorder recorder = const ProgressRecorder.none(),
  })  : _sessionId = sessionId,
        _sessions = sessions,
        _insightService = insights,
        _lessons = lessons,
        _content = content,
        _progress = progress,
        _assessments = assessments,
        _audio = audio,
        _connectivity = connectivity,
        _recorder = recorder {
    unawaited(load());
  }

  final String _sessionId;
  final ClassroomSessionRepository _sessions;

  /// Writes "a session was saved, at this time" for Learning Insights.
  final ProgressRecorder _recorder;
  final ClassroomInsightService _insightService;
  final LessonRepository _lessons;
  final LessonContentRepository _content;
  final LessonProgressRepository _progress;
  final AssessmentRepository _assessments;
  final LessonAudioService _audio;
  final ConnectivityService _connectivity;

  ResultLoadState _loadState = ResultLoadState.loading;
  ResultLoadState get loadState => _loadState;

  ClassroomSession? _session;
  ClassroomSession? get session => _session;

  Lesson? _lesson;
  Lesson? get lesson => _lesson;

  LessonPlan? _plan;

  AssessmentResult? _assessment;
  AssessmentResult? get assessmentResult => _assessment;

  ClassroomInsights? _insights;
  ClassroomInsights? get insights => _insights;

  List<ResultTimelineEntry> _timeline = const <ResultTimelineEntry>[];

  /// The conversation, expanded once at load.
  List<ResultTimelineEntry> get timeline => _timeline;

  SaveState _saveState = SaveState.notSaved;
  SaveState get saveState => _saveState;

  String? _message;

  /// A short note for the teacher. Never an exception.
  String? get message => _message;

  void dismissMessage() {
    if (_message == null) return;
    _message = null;
    notifyListeners();
  }

  bool get isOffline => _connectivity.status == ConnectionStatus.offline;

  /// The quick assessment this lesson carries, for the Start Assessment button.
  QuickAssessment? get assessment => _plan?.assessment;

  // --- Loading -------------------------------------------------------------

  Future<void> load() async {
    _loadState = ResultLoadState.loading;
    notifyListeners();

    try {
      final ClassroomSession? session = await _sessions.byId(_sessionId);
      if (session == null) {
        _loadState = ResultLoadState.error;
        notifyListeners();
        return;
      }
      _session = session;
      _saveState =
          session.isSaved ? SaveState.saved : SaveState.notSaved;

      _lesson = await _lessons.lessonById(session.lessonId);
      _plan = await _content.cachedPlan(session.lessonId);
      _assessment = await _assessments.latestFor(session.lessonId);

      _timeline = _expand(session);

      // Computed once here and cached, not recomputed as the screen scrolls.
      _insights = await _insightService.generateInsights(
        session: session,
        lesson: _lesson,
        assessment: _plan?.assessment,
        result: _assessment,
      );

      await _recordLessonProgress(session);

      _loadState = ResultLoadState.loaded;
    } on Object catch (error) {
      AppLogger.error('classroom session could not be loaded', error: error);
      _loadState = ResultLoadState.error;
    }
    notifyListeners();
  }

  /// A session where the class really did work through the lesson moves the
  /// lesson's progress along — but only to the level a live session earns, and
  /// only ever upwards.
  Future<void> _recordLessonProgress(ClassroomSession session) async {
    if (session.interactionsCompleted == 0) return;
    try {
      final int current = await _progress.percentFor(session.lessonId);
      if (current >= LessonMilestone.taughtLive.percent) return;
      await _progress.setPercent(
        session.lessonId,
        LessonMilestone.taughtLive.percent,
      );
    } on Object catch (error) {
      AppLogger.error('lesson progress could not be updated', error: error);
    }
  }

  /// Turns each recorded turn into the speaker's line plus the AI's line.
  List<ResultTimelineEntry> _expand(ClassroomSession session) {
    final List<ResultTimelineEntry> entries = <ResultTimelineEntry>[];

    for (final ConversationTurn turn in session.turns) {
      final bool teacherSide = turn.speaker == TurnSpeaker.teacher;
      final String sourceLabel = _languageName(turn.sourceLanguage);
      final String targetLabel = _languageName(turn.targetLanguage);

      if (turn.sourceText.trim().isNotEmpty) {
        entries.add(
          ResultTimelineEntry(
            turnId: turn.id,
            speaker: turn.speaker,
            title: '${teacherSide ? 'Teacher' : 'Student'} — $sourceLabel',
            text: turn.sourceText,
            timestamp: turn.timestamp,
            // The recogniser's own confidence, where it reported one.
            confidence: turn.confidence,
            playable: false,
            failed: turn.status == TurnStatus.failed,
          ),
        );
      }

      final String? translated = turn.translatedText;
      if (translated != null && translated.trim().isNotEmpty) {
        final String line = teacherSide ? 'Translation' : 'Meaning';
        // The provenance labels the honest source of the answer rather than
        // claiming AI for a phrasebook or a cached sentence. Blank falls back
        // to the product name without over-claiming a model.
        final String? provenance = turn.source?.label;
        final String title = provenance == null
            ? 'GyanSetu — $targetLabel $line'
            : 'GyanSetu $provenance — $targetLabel $line';
        entries.add(
          ResultTimelineEntry(
            turnId: turn.id,
            speaker: TurnSpeaker.ai,
            title: title,
            text: translated,
            secondaryText: turn.translatedSpokenText,
            // Translation confidence sits on the AI line, where it belongs.
            confidence: turn.confidence,
            // The audio layer voices the translation, so only this line plays.
            playable: true,
            timestamp: turn.metrics?.timestamp ?? turn.timestamp,
          ),
        );
      }

      if (turn.status == TurnStatus.failed && turn.sourceText.trim().isEmpty) {
        entries.add(
          ResultTimelineEntry(
            turnId: turn.id,
            speaker: turn.speaker,
            title: '${teacherSide ? 'Teacher' : 'Student'} — $sourceLabel',
            text: turn.failureMessage ?? 'This turn did not complete.',
            timestamp: turn.timestamp,
            failed: true,
          ),
        );
      }
    }
    return entries;
  }

  /// Locale id back to a name the teacher recognises.
  static String _languageName(String localeId) {
    for (final TargetLanguage v in TargetLanguage.values) {
      if (v.localeId == localeId) return v.label;
    }
    for (final TeachingMedium v in TeachingMedium.values) {
      if (v.localeId == localeId) return v.label;
    }
    return localeId;
  }

  // --- Audio ---------------------------------------------------------------

  /// Plays one line back. The words come from the recorded turn, so a session
  /// reopened days later still plays what was actually said.
  Future<void> playEntry(ResultTimelineEntry entry) async {
    final ClassroomSession? session = _session;
    if (session == null) return;

    ConversationTurn? turn;
    for (final ConversationTurn t in session.turns) {
      if (t.id == entry.turnId) turn = t;
    }
    if (turn == null || (turn.translatedText ?? '').isEmpty) {
      _message = 'Audio is unavailable.';
      notifyListeners();
      return;
    }

    final SpokenPassage passage = SpokenPassage(
      lessonId: session.lessonId,
      label: _languageName(turn.targetLanguage),
      displayText: turn.translatedText!,
      localeId: turn.targetLanguage,
      spokenText: turn.translatedSpokenText,
      spokenScriptLocaleId: turn.translatedSpokenText == null
          ? null
          : session.teachingLanguage,
      textHash: _hash(turn.translatedText!),
    );

    final AudioRequestOutcome outcome = await _audio.play(passage);
    switch (outcome) {
      case AudioStarted():
        _message = null;
      case AudioBlocked(:final String message):
        _message = message;
      case AudioFailed():
        _message = 'Audio is unavailable.';
    }
    notifyListeners();
  }

  Future<void> stopAudio() => _audio.stop();

  // --- Saving --------------------------------------------------------------

  /// Writes the session, its turns, its metrics and its insights to the device.
  ///
  /// Idempotent: a session already saved is reported as saved and written no
  /// second time. Needs no connection — a classroom session that could only be
  /// kept with a signal would be useless in the places this app is for.
  Future<void> saveSession() async {
    final ClassroomSession? session = _session;
    if (session == null) return;
    if (_saveState == SaveState.saving) return;
    if (_saveState == SaveState.saved) {
      _message = 'This session is already saved on this device.';
      notifyListeners();
      return;
    }

    _saveState = SaveState.saving;
    _message = null;
    notifyListeners();

    try {
      final ClassroomSession saved = session.copyWith(
        savedAt: DateTime.now(),
        // Local only until a sync service exists to move it. Claiming
        // "pending sync" would promise a transfer nothing is going to make.
        syncStatus: SessionSyncStatus.localOnly,
      );
      await _sessions.save(saved);
      _session = saved;
      _saveState = SaveState.saved;
      _message = 'Session saved on this device.';
      await _recorder.record(
        ProgressEventType.classroomSessionCompleted,
        lessonId: saved.lessonId,
        at: saved.savedAt,
        metadata: <String, String>{
          'sessionId': saved.sessionId,
          'interactions': '${saved.interactionsCompleted}',
          'studentTurns': '${saved.studentTurns}',
        },
      );
    } on Object catch (error) {
      AppLogger.error('session could not be saved', error: error);
      _saveState = SaveState.failed;
      _message = "Couldn't save the session. Your local data is still "
          'available.';
    }
    notifyListeners();
  }

  /// Records an assessment run from this screen, and refreshes the insights it
  /// feeds.
  Future<void> recordAssessment(AssessmentResult result) async {
    final ClassroomSession? session = _session;
    if (session == null) return;

    _assessment = result;
    await _assessments.record(result);

    final int current = await _progress.percentFor(session.lessonId);
    if (current < LessonMilestone.assessed.percent) {
      await _progress.setPercent(
        session.lessonId,
        LessonMilestone.assessed.percent,
      );
    }

    _insights = await _insightService.generateInsights(
      session: session,
      lesson: _lesson,
      assessment: _plan?.assessment,
      result: result,
    );
    _message = 'Assessment saved for ${result.achievedCount} of '
        '${result.total}.';
    notifyListeners();
  }

  static String _hash(String value) {
    int hash = 0x811c9dc5;
    for (final int unit in value.trim().toLowerCase().codeUnits) {
      hash = (hash ^ unit) * 0x01000193 & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
