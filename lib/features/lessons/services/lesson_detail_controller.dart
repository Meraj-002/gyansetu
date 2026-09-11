// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/utils/app_logger.dart';
import '../../../models/lesson.dart';
import '../../../models/lesson_plan.dart';
import '../../../models/lesson_translation.dart';
import '../../../models/progress_event.dart';
import '../../../services/audio/lesson_audio_service.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../progress/services/learning_progress_repository.dart';
import '../../setup/models/classroom_setup.dart';
import '../../setup/models/offline_resource_status.dart';
import '../../setup/services/classroom_setup_repository.dart';
import '../../setup/services/offline_resource_manager.dart';
import 'assessment_repository.dart';
import 'lesson_content_repository.dart';
import 'lesson_library_controller.dart' show LibraryOfflineState;
import 'lesson_repository.dart';
import 'translation_service.dart';

/// What the translation section is doing.
enum TranslationUiState {
  /// Nothing asked for yet.
  idle,

  /// A request is in flight.
  translating,

  /// A translation is on screen.
  ready,

  /// Offline and nothing saved for this language.
  offlineUnavailable,

  /// No translation exists for this lesson in this language.
  missing,

  /// The attempt failed and can be retried.
  error,
}

/// A step the teacher genuinely completed.
///
/// Progress is the highest milestone actually reached, never a number chosen to
/// make the screen look busy. Opening the lesson earns nothing.
enum LessonMilestone {
  /// The teacher played the script aloud in the classroom.
  scriptRead(percent: 25),

  /// The lesson was translated into the mother tongue.
  translated(percent: 50),

  /// The classroom activity was opened.
  activityOpened(percent: 75),

  /// The lesson was taught in a live session with at least one interaction.
  /// The same level as opening the activity: both mean the lesson was used in
  /// class, and neither is evidence the children have it yet.
  taughtLive(percent: 75),

  /// The quick assessment was completed and recorded.
  assessed(percent: 100);

  const LessonMilestone({required this.percent});

  final int percent;
}

/// Drives lesson detail.
///
/// Every service it needs is injected, so the screen can be built in a test
/// with fakes and, later, with FastAPI-backed implementations, without a single
/// change above this class.
class LessonDetailController extends ChangeNotifier {
  LessonDetailController({
    required String lessonId,
    required LessonRepository lessons,
    required LessonContentRepository content,
    required TranslationService translations,
    required LessonAudioService audio,
    required LessonProgressRepository progress,
    required AssessmentRepository assessments,
    required ClassroomSetupRepository classrooms,
    required OfflineResourceManager resources,
    required ConnectivityService connectivity,
    required String teacherId,
    ProgressRecorder recorder = const ProgressRecorder.none(),
  })  : _lessonId = lessonId,
        _lessons = lessons,
        _content = content,
        _translations = translations,
        _audio = audio,
        _progress = progress,
        _assessments = assessments,
        _classrooms = classrooms,
        _resources = resources,
        _teacherId = teacherId,
        _recorder = recorder {
    _connectionStatus = connectivity.status;
    _connectivitySubscription =
        connectivity.onStatusChanged.listen((ConnectionStatus status) {
      _connectionStatus = status;
      notifyListeners();
    });
    _playbackSubscription = _audio.states.listen((PlaybackState state) {
      _playback = state;
      notifyListeners();
    });
    _progressSubscription = _audio.progress.listen((double value) {
      _audioProgress = value;
      notifyListeners();
    });
    unawaited(load());
  }

  final String _lessonId;
  final LessonRepository _lessons;
  final LessonContentRepository _content;
  final TranslationService _translations;
  final LessonAudioService _audio;
  final LessonProgressRepository _progress;
  final AssessmentRepository _assessments;
  final ClassroomSetupRepository _classrooms;
  final OfflineResourceManager _resources;
  final String _teacherId;

  /// Where "this happened, at this time" is written. Learning Insights needs a
  /// timestamp for a finished lesson, and the progress store keeps only a
  /// percentage. Defaults to a recorder that keeps nothing, so a caller that
  /// does not care — a test — needs no wiring.
  final ProgressRecorder _recorder;

  StreamSubscription<ConnectionStatus>? _connectivitySubscription;
  StreamSubscription<PlaybackState>? _playbackSubscription;
  StreamSubscription<double>? _progressSubscription;

  // --- Lesson --------------------------------------------------------------

  bool _loading = true;
  bool get loading => _loading;

  Lesson? _lesson;
  Lesson? get lesson => _lesson;

  bool _notFound = false;

  /// True when the id handed to this screen resolves to nothing.
  bool get notFound => _notFound;

  LessonPlan? _plan;
  LessonPlan? get plan => _plan;

  String? _planMessage;

  /// Why there is no plan, when there is none.
  String? get planMessage => _planMessage;

  bool get hasContent => _plan != null;

  ClassroomSetup? _classroom;
  ClassroomSetup? get classroom => _classroom;

  /// The mother tongue this classroom teaches into. Every label on the screen
  /// that names a language reads this, never a constant.
  TargetLanguage get targetLanguage {
    // Python lesson uses English as its target language.
    if (_lessonId == 'python-intro') return TargetLanguage.english;
    return _classroom?.targetLanguage ?? TargetLanguage.santali;
  }

  TeachingMedium get teachingMedium =>
      _classroom?.teachingMedium ?? _plan?.scriptMedium ?? TeachingMedium.hindi;

  // --- Translation ---------------------------------------------------------

  TranslationUiState _translationState = TranslationUiState.idle;
  TranslationUiState get translationState => _translationState;

  LessonTranslation? _translation;
  LessonTranslation? get translation => _translation;

  String? _translationMessage;
  String? get translationMessage => _translationMessage;

  bool get isTranslating => _translationState == TranslationUiState.translating;

  // --- Audio ---------------------------------------------------------------

  PlaybackState _playback = PlaybackState.idle;
  PlaybackState get playback => _playback;

  double _audioProgress = 0;

  /// 0..1, and only ever a position the engine reported. The waveform reads
  /// this; it draws no position when nothing has been reported.
  double get audioProgress => _audioProgress;

  AudioSpeed get speed => _audio.speed;

  AudioAvailability? _targetAudio;

  /// What can voice the mother-tongue passage, once it is known.
  AudioAvailability? get targetAudio => _targetAudio;

  bool _savingAudio = false;
  bool get savingAudio => _savingAudio;

  bool _audioSaved = false;
  bool get audioSaved => _audioSaved;

  /// Which passage is sounding, so only that card shows the playing state.
  String? _activePassage;
  String? get activePassage => _activePassage;

  static const String scriptPassageId = 'script';
  static const String targetPassageId = 'target';

  // --- Progress and assessment ---------------------------------------------

  int _percent = 0;
  int get completionPercentage => _percent;

  AssessmentResult? _assessment;
  AssessmentResult? get assessmentResult => _assessment;

  // --- Shared state --------------------------------------------------------

  ConnectionStatus _connectionStatus = ConnectionStatus.unknown;
  ConnectionStatus get connectionStatus => _connectionStatus;

  OfflineResourceStatus _resourceStatus = const OfflineResourceStatus.unknown();

  String? _message;

  /// A transient note for the teacher — a refusal, a confirmation. Never an
  /// exception.
  String? get message => _message;

  void dismissMessage() {
    if (_message == null) return;
    _message = null;
    notifyListeners();
  }

  /// The same pill the library shows, computed the same way, so the two screens
  /// can never disagree about whether this device is ready.
  LibraryOfflineState get offlineState {
    if (_connectionStatus == ConnectionStatus.unknown) {
      return LibraryOfflineState.unknown;
    }
    if (_connectionStatus == ConnectionStatus.online) {
      return LibraryOfflineState.online;
    }
    if (!hasContent) return LibraryOfflineState.resourcesMissing;
    if (_resourceStatus.readiness == OfflineReadiness.ready) {
      return LibraryOfflineState.offlineReady;
    }
    return LibraryOfflineState.syncRequired;
  }

  // --- Loading -------------------------------------------------------------

  Future<void> load() async {
    _loading = true;
    _notFound = false;
    notifyListeners();

    try {
      _classroom = await _classrooms.load(_teacherId);
      final Lesson? lesson = await _lessons.lessonById(_lessonId);

      if (lesson == null) {
        _lesson = null;
        _notFound = true;
        _loading = false;
        notifyListeners();
        return;
      }
      _lesson = lesson;

      final ClassroomSetup? classroom = _classroom;
      if (classroom != null) {
        final PlanResult result = await _content.planFor(lesson, classroom);
        switch (result) {
          case PlanLoaded(:final LessonPlan plan):
            _plan = plan;
            _planMessage = null;
          case PlanUnavailable(:final String message):
            _plan = null;
            _planMessage = message;
        }
        _resourceStatus = await _resources.check(classroom.resourceProfile);
      } else {
        // Without a classroom there is no teaching medium and no mother tongue,
        // so the screen cannot honestly claim a language pair. It says so
        // rather than guessing one.
        _plan = await _content.cachedPlan(lesson.id);
        _planMessage = _plan == null
            ? 'Finish classroom setup to open this lesson.'
            : null;
      }

      _percent = await _progress.percentFor(lesson.id);
      _assessment = await _assessments.latestFor(lesson.id);

      await _loadCachedTranslation();
      await _refreshAudioAvailability();
    } on Object catch (error) {
      AppLogger.error('lesson detail could not be loaded', error: error);
      _notFound = _lesson == null;
      _planMessage ??= "Couldn't open this lesson right now.";
    }

    _loading = false;
    notifyListeners();
  }

  /// A saved translation is shown immediately, with no request and no spinner.
  /// This is what makes reopening a lesson offline feel identical to online.
  Future<void> _loadCachedTranslation() async {
    final Lesson? lesson = _lesson;
    if (lesson == null) return;

    final LessonTranslation? saved =
        await _translations.cached(lesson.id, targetLanguage);
    if (saved == null) {
      _translation = null;
      _translationState = TranslationUiState.idle;
      return;
    }
    _translation = saved;
    _translationState = TranslationUiState.ready;
  }

  Future<void> _refreshAudioAvailability() async {
    final SpokenPassage? passage = targetPassage;
    if (passage == null) {
      _targetAudio = null;
      _audioSaved = false;
      return;
    }
    _targetAudio = await _audio.availability(passage);
    _audioSaved = _targetAudio?.saved ?? false;
  }

  // --- Passages ------------------------------------------------------------

  /// The teacher script, in the classroom's teaching medium.
  SpokenPassage? get scriptPassage {
    final LessonPlan? plan = _plan;
    final Lesson? lesson = _lesson;
    if (plan == null || lesson == null) return null;

    return SpokenPassage(
      lessonId: lesson.id,
      label: plan.scriptMedium.label,
      displayText: plan.teacherScript,
      localeId: plan.scriptMedium.localeId,
    );
  }

  /// The translated script, in the classroom's mother tongue.
  SpokenPassage? get targetPassage {
    final LessonTranslation? translation = _translation;
    final Lesson? lesson = _lesson;
    if (translation == null || lesson == null) return null;

    return SpokenPassage(
      lessonId: lesson.id,
      label: translation.targetLanguage.label,
      displayText: translation.text,
      localeId: translation.targetLanguage.localeId,
      spokenText: translation.spokenText,
      // Devanagari is the script the spoken form is written in, so a Hindi
      // voice is the one that can pronounce it.
      spokenScriptLocaleId:
          translation.spokenText == null ? null : TeachingMedium.hindi.localeId,
    );
  }

  // --- Translation ---------------------------------------------------------

  Future<void> translate() async {
    final Lesson? lesson = _lesson;
    final LessonPlan? plan = _plan;
    if (lesson == null || plan == null) return;
    if (_translationState == TranslationUiState.translating) return;

    _translationState = TranslationUiState.translating;
    _translationMessage = null;
    notifyListeners();

    final TranslationOutcome outcome = await _translations.translate(
      lesson: lesson,
      plan: plan,
      target: targetLanguage,
    );

    switch (outcome) {
      case TranslationReady(:final LessonTranslation translation):
        _translation = translation;
        _translationState = TranslationUiState.ready;
        _translationMessage = null;
        await _refreshAudioAvailability();
        await _reach(LessonMilestone.translated);
      case TranslationNeedsConnection(:final String message):
        _translationState = TranslationUiState.offlineUnavailable;
        _translationMessage = message;
      case TranslationMissing(:final String message):
        _translationState = TranslationUiState.missing;
        _translationMessage = message;
      case TranslationFailed(:final String message):
        _translationState = TranslationUiState.error;
        _translationMessage = message;
    }
    notifyListeners();
  }

  // --- Audio ---------------------------------------------------------------

  Future<void> playScript() => _play(scriptPassage, scriptPassageId);

  Future<void> playTarget() => _play(targetPassage, targetPassageId);

  Future<void> _play(SpokenPassage? passage, String id) async {
    if (passage == null) return;

    // A second tap on something already sounding pauses it, which is what a
    // teacher expects from a play button mid-sentence.
    if (_activePassage == id && _playback == PlaybackState.playing) {
      await _audio.pause();
      return;
    }

    _activePassage = id;
    _message = null;
    notifyListeners();

    final AudioRequestOutcome outcome = await _audio.play(passage);
    _handleAudioOutcome(outcome);

    if (outcome is AudioStarted && id == scriptPassageId) {
      await _reach(LessonMilestone.scriptRead);
    }
    notifyListeners();
  }

  /// Resumes a paused passage, or starts it again if it had finished.
  Future<void> resumeOrReplay() async {
    final String? id = _activePassage;
    if (id == null) return;
    await _play(id == scriptPassageId ? scriptPassage : targetPassage, id);
  }

  /// Replays from the beginning, whatever state playback is in.
  Future<void> repeat() async {
    final String id = _activePassage ?? targetPassageId;
    final SpokenPassage? passage =
        id == scriptPassageId ? scriptPassage : targetPassage;
    if (passage == null) return;

    _activePassage = id;
    notifyListeners();

    _handleAudioOutcome(await _audio.repeat(passage));
    notifyListeners();
  }

  Future<void> stopAudio() async {
    await _audio.stop();
    _activePassage = null;
    notifyListeners();
  }

  /// Toggles between normal and slow, and applies it to sound already playing.
  Future<void> toggleSpeed() async {
    final AudioSpeed next =
        _audio.speed == AudioSpeed.slow ? AudioSpeed.normal : AudioSpeed.slow;
    final String? id = _activePassage;
    await _audio.setSpeed(
      next,
      current: id == scriptPassageId ? scriptPassage : targetPassage,
    );
    notifyListeners();
  }

  Future<void> saveAudio() async {
    final SpokenPassage? passage = targetPassage;
    if (passage == null || _savingAudio) return;

    _savingAudio = true;
    _message = null;
    notifyListeners();

    final SaveAudioOutcome outcome = await _audio.save(passage);
    _savingAudio = false;

    switch (outcome) {
      case AudioSaved():
        // Availability is re-read first, then the saved flag is set: reading it
        // afterwards would let a stale answer undo what just succeeded.
        await _refreshAudioAvailability();
        _audioSaved = true;
        _message = 'Saved for offline use.';
      case AudioAlreadySaved():
        _audioSaved = true;
        _message = 'Already saved on this device.';
      case SaveBlocked(:final String message):
        _message = message;
      case SaveFailed(:final String message):
        _message = message;
    }
    notifyListeners();
  }

  void _handleAudioOutcome(AudioRequestOutcome outcome) {
    switch (outcome) {
      case AudioStarted():
        _message = null;
      case AudioBlocked(:final String message):
        _activePassage = null;
        _message = message;
      case AudioFailed(:final String message):
        _activePassage = null;
        _message = message;
    }
  }

  // --- Progress ------------------------------------------------------------

  /// Records a milestone, but only ever upwards: reopening a finished lesson
  /// must not knock its progress back down.
  Future<void> _reach(LessonMilestone milestone) async {
    final Lesson? lesson = _lesson;
    if (lesson == null) return;
    if (milestone.percent <= _percent) return;

    final int before = _percent;
    _percent = milestone.percent;
    await _progress.setPercent(lesson.id, _percent);

    // The first milestone of any kind means the lesson was actually taken up;
    // reaching 100 means it was finished. Opening the screen does neither.
    if (before == 0) {
      unawaited(
        _recorder.record(
          ProgressEventType.lessonStarted,
          lessonId: lesson.id,
          metadata: <String, String>{'milestone': milestone.name},
        ),
      );
    }
    if (_percent >= 100) {
      unawaited(
        _recorder.record(
          ProgressEventType.lessonCompleted,
          lessonId: lesson.id,
          metadata: <String, String>{'subject': lesson.subject.name},
        ),
      );
    }
    notifyListeners();
  }

  /// Called when the teacher actually opens the activity.
  Future<void> activityOpened() => _reach(LessonMilestone.activityOpened);

  /// Called when the teacher finishes the quick assessment.
  Future<void> recordAssessment(AssessmentResult result) async {
    _assessment = result;
    await _assessments.record(result);
    await _reach(LessonMilestone.assessed);
    _message = 'Assessment saved for ${result.achievedCount} of '
        '${result.total}.';
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_connectivitySubscription?.cancel());
    unawaited(_playbackSubscription?.cancel());
    unawaited(_progressSubscription?.cancel());
    unawaited(_audio.stop());
    super.dispose();
  }
}
