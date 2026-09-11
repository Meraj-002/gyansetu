import 'dart:async';

import 'package:gyan_setu_ai/features/lessons/services/lesson_content_repository.dart';
import 'package:gyan_setu_ai/features/lessons/services/translation_service.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/models/lesson.dart';
import 'package:gyan_setu_ai/models/lesson_plan.dart';
import 'package:gyan_setu_ai/models/lesson_translation.dart';
import 'package:gyan_setu_ai/services/audio/audio_resource_store.dart';
import 'package:gyan_setu_ai/services/audio/lesson_audio_service.dart';

/// A plan the test controls completely.
LessonPlan testPlan({
  String lessonId = 'a',
  String script = 'बच्चों, आज हम 1 से 10 तक गिनती सीखेंगे।',
  TeachingMedium medium = TeachingMedium.hindi,
  ContentProvenance provenance = ContentProvenance.authored,
  bool curriculumAligned = true,
  String? competency = 'NIPUN Bharat • Numeracy • Counts up to 10',
  TeachingTip? tip,
}) =>
    LessonPlan(
      lessonId: lessonId,
      scriptMedium: medium,
      teacherScript: script,
      provenance: provenance,
      curriculumAligned: curriculumAligned,
      flnCompetency: competency,
      tip: tip ??
          const TeachingTip(
            text: 'Use real objects like seeds, sticks, or stones.',
          ),
      activity: const ClassroomActivity(
        id: 'act-1',
        title: 'Count with real objects',
        summary: 'Show 5 objects and ask children to count them.',
        steps: <String>['Put five seeds on the desk.', 'Count them together.'],
        materials: <String>['Seeds'],
        minutes: 6,
      ),
      assessment: const QuickAssessment(
        id: 'qa-1',
        title: 'Quick Assessment',
        summary: 'Ask the child to show 3 objects.',
        questions: <AssessmentQuestion>[
          AssessmentQuestion(
            id: 'q1',
            prompt: 'Ask the child to show 3 objects.',
            successCriteria: 'Picks up exactly three.',
          ),
          AssessmentQuestion(
            id: 'q2',
            prompt: 'Ask the child to count 7 stones.',
            successCriteria: 'Counts to seven.',
          ),
        ],
      ),
      generatedAt: DateTime(2026, 6, 1),
    );

LessonTranslation testTranslation({
  String lessonId = 'a',
  TargetLanguage target = TargetLanguage.santali,
  String text = "Johar gidra'ko! Mit', bar, pe, pon, more.",
  String? spokenText = 'जोहार गिड़ाको! मित्, बार, पे, पोन, मोड़े।',
  bool reviewed = false,
}) =>
    LessonTranslation(
      lessonId: lessonId,
      sourceMedium: TeachingMedium.hindi,
      targetLanguage: target,
      text: text,
      spokenText: spokenText,
      reviewedBySpeaker: reviewed,
      createdAt: DateTime(2026, 6, 1),
    );

/// Serves whichever plan the test set, or the reason it cannot.
class FakeContentRepository implements LessonContentRepository {
  FakeContentRepository({this.plan, this.unavailable, this.latency});

  LessonPlan? plan;

  /// Returned instead of [plan] when set.
  PlanUnavailable? unavailable;

  /// Holds the load open so the skeleton is observable.
  Duration? latency;

  int planCalls = 0;

  @override
  Future<LessonPlan?> cachedPlan(String lessonId) async => plan;

  @override
  Future<PlanResult> planFor(Lesson lesson, ClassroomSetup classroom) async {
    planCalls++;
    final Duration? wait = latency;
    if (wait != null) await Future<void>.delayed(wait);

    final PlanUnavailable? blocked = unavailable;
    if (blocked != null) return blocked;

    final LessonPlan? value = plan;
    if (value == null) {
      return const PlanUnavailable(
        PlanUnavailableReason.noContent,
        "Lesson content isn't available for this lesson yet.",
      );
    }
    return PlanLoaded(value);
  }
}

/// A translation service whose every outcome the test dictates.
class FakeTranslationService implements TranslationService {
  FakeTranslationService({
    this.outcome,
    this.cachedTranslation,
    this.latency = Duration.zero,
  });

  /// What [translate] returns. Defaults to a successful translation.
  TranslationOutcome? outcome;

  /// What is already on the device.
  LessonTranslation? cachedTranslation;

  Duration latency;

  int translateCalls = 0;

  @override
  Future<LessonTranslation?> cached(
    String lessonId,
    TargetLanguage target,
  ) async =>
      cachedTranslation;

  @override
  Future<TranslationOutcome> translate({
    required Lesson lesson,
    required LessonPlan plan,
    required TargetLanguage target,
  }) async {
    translateCalls++;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return outcome ?? TranslationReady(testTranslation(target: target));
  }

  @override
  Future<void> forget(String lessonId, TargetLanguage target) async =>
      cachedTranslation = null;
}

/// An audio service that records what it was asked to do.
///
/// It reports states through the same stream the real one uses, so the screen
/// under test goes through exactly the transitions it would in production.
class FakeAudioService implements LessonAudioService {
  FakeAudioService({
    this.availabilityResult =
        const AudioAvailability(kind: AudioVoiceKind.nativeVoice),
    this.playOutcome,
    this.saveOutcome,
  });

  AudioAvailability availabilityResult;

  /// Defaults to starting successfully.
  AudioRequestOutcome? playOutcome;

  SaveAudioOutcome? saveOutcome;

  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();
  final StreamController<double> _progress =
      StreamController<double>.broadcast();

  PlaybackState _state = PlaybackState.idle;
  AudioSpeed _speed = AudioSpeed.normal;
  double _progressValue = 0;

  final List<String> calls = <String>[];
  SpokenPassage? lastPassage;
  int playCalls = 0;
  int repeatCalls = 0;
  int saveCalls = 0;

  @override
  PlaybackState get state => _state;

  @override
  AudioSpeed get speed => _speed;

  @override
  Stream<PlaybackState> get states => _states.stream;

  @override
  Stream<double> get progress => _progress.stream;

  @override
  double get progressValue => _progressValue;

  void emit(PlaybackState next) {
    _state = next;
    _states.add(next);
  }

  void emitProgress(double value) {
    _progressValue = value;
    _progress.add(value);
  }

  @override
  Future<AudioAvailability> availability(SpokenPassage passage) async =>
      availabilityResult;

  @override
  Future<AudioRequestOutcome> play(SpokenPassage passage) async {
    playCalls++;
    calls.add('play');
    lastPassage = passage;
    final AudioRequestOutcome result =
        playOutcome ?? const AudioStarted(AudioVoiceKind.nativeVoice);
    if (result is AudioStarted) emit(PlaybackState.playing);
    return result;
  }

  @override
  Future<AudioRequestOutcome> repeat(SpokenPassage passage) async {
    repeatCalls++;
    calls.add('repeat');
    lastPassage = passage;
    emit(PlaybackState.idle);
    emit(PlaybackState.playing);
    return const AudioStarted(AudioVoiceKind.nativeVoice);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    emit(PlaybackState.paused);
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    emit(PlaybackState.idle);
  }

  @override
  Future<void> setSpeed(AudioSpeed speed, {SpokenPassage? current}) async {
    calls.add('speed:${speed.name}');
    _speed = speed;
  }

  @override
  Future<SaveAudioOutcome> save(SpokenPassage passage) async {
    saveCalls++;
    calls.add('save');
    return saveOutcome ??
        AudioSaved(
          AudioResourceStub(passage.lessonId, passage.localeId).resource,
        );
  }

  @override
  Future<void> dispose() async {
    await _states.close();
    await _progress.close();
  }
}

/// Builds a plausible saved-clip record without touching the file system.
class AudioResourceStub {
  AudioResourceStub(this.lessonId, this.localeId);

  final String lessonId;
  final String localeId;

  AudioResource get resource => AudioResource(
        audioResourceId: 'audio-$lessonId-$localeId',
        lessonId: lessonId,
        localeId: localeId,
        filePath: '/tmp/$lessonId-$localeId.wav',
        createdAt: DateTime(2026, 6, 1),
      );
}
