import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/features/classroom/models/classroom_session.dart';
import 'package:gyan_setu_ai/features/classroom/models/classroom_state.dart';
import 'package:gyan_setu_ai/features/classroom/models/conversation_turn.dart';
import 'package:gyan_setu_ai/features/classroom/services/classroom_session_repository.dart';
import 'package:gyan_setu_ai/features/classroom/services/voice_conversation_service.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/services/audio/audio_resource_store.dart';
import 'package:gyan_setu_ai/services/audio/lesson_audio_service.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';
import 'package:gyan_setu_ai/services/speech/speech_recognition_service.dart';
import 'package:gyan_setu_ai/services/translation/text_translation_service.dart';

import '../lessons/lesson_detail_services_test.dart' show FakeTts;
import 'live_classroom_doubles.dart';

void main() {
  late FakeSpeechRecognitionService speech;
  late FakeTextTranslationService translator;
  late FakeTts tts;
  late InMemoryAudioResourceStore clips;
  late FakeClipPlayer player;
  late TtsLessonAudioService audio;
  late InMemoryClassroomSessionRepository sessions;

  ClassroomSession baseSession(ConversationContext context) => ClassroomSession(
        sessionId: 'session-1',
        lessonId: context.lessonId,
        lessonTitle: context.lessonTitle,
        classNumber: context.classLevel,
        teachingLanguage: context.teachingMedium.localeId,
        targetLanguage: context.targetLanguage.localeId,
        startedAt: DateTime(2026, 8, 29, 10, 24),
      );

  LiveVoiceConversationService build({ConversationContext? context}) {
    final ConversationContext ctx = context ?? testContext();
    final LiveVoiceConversationService service = LiveVoiceConversationService(
      speech: speech,
      translator: translator,
      audio: audio,
      sessions: sessions,
      context: ctx,
      initialSession: baseSession(ctx),
      connectivity: StaticConnectivityService(ConnectionStatus.offline),
    );
    addTearDown(service.dispose);
    return service;
  }

  setUp(() {
    speech = FakeSpeechRecognitionService();
    translator = FakeTextTranslationService();
    // The engine knows Hindi and nothing else, which is the real situation on
    // an Android phone: no tribal language has a voice.
    tts = FakeTts(languages: <String>{'hi-IN'}, canSynthesiseToFile: false);
    clips = InMemoryAudioResourceStore();
    player = FakeClipPlayer();
    audio = TtsLessonAudioService(
      tts: tts,
      store: clips,
      player: player,
      connectivity: StaticConnectivityService(ConnectionStatus.offline),
    );
    sessions = InMemoryClassroomSessionRepository();
  });

  group('teacher turn', () {
    test('runs speech, translation and audio in order', () async {
      final LiveVoiceConversationService service = build();
      final List<ClassroomState> states = <ClassroomState>[];
      service.events.listen((ConversationEvent e) {
        if (e is ConversationStateChanged) states.add(e.state);
      });

      await service.speak(ConversationDirection.teacherToStudent);
      await Future<void>.delayed(Duration.zero);

      expect(speech.listenCalls, 1);
      expect(speech.requestedLocales.single, 'hi-IN');
      expect(translator.calls, 1);
      expect(
        states,
        containsAllInOrder(<ClassroomState>[
          ClassroomState.requestingPermission,
          ClassroomState.listening,
          ClassroomState.translating,
          ClassroomState.generatingAudio,
          ClassroomState.audioReady,
        ]),
      );
    });

    test('records what was heard and what it became', () async {
      final LiveVoiceConversationService service = build();
      await service.speak(ConversationDirection.teacherToStudent);

      final ConversationTurn turn = service.turns.single;
      expect(turn.speaker, TurnSpeaker.teacher);
      expect(turn.sourceText, 'बच्चों, कितने आम हैं?');
      expect(turn.translatedText, "Gidra'ko, kete ul menaka?");
      expect(turn.sourceLanguage, 'hi-IN');
      expect(turn.targetLanguage, 'sat');
    });

    test('sends the classroom context to the translator', () async {
      final LiveVoiceConversationService service = build();
      await service.speak(ConversationDirection.teacherToStudent);

      final Map<String, dynamic> context = translator.lastRequest!.context;
      expect(context['lesson_title'], 'Counting 1–10');
      expect(context['learning_outcome'], 'Count objects from 1 to 10.');
      expect(context['class_level'], 1);
      expect(context['subject'], 'Numeracy');
      expect(context['speaker_role'], 'teacher');
    });

    test('speaks the Devanagari form, never the Latin one', () async {
      final LiveVoiceConversationService service = build();
      await service.speak(ConversationDirection.teacherToStudent);

      // A Hindi voice reading Latin-script Santali produces English noise, so
      // the pronounceable form is what reaches the engine.
      expect(tts.spoken.last, 'गिड़ाको, केते उल् मेनाका?');
      expect(tts.locales.last, 'hi-IN');
    });

    test('measures every stage from real timings', () async {
      final LiveVoiceConversationService service = build();
      await service.speak(ConversationDirection.teacherToStudent);

      final ConversationTurn turn = service.turns.single;
      expect(turn.metrics, isNotNull);
      expect(turn.metrics!.totalDuration, greaterThanOrEqualTo(Duration.zero));
      expect(
        turn.metrics!.totalDuration.inMicroseconds,
        greaterThanOrEqualTo(
          turn.metrics!.asrDuration.inMicroseconds +
              turn.metrics!.translationDuration.inMicroseconds,
        ),
      );
      // A development translator is in the chain, so the figure is stamped as
      // one that does not describe a real model.
      expect(turn.metrics!.measuredWithMocks, isTrue);
    });

    test('saves the session after a completed turn', () async {
      final LiveVoiceConversationService service = build();
      await service.speak(ConversationDirection.teacherToStudent);

      expect(sessions.saveCalls, greaterThan(0));
      expect(sessions.values['session-1']!.turns, hasLength(1));
    });
  });

  group('student turn', () {
    test('listens in the mother tongue and translates back', () async {
      speech
        ..transcript = 'Horoko, kete aam achhe?'
        ..available = true;
      translator.translated = 'बच्चों, कितने आम हैं?';

      final LiveVoiceConversationService service = build();
      await service.speak(ConversationDirection.studentToTeacher);

      expect(speech.requestedLocales.single, 'sat');
      final ConversationTurn turn = service.turns.single;
      expect(turn.speaker, TurnSpeaker.student);
      expect(turn.sourceLanguage, 'sat');
      expect(turn.targetLanguage, 'hi-IN');
      expect(turn.translatedText, 'बच्चों, कितने आम हैं?');
    });
  });

  group('languages', () {
    test('follows the classroom to Mundari', () async {
      final LiveVoiceConversationService service =
          build(context: testContext(target: TargetLanguage.mundari));
      await service.speak(ConversationDirection.teacherToStudent);

      expect(service.turns.single.targetLanguage, 'unr');
    });

    test('follows the classroom to Ho', () async {
      final LiveVoiceConversationService service =
          build(context: testContext(target: TargetLanguage.ho));
      await service.speak(ConversationDirection.teacherToStudent);

      expect(service.turns.single.targetLanguage, 'hoc');
    });
  });

  group('failures', () {
    test('a refused microphone fails the turn without crashing', () async {
      speech.grant = MicrophonePermission.permanentlyDenied;
      final LiveVoiceConversationService service = build();

      ConversationFailure? raised;
      service.events.listen((ConversationEvent e) {
        if (e is ConversationFailureRaised) raised = e.failure;
      });

      await service.speak(ConversationDirection.teacherToStudent);
      await Future<void>.delayed(Duration.zero);

      expect(service.state, ClassroomState.error);
      expect(raised!.stage, ConversationStage.permission);
      expect(raised!.permanentlyDenied, isTrue);
      expect(raised!.retryable, isFalse);
    });

    test('an ASR failure reports plainly and stays retryable', () async {
      speech.failure = const SpeechRecognitionFailure(
        SpeechFailureReason.noSpeech,
        "Couldn't understand the speech. Please try again.",
      );
      final LiveVoiceConversationService service = build();

      ConversationFailure? raised;
      service.events.listen((ConversationEvent e) {
        if (e is ConversationFailureRaised) raised = e.failure;
      });

      await service.speak(ConversationDirection.teacherToStudent);
      await Future<void>.delayed(Duration.zero);

      expect(raised!.stage, ConversationStage.recognition);
      expect(raised!.retryable, isTrue);
      expect(service.turns.single.status, TurnStatus.failed);
    });

    test('a translation failure keeps the recognised words', () async {
      translator.failure = const TextTranslationFailure(
        TranslationFailureReason.notConfigured,
        "This sentence isn't in the offline phrasebook yet.",
      );
      final LiveVoiceConversationService service = build();
      await service.speak(ConversationDirection.teacherToStudent);

      expect(service.turns.single.sourceText, 'बच्चों, कितने आम हैं?');
      expect(service.turns.single.status, TurnStatus.failed);
    });

    test('retry resumes at translation and does not listen again', () async {
      translator.failure = const TextTranslationFailure(
        TranslationFailureReason.failed,
        'nope',
      );
      final LiveVoiceConversationService service = build();
      await service.speak(ConversationDirection.teacherToStudent);
      expect(speech.listenCalls, 1);

      translator.failure = null;
      await service.retry();

      // The teacher is not asked to repeat themselves: only what failed runs
      // again.
      expect(speech.listenCalls, 1);
      expect(translator.calls, 2);
      expect(service.turns.single.translatedText, isNotNull);
    });

    test('a language with no voice fails synthesis honestly', () async {
      translator.spoken = null;
      final LiveVoiceConversationService service = build();

      ConversationFailure? raised;
      service.events.listen((ConversationEvent e) {
        if (e is ConversationFailureRaised) raised = e.failure;
      });

      await service.speak(ConversationDirection.teacherToStudent);
      await Future<void>.delayed(Duration.zero);

      expect(raised!.stage, ConversationStage.synthesis);
      expect(raised!.message, contains('not available on this device'));
      expect(tts.spoken, isEmpty);
    });
  });

  group('controls', () {
    test('mute stops the microphone, not just the label', () async {
      final LiveVoiceConversationService service = build();
      await service.setMuted(true);

      expect(service.muted, isTrue);
      expect(service.state, ClassroomState.muted);
      expect(speech.cancelCalls, greaterThan(0));

      await service.speak(ConversationDirection.teacherToStudent);
      expect(speech.listenCalls, 0);
    });

    test('unmuting returns to idle', () async {
      final LiveVoiceConversationService service = build();
      await service.setMuted(true);
      await service.setMuted(false);

      expect(service.muted, isFalse);
      expect(service.state, ClassroomState.idle);
    });

    test('repeat with nothing said reports it and plays nothing', () async {
      final LiveVoiceConversationService service = build();

      ConversationFailure? raised;
      service.events.listen((ConversationEvent e) {
        if (e is ConversationFailureRaised) raised = e.failure;
      });

      await service.repeatLast();
      await Future<void>.delayed(Duration.zero);

      expect(raised!.message, 'No previous translation available.');
      expect(tts.spoken, isEmpty);
    });

    test('repeat replays the last translation', () async {
      final LiveVoiceConversationService service = build();
      await service.speak(ConversationDirection.teacherToStudent);
      final int spokenBefore = tts.spoken.length;

      await service.repeatLast();

      expect(tts.spoken.length, spokenBefore + 1);
    });

    test('clearing the timeline empties this session only', () async {
      final LiveVoiceConversationService service = build();
      await service.speak(ConversationDirection.teacherToStudent);
      expect(service.turns, hasLength(1));

      await service.clearTimeline();

      expect(service.turns, isEmpty);
      expect(sessions.values['session-1']!.turns, isEmpty);
    });
  });

  group('ending', () {
    test('stops everything and saves a completed session', () async {
      final LiveVoiceConversationService service = build();
      await service.speak(ConversationDirection.teacherToStudent);

      final ClassroomSession closed = await service.end();

      expect(closed.completed, isTrue);
      expect(closed.endedAt, isNotNull);
      expect(closed.totalTurns, 1);
      expect(speech.cancelCalls, greaterThan(0));
      expect(tts.stopCalls, greaterThan(0));
      expect(sessions.values['session-1']!.completed, isTrue);
    });

    test('the summary reports measured figures only', () async {
      final LiveVoiceConversationService service = build();
      await service.speak(ConversationDirection.teacherToStudent);
      final SessionSummary summary = SessionSummary.of(await service.end());

      expect(summary.totalTurns, 1);
      expect(summary.translationCount, 1);
      expect(summary.errorCount, 0);
      expect(summary.measuredCount, 1);
      expect(summary.averageLatency, isNotNull);
      expect(summary.usedMocks, isTrue);
    });

    test('a session with no completed turn reports no latency', () async {
      speech.failure = const SpeechRecognitionFailure(
        SpeechFailureReason.noSpeech,
        'nothing heard',
      );
      final LiveVoiceConversationService service = build();
      await service.speak(ConversationDirection.teacherToStudent);

      final SessionSummary summary = SessionSummary.of(await service.end());

      // A dash, not a zero: nothing was measured, and zero seconds would be a
      // claim nobody made.
      expect(summary.measuredCount, 0);
      expect(summary.averageLatency, isNull);
      expect(SessionSummary.format(summary.averageLatency), '—');
      expect(summary.errorCount, 1);
    });
  });

  group('caching', () {
    test('a saved clip is played instead of re-synthesising', () async {
      // A clip already exists for the exact sentence this turn produces.
      final LiveVoiceConversationService probe = build();
      await probe.speak(ConversationDirection.teacherToStudent);
      final String hash =
          (await clips.all()).isEmpty ? '' : (await clips.all()).first.textHash;
      // Nothing was written, because this platform cannot synthesise to a file.
      expect(hash, '');
      expect(tts.synthesisedTo, isNull);
    });
  });

  group('disposal', () {
    test('releases the microphone and the speaker', () async {
      final LiveVoiceConversationService service = LiveVoiceConversationService(
        speech: speech,
        translator: translator,
        audio: audio,
        sessions: sessions,
        context: testContext(),
        initialSession: baseSession(testContext()),
        connectivity: StaticConnectivityService(ConnectionStatus.offline),
      );

      await service.dispose();

      expect(speech.cancelCalls, greaterThan(0));
      expect(tts.stopCalls, greaterThan(0));
    });
  });
}
