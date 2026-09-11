import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/core/errors/app_exception.dart';
import 'package:gyan_setu_ai/core/utils/result.dart';
import 'package:gyan_setu_ai/features/lessons/services/ai_content_service.dart';
import 'package:gyan_setu_ai/features/lessons/services/lesson_content_repository.dart';
import 'package:gyan_setu_ai/features/lessons/services/translation_service.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/models/lesson.dart';
import 'package:gyan_setu_ai/models/lesson_plan.dart';
import 'package:gyan_setu_ai/models/lesson_translation.dart';
import 'package:gyan_setu_ai/services/audio/audio_resource_store.dart';
import 'package:gyan_setu_ai/services/audio/clip_player.dart';
import 'package:gyan_setu_ai/services/audio/lesson_audio_service.dart';
import 'package:gyan_setu_ai/services/audio/text_to_speech_service.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';

import 'lesson_detail_doubles.dart';
import 'lesson_test_doubles.dart';

/// An AI service the test drives, including whether it claims a real provider.
class ScriptedAiContentService implements AiContentService {
  ScriptedAiContentService({
    this.hasProvider = false,
    this.plan,
    this.translation,
    this.translationFailure,
    this.throwOnTranslate = false,
  });

  @override
  final bool hasProvider;

  LessonPlan? plan;
  LessonTranslation? translation;
  AiContentUnavailable<LessonTranslation>? translationFailure;
  bool throwOnTranslate;

  int translateCalls = 0;
  int generateCalls = 0;

  @override
  Future<AiContentResult<LessonPlan>> generateLesson({
    required Lesson lesson,
    required ClassroomSetup classroom,
  }) async {
    generateCalls++;
    final LessonPlan? value = plan;
    return value == null
        ? const AiContentUnavailable<LessonPlan>(
            AiUnavailableReason.notConfigured,
            'not configured',
          )
        : AiContent<LessonPlan>(value);
  }

  @override
  Future<AiContentResult<LessonTranslation>> translateLesson({
    required Lesson lesson,
    required LessonPlan plan,
    required TargetLanguage target,
  }) async {
    translateCalls++;
    if (throwOnTranslate) throw StateError('provider exploded');
    final AiContentUnavailable<LessonTranslation>? failure = translationFailure;
    if (failure != null) return failure;
    final LessonTranslation? value = translation;
    return value == null
        ? const AiContentUnavailable<LessonTranslation>(
            AiUnavailableReason.noContent,
            'This lesson has not been translated into Santali yet.',
          )
        : AiContent<LessonTranslation>(value);
  }

  @override
  Future<AiContentResult<LessonPlan>> adaptLesson({
    required LessonPlan plan,
    required ClassroomSetup classroom,
  }) async =>
      const AiContentUnavailable<LessonPlan>(
        AiUnavailableReason.notConfigured,
        'not configured',
      );

  @override
  Future<AiContentResult<ClassroomActivity>> generateActivity({
    required Lesson lesson,
    required ClassroomSetup classroom,
  }) async =>
      const AiContentUnavailable<ClassroomActivity>(
        AiUnavailableReason.notConfigured,
        'not configured',
      );

  @override
  Future<AiContentResult<QuickAssessment>> generateAssessment({
    required Lesson lesson,
    required ClassroomSetup classroom,
  }) async =>
      const AiContentUnavailable<QuickAssessment>(
        AiUnavailableReason.notConfigured,
        'not configured',
      );

  @override
  Future<AiContentResult<TeachingTip>> generateTeachingTip({
    required Lesson lesson,
    required ClassroomSetup classroom,
  }) async =>
      const AiContentUnavailable<TeachingTip>(
        AiUnavailableReason.notConfigured,
        'not configured',
      );

  @override
  Future<AiContentResult<String>> generateWorksheet({
    required Lesson lesson,
    required ClassroomSetup classroom,
  }) async =>
      const AiContentUnavailable<String>(
        AiUnavailableReason.notConfigured,
        'not configured',
      );

  @override
  Future<AiContentResult<String>> generateFlashcards({
    required Lesson lesson,
    required ClassroomSetup classroom,
  }) async =>
      const AiContentUnavailable<String>(
        AiUnavailableReason.notConfigured,
        'not configured',
      );
}

/// A speech engine the test controls, with no platform channel behind it.
class FakeTts implements TextToSpeechService {
  FakeTts({
    this.languages = const <String>{'hi-IN'},
    this.canSynthesiseToFile = true,
    this.speakFails = false,
  });

  Set<String> languages;

  @override
  bool canSynthesiseToFile;

  bool speakFails;

  @override
  bool get canPause => true;

  @override
  bool get canResume => false;

  final StreamController<SpeechEvent> _events =
      StreamController<SpeechEvent>.broadcast();
  final StreamController<double> _progress =
      StreamController<double>.broadcast();

  final List<String> spoken = <String>[];
  final List<String> locales = <String>[];
  final List<double> speeds = <double>[];
  String? synthesisedTo;
  int stopCalls = 0;
  int pauseCalls = 0;

  @override
  Stream<SpeechEvent> get events => _events.stream;

  @override
  Stream<double> get progress => _progress.stream;

  @override
  Future<Result<List<String>>> availableLanguages() async =>
      Ok<List<String>>(languages.toList());

  @override
  Future<bool> isLanguageAvailable(String localeId) async =>
      languages.contains(localeId);

  @override
  Future<Result<void>> speak(String text, {required String localeId}) async {
    if (speakFails) {
      return Err<void>(const AudioException('The audio could not be played'));
    }
    spoken.add(text);
    locales.add(localeId);
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> pause() async {
    pauseCalls++;
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> resume() async =>
      const Err<void>(AudioException('resume unsupported in fake'));

  @override
  Future<Result<void>> stop() async {
    stopCalls++;
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> setSpeedMultiplier(double multiplier) async {
    speeds.add(multiplier);
    return const Ok<void>(null);
  }

  @override
  Future<Result<String>> synthesiseToFile(
    String text, {
    required String localeId,
    required String filePath,
  }) async {
    if (!canSynthesiseToFile) {
      return Err<String>(const AudioException('unsupported'));
    }
    synthesisedTo = filePath;
    return Ok<String>(filePath);
  }

  @override
  Future<void> dispose() async {
    await _events.close();
    await _progress.close();
  }
}

/// A clip player with no platform behind it.
class FakeClipPlayer implements ClipPlayer {
  final StreamController<void> _complete = StreamController<void>.broadcast();
  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _duration =
      StreamController<Duration>.broadcast();

  final List<String> played = <String>[];
  final List<double> rates = <double>[];
  int stopCalls = 0;

  @override
  Stream<void> get onComplete => _complete.stream;

  @override
  Stream<Duration> get onPosition => _position.stream;

  @override
  Stream<Duration> get onDuration => _duration.stream;

  @override
  Future<void> playFile(String path) async => played.add(path);

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> setRate(double rate) async => rates.add(rate);

  @override
  Future<void> dispose() async {
    await _complete.close();
    await _position.close();
    await _duration.close();
  }
}

void main() {
  final Lesson lesson = testLesson(id: 'a', title: 'Counting 1–10');
  final ClassroomSetup classroom = testClassroom();

  group('LocalLessonContentRepository', () {
    test('returns the plan from the provider and caches it', () async {
      final ScriptedAiContentService ai =
          ScriptedAiContentService(plan: testPlan());
      final InMemorySecureStorageService storage =
          InMemorySecureStorageService();
      final LocalLessonContentRepository repository =
          LocalLessonContentRepository(ai: ai, storage: storage);

      final PlanResult first = await repository.planFor(lesson, classroom);
      expect(first, isA<PlanLoaded>());
      expect(ai.generateCalls, 1);

      // A second repository over the same storage must not need the provider.
      final LocalLessonContentRepository reopened =
          LocalLessonContentRepository(ai: ai, storage: storage);
      final PlanResult second = await reopened.planFor(lesson, classroom);

      expect(second, isA<PlanLoaded>());
      expect((second as PlanLoaded).fromCache, isTrue);
      expect(ai.generateCalls, 1);
    });

    test('reports missing content rather than inventing a plan', () async {
      final LocalLessonContentRepository repository =
          LocalLessonContentRepository(
        ai: ScriptedAiContentService(),
        storage: InMemorySecureStorageService(),
      );

      final PlanResult result = await repository.planFor(lesson, classroom);

      expect(result, isA<PlanUnavailable>());
      expect(
        (result as PlanUnavailable).message,
        "Lesson content isn't available for this lesson yet.",
      );
    });
  });

  group('AiTranslationService', () {
    late InMemorySecureStorageService storage;
    late LessonPlan plan;

    setUp(() {
      storage = InMemorySecureStorageService();
      plan = testPlan();
    });

    test('a cached translation is returned without asking the provider',
        () async {
      final ScriptedAiContentService ai =
          ScriptedAiContentService(translation: testTranslation());
      final AiTranslationService service = AiTranslationService(
        ai: ai,
        storage: storage,
        connectivity: StaticConnectivityService(ConnectionStatus.online),
      );

      await service.translate(lesson: lesson, plan: plan, target: TargetLanguage.santali);
      expect(ai.translateCalls, 1);

      // A fresh service over the same storage reads what was saved.
      final AiTranslationService reopened = AiTranslationService(
        ai: ai,
        storage: storage,
        connectivity: StaticConnectivityService(ConnectionStatus.offline),
      );
      final TranslationOutcome second = await reopened.translate(
        lesson: lesson,
        plan: plan,
        target: TargetLanguage.santali,
      );

      expect(second, isA<TranslationReady>());
      expect((second as TranslationReady).fromCache, isTrue);
      expect(ai.translateCalls, 1);
    });

    test('a remote provider offline reports it, and asks nothing', () async {
      final ScriptedAiContentService ai = ScriptedAiContentService(
        hasProvider: true,
        translation: testTranslation(),
      );
      final AiTranslationService service = AiTranslationService(
        ai: ai,
        storage: storage,
        connectivity: StaticConnectivityService(ConnectionStatus.offline),
      );

      final TranslationOutcome outcome = await service.translate(
        lesson: lesson,
        plan: plan,
        target: TargetLanguage.santali,
      );

      expect(outcome, isA<TranslationNeedsConnection>());
      expect(ai.translateCalls, 0);
    });

    test('a local provider offline still answers', () async {
      final ScriptedAiContentService ai =
          ScriptedAiContentService(translation: testTranslation());
      final AiTranslationService service = AiTranslationService(
        ai: ai,
        storage: storage,
        connectivity: StaticConnectivityService(ConnectionStatus.offline),
      );

      final TranslationOutcome outcome = await service.translate(
        lesson: lesson,
        plan: plan,
        target: TargetLanguage.santali,
      );

      expect(outcome, isA<TranslationReady>());
    });

    test('a language with no translation says so and stores nothing', () async {
      final AiTranslationService service = AiTranslationService(
        ai: ScriptedAiContentService(),
        storage: storage,
        connectivity: StaticConnectivityService(ConnectionStatus.online),
      );

      final TranslationOutcome outcome = await service.translate(
        lesson: lesson,
        plan: plan,
        target: TargetLanguage.ho,
      );

      expect(outcome, isA<TranslationMissing>());
      expect(await service.cached(lesson.id, TargetLanguage.ho), isNull);
    });

    test('a thrown provider error becomes a plain message', () async {
      final AiTranslationService service = AiTranslationService(
        ai: ScriptedAiContentService(throwOnTranslate: true),
        storage: storage,
        connectivity: StaticConnectivityService(ConnectionStatus.online),
      );

      final TranslationOutcome outcome = await service.translate(
        lesson: lesson,
        plan: plan,
        target: TargetLanguage.santali,
      );

      expect(outcome, isA<TranslationFailed>());
      expect(
        (outcome as TranslationFailed).message,
        "Couldn't translate this lesson right now.",
      );
    });
  });

  group('TtsLessonAudioService', () {
    late FakeTts tts;
    late InMemoryAudioResourceStore store;
    late FakeClipPlayer player;
    late TtsLessonAudioService audio;

    const SpokenPassage santali = SpokenPassage(
      lessonId: 'a',
      label: 'Santali',
      displayText: "Johar gidra'ko!",
      localeId: 'sat',
      spokenText: 'जोहार गिड़ाको!',
      spokenScriptLocaleId: 'hi-IN',
    );

    const SpokenPassage hindi = SpokenPassage(
      lessonId: 'a',
      label: 'Hindi',
      displayText: 'बच्चों, आज हम गिनती सीखेंगे।',
      localeId: 'hi-IN',
    );

    setUp(() {
      tts = FakeTts();
      store = InMemoryAudioResourceStore();
      player = FakeClipPlayer();
      audio = TtsLessonAudioService(
        tts: tts,
        store: store,
        player: player,
        connectivity: StaticConnectivityService(ConnectionStatus.online),
      );
      addTearDown(audio.dispose);
    });

    test('a language the engine knows gets its own voice', () async {
      final AudioAvailability result = await audio.availability(hindi);
      expect(result.kind, AudioVoiceKind.nativeVoice);
      expect(result.canPlay, isTrue);
    });

    test('a language with no voice falls back to the Devanagari form', () async {
      final AudioAvailability result = await audio.availability(santali);

      expect(result.kind, AudioVoiceKind.approximateVoice);
      expect(result.note, contains('Approximate voice'));
    });

    test('the approximate voice speaks the Devanagari, not the Latin', () async {
      await audio.play(santali);

      expect(tts.spoken.single, 'जोहार गिड़ाको!');
      expect(tts.locales.single, 'hi-IN');
    });

    test('no voice and no Devanagari form means no playback', () async {
      const SpokenPassage bare = SpokenPassage(
        lessonId: 'a',
        label: 'Ho',
        displayText: 'Johar!',
        localeId: 'hoc',
      );

      final AudioAvailability result = await audio.availability(bare);
      expect(result.kind, AudioVoiceKind.none);

      final AudioRequestOutcome outcome = await audio.play(bare);
      expect(outcome, isA<AudioBlocked>());
      expect(tts.spoken, isEmpty);
    });

    test('a saved clip is preferred over the engine', () async {
      await store.save(AudioResourceStub('a', 'sat').resource);

      final AudioAvailability result = await audio.availability(santali);
      expect(result.kind, AudioVoiceKind.savedClip);
      expect(result.saved, isTrue);

      await audio.play(santali);
      expect(player.played.single, '/tmp/a-sat.wav');
      expect(tts.spoken, isEmpty);
    });

    test('the speed multiplier reaches the engine', () async {
      await audio.setSpeed(AudioSpeed.slow);
      await audio.play(hindi);

      expect(tts.speeds, contains(0.75));
      expect(audio.speed, AudioSpeed.slow);
    });

    test('repeat stops before it starts again', () async {
      await audio.play(hindi);
      final int stopsBefore = tts.stopCalls;

      await audio.repeat(hindi);

      expect(tts.stopCalls, greaterThan(stopsBefore));
      expect(tts.spoken.length, 2);
    });

    test('an engine failure is reported, not swallowed', () async {
      tts.speakFails = true;

      final AudioRequestOutcome outcome = await audio.play(hindi);

      expect(outcome, isA<AudioFailed>());
      expect(audio.state, PlaybackState.error);
    });

    test('saving on a platform that cannot write a file is refused', () async {
      tts.canSynthesiseToFile = false;

      final SaveAudioOutcome outcome = await audio.save(santali);

      expect(outcome, isA<SaveBlocked>());
      expect(await store.find('a', 'sat'), isNull);
    });

    test('an already-saved clip is not written twice', () async {
      await store.save(AudioResourceStub('a', 'sat').resource);

      final SaveAudioOutcome outcome = await audio.save(santali);

      expect(outcome, isA<AudioAlreadySaved>());
      expect(tts.synthesisedTo, isNull);
    });

    test('an engine completion is reported as completed', () async {
      final List<PlaybackState> seen = <PlaybackState>[];
      final StreamSubscription<PlaybackState> subscription =
          audio.states.listen(seen.add);

      await audio.play(hindi);
      await audio.stop();
      // Stream delivery is asynchronous; let the queued events land before the
      // subscription is torn down.
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(seen, contains(PlaybackState.playing));
      expect(seen.last, PlaybackState.idle);
    });
  });

  group('DevelopmentAiContentService', () {
    test('never claims to have a provider', () {
      expect(DevelopmentAiContentService().hasProvider, isFalse);
    });

    test('refuses generation rather than returning invented content', () async {
      final AiContentResult<QuickAssessment> result =
          await DevelopmentAiContentService().generateAssessment(
        lesson: lesson,
        classroom: classroom,
      );

      expect(result, isA<AiContentUnavailable<QuickAssessment>>());
    });

    test('serves only the curated translations it actually has', () async {
      final DevelopmentAiContentService ai = DevelopmentAiContentService();
      final LessonPlan plan = testPlan(lessonId: 'c1-num-counting-1-10');

      final AiContentResult<LessonTranslation> known = await ai.translateLesson(
        lesson: testLesson(
          id: 'c1-num-counting-1-10',
          title: 'Counting 1–10',
        ),
        plan: plan,
        target: TargetLanguage.santali,
      );
      expect(known, isA<AiContent<LessonTranslation>>());

      final AiContentResult<LessonTranslation> unknown =
          await ai.translateLesson(
        lesson: testLesson(id: 'nothing', title: 'Nothing'),
        plan: plan,
        target: TargetLanguage.santali,
      );
      expect(unknown, isA<AiContentUnavailable<LessonTranslation>>());
    });

    test('curated content reports itself as authored, never as AI', () {
      final LessonPlan? plan =
          DevelopmentAiContentService().curatedPlan('c1-num-counting-1-10');

      expect(plan, isNotNull);
      expect(plan!.provenance, ContentProvenance.authored);
      expect(plan.provenance.involvesAi, isFalse);
    });

    test('curated translations are marked as unreviewed', () async {
      final AiContentResult<LessonTranslation> result =
          await DevelopmentAiContentService().translateLesson(
        lesson: testLesson(id: 'c1-num-counting-1-10', title: 'Counting 1–10'),
        plan: testPlan(lessonId: 'c1-num-counting-1-10'),
        target: TargetLanguage.santali,
      );

      final LessonTranslation translation =
          (result as AiContent<LessonTranslation>).value;
      expect(translation.reviewedBySpeaker, isFalse);
      expect(translation.spokenText, isNotNull);
    });
  });
}
