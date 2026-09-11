// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/utils/app_logger.dart';
import '../../../models/assessment_answer.dart';
import '../../../models/assessment_question.dart';
import '../../../models/assessment_result.dart';
import '../../../models/lesson.dart';
import '../../../models/progress_event.dart';
import '../../../services/audio/lesson_audio_service.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../lessons/services/lesson_repository.dart';
import '../../progress/services/learning_progress_repository.dart';
import '../../setup/models/classroom_setup.dart';
import '../../setup/services/classroom_setup_repository.dart';
import 'assessment_recommendation_service.dart';
import 'quiz_repository.dart';

/// Where the screen is in its own lifecycle.
enum AssessmentStage {
  /// Questions and classroom are being read.
  loading,

  /// Something went wrong reading them. Retryable.
  error,

  /// Loaded, but this lesson has no assessment written for it. Not an error.
  noQuestions,

  /// At least one question is unanswered.
  inProgress,

  /// Every question has an answer and the result has been worked out.
  completed,
}

/// What the "hear this question" button is doing.
enum QuestionSpeech { idle, speaking }

/// Which language the question was, or would be, read aloud in.
enum SpokenIn {
  /// A reviewed mother-tongue wording exists and is what plays.
  targetLanguage,

  /// No mother-tongue wording exists, so the teaching-medium wording plays.
  teachingMedium,
}

/// Drives the assessment screen.
///
/// Holds which question is showing, what has been answered, and — once
/// everything has been answered — the result. It computes the score from the
/// answers it was given and nothing else: there is no default score anywhere in
/// this class, and no code path that produces a result from fewer answers than
/// there are questions.
class AssessmentController extends ChangeNotifier {
  AssessmentController({
    required QuizRepository quizzes,
    required ClassroomSetupRepository classrooms,
    required LessonAudioService audio,
    required ConnectivityService connectivity,
    required String teacherId,
    required String lessonId,
    LessonRepository? lessons,
    AssessmentRecommendationService? recommendations,
    ProgressRecorder recorder = const ProgressRecorder.none(),
    DateTime Function()? clock,
  })  : _quizzes = quizzes,
        _classrooms = classrooms,
        _audio = audio,
        _connectivity = connectivity,
        _teacherId = teacherId,
        _lessonId = lessonId,
        _lessons = lessons,
        _recommendations =
            recommendations ?? const LocalAssessmentRecommendationService(),
        _recorder = recorder,
        _now = clock ?? DateTime.now {
    _playbackSubscription = _audio.states.listen(_onPlayback);
    _connectionStatus = _connectivity.status;
    _connectivitySubscription =
        _connectivity.onStatusChanged.listen((ConnectionStatus status) {
      _connectionStatus = status;
      notifyListeners();
    });
    unawaited(load());
  }

  final QuizRepository _quizzes;
  final ClassroomSetupRepository _classrooms;
  final LessonAudioService _audio;
  final ConnectivityService _connectivity;
  final LessonRepository? _lessons;
  final AssessmentRecommendationService _recommendations;
  final String _teacherId;
  final String _lessonId;

  /// Writes "an assessment was finished, at this time" for Learning Insights.
  final ProgressRecorder _recorder;

  /// Injected so a test can pin the clock and assert on a duration.
  final DateTime Function() _now;

  StreamSubscription<PlaybackState>? _playbackSubscription;
  StreamSubscription<ConnectionStatus>? _connectivitySubscription;

  // --- Loaded context ------------------------------------------------------

  AssessmentStage _stage = AssessmentStage.loading;
  AssessmentStage get stage => _stage;

  List<QuizQuestion> _questions = const <QuizQuestion>[];
  List<QuizQuestion> get questions => _questions;

  ClassroomSetup? _classroom;
  ClassroomSetup? get classroom => _classroom;

  Lesson? _lesson;
  Lesson? get lesson => _lesson;

  String get lessonId => _lessonId;

  ConnectionStatus _connectionStatus = ConnectionStatus.unknown;

  /// The mother tongue this classroom teaches into. Every label naming a
  /// language reads this, never a constant.
  TargetLanguage get targetLanguage {
    // Python lesson uses English as its target language.
    if (_lessonId == 'python-intro') return TargetLanguage.english;
    return _classroom?.targetLanguage ?? TargetLanguage.santali;
  }

  TeachingMedium get teachingMedium =>
      _classroom?.teachingMedium ?? TeachingMedium.hindi;

  /// "Class 1 • Counting 1–10", from the lesson when there is one.
  String get subtitle {
    final Lesson? l = _lesson;
    final int classLevel = l?.classNumber ?? _classroom?.classLevel ?? 1;
    final String title = l?.title ?? 'Assessment';
    return 'Class $classLevel  •  $title';
  }

  /// What the header pill may claim, from the device's real state.
  ///
  /// The questions, the pictures and the marking are all on this phone, so the
  /// pill says the assessment is offline whatever the radio is doing; the
  /// connection is reported separately and only where it is true.
  String get connectionLabel => switch (_connectionStatus) {
        ConnectionStatus.offline => 'No connection',
        ConnectionStatus.online => 'Online',
        ConnectionStatus.unknown => 'Checking…',
      };

  // --- Where we are --------------------------------------------------------

  int _index = 0;
  int get index => _index;

  final Map<String, QuizAnswer> _answers = <String, QuizAnswer>{};

  /// Answers given so far, keyed by question id.
  Map<String, QuizAnswer> get answers =>
      Map<String, QuizAnswer>.unmodifiable(_answers);

  DateTime? _startedAt;

  /// When the current question came on screen, so the time it took can be
  /// measured rather than estimated.
  DateTime? _questionShownAt;

  QuestionSpeech _speech = QuestionSpeech.idle;
  QuestionSpeech get speech => _speech;

  String? _message;

  /// A note for the teacher — never an exception, never a fake success.
  String? get message => _message;

  void dismissMessage() {
    if (_message == null) return;
    _message = null;
    notifyListeners();
  }

  int get total => _questions.length;

  QuizQuestion? get current =>
      _questions.isEmpty ? null : _questions[_index.clamp(0, total - 1)];

  /// What was tapped for the question on screen, or null if nothing was.
  String? get selectedOptionId => _answers[current?.id]?.selectedOptionId;

  bool get isAnswered => selectedOptionId != null;

  int get answeredCount => _answers.length;

  bool get hasNext => _index < total - 1;

  bool get hasPrevious => _index > 0;

  bool get isLastQuestion => total > 0 && _index == total - 1;

  /// "Question 4 of 10".
  String get progressLabel => 'Question ${_index + 1} of $total';

  /// 0..1, counted from answers given rather than from how far the teacher has
  /// paged. Skipping ahead does not move the bar.
  double get progress => total == 0 ? 0 : answeredCount / total;

  int get percentComplete => (progress * 100).round();

  /// True only when every question has an answer.
  bool get allAnswered => total > 0 && answeredCount == total;

  QuizResult? _result;

  /// The finished result, or null until every question has been answered.
  QuizResult? get result => _result;

  PracticeSuggestion? _suggestion;

  /// What to practise next. Computed from [result] by a rule, never by a model.
  PracticeSuggestion? get suggestion => _suggestion;

  // --- Loading -------------------------------------------------------------

  Future<void> load() async {
    _stage = AssessmentStage.loading;
    notifyListeners();

    try {
      _questions = await _quizzes.questionsFor(_lessonId);
      _classroom = await _classrooms.load(_teacherId);
      _lesson = await _lessons?.lessonById(_lessonId);

      if (_questions.isEmpty) {
        _stage = AssessmentStage.noQuestions;
        notifyListeners();
        return;
      }

      // An assessment that was interrupted picks up where it stopped.
      _answers
        ..clear()
        ..addAll(await _quizzes.answersFor(_lessonId));
      // An answer whose question is no longer in the set would count towards a
      // total it is not part of.
      _answers.removeWhere(
        (String id, _) => !_questions.any((QuizQuestion q) => q.id == id),
      );

      _index = _firstUnansweredIndex();
      _startedAt = _now();
      _questionShownAt = _startedAt;
      _stage = AssessmentStage.inProgress;
      _recomputeIfComplete();
    } on Object catch (error) {
      AppLogger.error('assessment could not be loaded', error: error);
      _stage = AssessmentStage.error;
    }
    notifyListeners();
  }

  int _firstUnansweredIndex() {
    for (int i = 0; i < _questions.length; i++) {
      if (!_answers.containsKey(_questions[i].id)) return i;
    }
    return _questions.isEmpty ? 0 : _questions.length - 1;
  }

  // --- Answering -----------------------------------------------------------

  /// Records the tapped option for the question on screen.
  ///
  /// Does not advance. A child who taps the wrong tile should be able to change
  /// their mind before the teacher moves on, and tapping the same tile twice
  /// clears nothing and changes nothing.
  Future<void> select(String optionId) async {
    final QuizQuestion? question = current;
    if (question == null) return;
    if (question.optionById(optionId) == null) return;

    final QuizAnswer? existing = _answers[question.id];
    if (existing?.selectedOptionId == optionId) return;

    final DateTime at = _now();
    final DateTime? shown = _questionShownAt;

    _answers[question.id] = QuizAnswer(
      questionId: question.id,
      selectedOptionId: optionId,
      correct: question.isCorrect(optionId),
      answeredAt: at,
      // Only measured for the first answer to a question. A child who changes
      // their mind has not taken that long to think; reporting the second gap
      // would be a smaller number that means nothing.
      timeTaken: existing?.timeTaken ??
          (shown == null ? null : at.difference(shown)),
    );
    _message = null;

    unawaited(_persist(question.id));
    _recomputeIfComplete();
    notifyListeners();
  }

  Future<void> _persist(String questionId) async {
    final QuizAnswer? answer = _answers[questionId];
    if (answer == null) return;
    try {
      await _quizzes.saveAnswer(_lessonId, answer);
    } on Object catch (error) {
      // Losing the saved copy does not lose the answer on screen, so this is
      // logged rather than shown.
      AppLogger.error('assessment answer was not saved', error: error);
    }
  }

  /// Works out the result once, as soon as the last question is answered, and
  /// keeps it in step if an answer is changed afterwards.
  void _recomputeIfComplete() {
    if (!allAnswered) {
      _result = null;
      _suggestion = null;
      if (_stage == AssessmentStage.completed) {
        _stage = AssessmentStage.inProgress;
      }
      return;
    }

    final DateTime started = _startedAt ?? _now();
    final QuizResult result = QuizResult.from(
      lessonId: _lessonId,
      questions: _questions,
      answers: _answers,
      startedAt: started,
      // The clock stops at the last answer, not when the screen is looked at.
      finishedAt: _latestAnswerTime() ?? _now(),
    );

    _result = result;
    _suggestion = _recommendations.suggest(result);
    _stage = AssessmentStage.completed;
    unawaited(_recordResult(result));
  }

  DateTime? _latestAnswerTime() {
    DateTime? latest;
    for (final QuizAnswer a in _answers.values) {
      if (latest == null || a.answeredAt.isAfter(latest)) latest = a.answeredAt;
    }
    return latest;
  }

  Future<void> _recordResult(QuizResult result) async {
    try {
      await _quizzes.saveResult(result);
    } on Object catch (error) {
      AppLogger.error('assessment result was not saved', error: error);
    }
    // Only a finished assessment is recorded. There is no code path that
    // records one from fewer answers than there are questions.
    await _recorder.record(
      ProgressEventType.assessmentCompleted,
      lessonId: result.lessonId,
      at: result.finishedAt,
      metadata: <String, String>{
        'score': '${result.score}',
        'total': '${result.total}',
        'percentage': '${result.percentage}',
      },
    );
  }

  // --- Moving through the questions ----------------------------------------

  /// Moves on. Refuses while the question on screen is unanswered, and says so.
  Future<void> next() async {
    if (!isAnswered) {
      _message = 'Choose an answer before moving on.';
      notifyListeners();
      return;
    }
    if (!hasNext) return;
    await _moveTo(_index + 1);
  }

  /// Goes back. The answer already given for that question is still selected
  /// when it comes back on screen.
  Future<void> previous() async {
    if (!hasPrevious) return;
    await _moveTo(_index - 1);
  }

  Future<void> goTo(int index) async {
    if (index < 0 || index >= total || index == _index) return;
    await _moveTo(index);
  }

  Future<void> _moveTo(int index) async {
    await _stopSpeech();
    _index = index;
    _message = null;
    // Only start the clock on a question nobody has answered yet, so paging
    // back through finished questions does not invent thinking time.
    _questionShownAt =
        _answers.containsKey(_questions[index].id) ? null : _now();
    notifyListeners();
  }

  /// Clears every answer and starts again.
  Future<void> restart() async {
    await _stopSpeech();
    _answers.clear();
    _result = null;
    _suggestion = null;
    _index = 0;
    _startedAt = _now();
    _questionShownAt = _startedAt;
    _stage = AssessmentStage.inProgress;
    _message = null;
    notifyListeners();
    try {
      await _quizzes.clearAnswers(_lessonId);
    } on Object catch (error) {
      AppLogger.error('assessment answers were not cleared', error: error);
    }
  }

  // --- Audio ---------------------------------------------------------------

  /// Whether a reviewed mother-tongue wording of this question exists.
  bool get hasTargetLanguageReading =>
      current?.spokenTextFor(targetLanguage) != null;

  /// Which language the button would actually read the question in.
  SpokenIn get spokenIn => hasTargetLanguageReading
      ? SpokenIn.targetLanguage
      : SpokenIn.teachingMedium;

  /// Exactly what the listen button says, so it can never promise Santali and
  /// then play Hindi.
  String get listenLabel => switch (spokenIn) {
        SpokenIn.targetLanguage =>
          'Hear question in ${targetLanguage.label}',
        SpokenIn.teachingMedium => 'Hear question in ${teachingMedium.label}',
      };

  /// Shown under the button when there is no mother-tongue wording. Null when
  /// there is one and nothing needs explaining.
  String? get listenNote => hasTargetLanguageReading
      ? null
      : 'No ${targetLanguage.label} wording of this question has been written '
          'and checked yet, so it is read in ${teachingMedium.label}.';

  /// Reads the question aloud, or stops it if it is already reading.
  Future<void> listen() async {
    final QuizQuestion? question = current;
    if (question == null) return;

    if (_speech == QuestionSpeech.speaking) {
      await _stopSpeech();
      notifyListeners();
      return;
    }

    final String? targetText = question.spokenTextFor(targetLanguage);
    final bool inTarget = targetText != null;

    _message = null;
    final AudioRequestOutcome outcome = await _audio.play(
      SpokenPassage(
        lessonId: 'assessment-$_lessonId',
        label: inTarget ? targetLanguage.label : teachingMedium.label,
        displayText: inTarget ? targetText : question.promptHindi,
        localeId:
            inTarget ? targetLanguage.localeId : teachingMedium.localeId,
        spokenText: inTarget ? targetText : null,
        // Devanagari is the script both wordings are written in, so an Indic
        // voice is the one that can pronounce them.
        spokenScriptLocaleId: inTarget ? teachingMedium.localeId : null,
        textHash: question.id,
      ),
    );

    switch (outcome) {
      case AudioStarted():
        _speech = QuestionSpeech.speaking;
      case AudioBlocked(:final String message):
        _speech = QuestionSpeech.idle;
        _message = message;
      case AudioFailed():
        _speech = QuestionSpeech.idle;
        _message = 'Audio is unavailable on this device.';
    }
    notifyListeners();
  }

  Future<void> stopAudio() async {
    if (_speech == QuestionSpeech.idle) return;
    await _stopSpeech();
    notifyListeners();
  }

  Future<void> _stopSpeech() async {
    if (_speech == QuestionSpeech.idle) return;
    await _audio.stop();
    _speech = QuestionSpeech.idle;
  }

  void _onPlayback(PlaybackState state) {
    final QuestionSpeech next = state == PlaybackState.playing
        ? QuestionSpeech.speaking
        : QuestionSpeech.idle;
    if (next == _speech) return;
    _speech = next;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_playbackSubscription?.cancel());
    unawaited(_connectivitySubscription?.cancel());
    super.dispose();
  }
}
