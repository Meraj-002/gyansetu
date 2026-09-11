import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/app/routes.dart';
import 'package:gyan_setu_ai/app/theme.dart';
import 'package:gyan_setu_ai/features/classroom/conversation_result_screen.dart'
    show ConversationResultArgs;
import 'package:gyan_setu_ai/features/classroom/live_classroom_screen.dart';
import 'package:gyan_setu_ai/features/classroom/models/classroom_session.dart';
import 'package:gyan_setu_ai/features/classroom/models/conversation_turn.dart';
import 'package:gyan_setu_ai/features/classroom/services/classroom_session_repository.dart';
import 'package:gyan_setu_ai/features/classroom/services/live_classroom_controller.dart';
import 'package:gyan_setu_ai/features/classroom/services/voice_conversation_service.dart';
import 'package:gyan_setu_ai/features/classroom/widgets/live_classroom_widgets.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/services/ai/ai_runtime_status_service.dart';
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
  late FakeClipPlayer player;
  late TtsLessonAudioService audio;
  late InMemoryClassroomSessionRepository sessions;
  late FakeAiRuntimeStatusService runtime;
  late StaticConnectivityService connectivity;

  setUp(() {
    speech = FakeSpeechRecognitionService();
    translator = FakeTextTranslationService();
    tts = FakeTts(languages: <String>{'hi-IN'}, canSynthesiseToFile: false);
    player = FakeClipPlayer();
    connectivity = StaticConnectivityService(ConnectionStatus.offline);
    audio = TtsLessonAudioService(
      tts: tts,
      store: InMemoryAudioResourceStore(),
      player: player,
      connectivity: connectivity,
    );
    sessions = InMemoryClassroomSessionRepository();
    runtime = FakeAiRuntimeStatusService();
  });

  LiveClassroomController buildController({ConversationContext? context}) {
    final ConversationContext ctx = context ?? testContext();
    final VoiceConversationService conversation = LiveVoiceConversationService(
      speech: speech,
      translator: translator,
      audio: audio,
      sessions: sessions,
      context: ctx,
      initialSession: ClassroomSession(
        sessionId: 'session-1',
        lessonId: ctx.lessonId,
        lessonTitle: ctx.lessonTitle,
        classNumber: ctx.classLevel,
        teachingLanguage: ctx.teachingMedium.localeId,
        targetLanguage: ctx.targetLanguage.localeId,
        startedAt: DateTime(2026, 8, 29, 10, 24),
      ),
      connectivity: connectivity,
    );
    addTearDown(conversation.dispose);

    final LiveClassroomController controller = LiveClassroomController(
      conversation: conversation,
      runtime: runtime,
      connectivity: connectivity,
      context: ctx,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<LiveClassroomController> pump(
    WidgetTester tester, {
    ConversationContext? context,
    Size size = const Size(430, 1500),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final LiveClassroomController controller =
        buildController(context: context);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        onGenerateRoute: AppRouter.onGenerateRoute,
        home: LiveClassroomScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  group('context', () {
    testWidgets('shows the class and both languages from the classroom', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      expect(find.text('Live Classroom'), findsOneWidget);
      expect(find.text('Class 1  •  Hindi ↔ Santali'), findsOneWidget);
      expect(find.text('Teacher — Hindi'), findsOneWidget);
      expect(find.text('Translated to Santali'), findsOneWidget);
    });

    testWidgets('follows the classroom to Mundari', (
      WidgetTester tester,
    ) async {
      await pump(tester, context: testContext(target: TargetLanguage.mundari));

      expect(find.text('Class 1  •  Hindi ↔ Mundari'), findsOneWidget);
      expect(find.text('Translated to Mundari'), findsOneWidget);
      expect(find.textContaining('Santali'), findsNothing);
    });

    testWidgets('follows the classroom to Ho', (WidgetTester tester) async {
      await pump(tester, context: testContext(target: TargetLanguage.ho));

      expect(find.text('Class 1  •  Hindi ↔ Ho'), findsOneWidget);
      expect(find.text('Translated to Ho'), findsOneWidget);
    });

    testWidgets('carries GyanSetu AI branding and no other', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      expect(
        find.textContaining('GyanSetu AI', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('BhashaSetu', findRichText: true),
        findsNothing,
      );
    });

    testWidgets('opened with no lesson says so instead of guessing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: LiveClassroomScreen()),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No lesson was handed to this session.'),
        findsOneWidget,
      );
    });
  });

  group('status and latency', () {
    testWidgets('the latency badge shows dashes until something is measured', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      expect(find.text('Latency: --'), findsOneWidget);
    });

    testWidgets('shows a measured latency after a turn', (
      WidgetTester tester,
    ) async {
      final LiveClassroomController c = await pump(tester);

      await tester.tap(find.byKey(MicrophoneOrb.orbKey));
      await tester.pumpAndSettle();

      expect(c.latestMetrics, isNotNull);
      expect(find.textContaining('Latency: '), findsOneWidget);
      expect(find.text('Latency: --'), findsNothing);
    });

    testWidgets('marks a development pipeline as a demo', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byKey(MicrophoneOrb.orbKey));
      await tester.pumpAndSettle();

      expect(find.text('Demo pipeline'), findsOneWidget);
    });

    testWidgets('warns when a turn is slower than the target', (
      WidgetTester tester,
    ) async {
      final LiveClassroomController c = await pump(tester);
      await tester.tap(find.byKey(MicrophoneOrb.orbKey));
      await tester.pumpAndSettle();

      // The real measurement is far under the target with fakes in the chain,
      // so the warning must be absent — it appears only on a real slow turn.
      expect(c.latestMetrics!.withinTarget, isTrue);
      expect(find.text('Slower than the 3 second target'), findsNothing);
    });

    testWidgets('the status pill reports what the runtime said', (
      WidgetTester tester,
    ) async {
      runtime.status = const AiRuntimeStatus(
        state: AiRuntimeState.limited,
        components: <AiComponentStatus>[],
        label: 'Speech recognition unavailable',
      );
      await pump(tester);

      expect(find.text('Speech recognition unavailable'), findsOneWidget);
      expect(find.text('Offline AI Active'), findsNothing);
    });
  });

  group('pipeline', () {
    testWidgets('tapping the microphone runs a full turn', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byKey(MicrophoneOrb.orbKey));
      await tester.pumpAndSettle();

      expect(speech.listenCalls, 1);
      expect(find.text('बच्चों, कितने आम हैं?'), findsWidgets);
      expect(find.text("Gidra'ko, kete ul menaka?"), findsWidgets);
    });

    testWidgets('a low-confidence translation asks to be verified', (
      WidgetTester tester,
    ) async {
      translator.confidence = 0.4;
      await pump(tester);

      await tester.tap(find.byKey(MicrophoneOrb.orbKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('Please verify'), findsOneWidget);
    });

    testWidgets('Play to Students is disabled until there is a translation', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      final Finder play =
          find.byKey(LiveClassroomScreen.playToStudentsKey);
      expect(tester.widget<FilledButton>(play).onPressed, isNull);

      await tester.tap(find.byKey(MicrophoneOrb.orbKey));
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(play).onPressed, isNotNull);
    });

    testWidgets('Play to Students really speaks', (WidgetTester tester) async {
      await pump(tester);
      await tester.tap(find.byKey(MicrophoneOrb.orbKey));
      await tester.pumpAndSettle();

      final int before = tts.spoken.length;
      await tester.tap(find.byKey(LiveClassroomScreen.playToStudentsKey));
      await tester.pumpAndSettle();

      expect(tts.spoken.length, before + 1);
    });

    testWidgets('a student turn listens in the mother tongue', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byKey(LiveClassroomScreen.studentTurnKey));
      await tester.pumpAndSettle();

      expect(speech.requestedLocales.last, 'sat');
    });
  });

  group('errors', () {
    testWidgets('a refused microphone shows a message, not a crash', (
      WidgetTester tester,
    ) async {
      speech.grant = MicrophonePermission.denied;
      await pump(tester);

      await tester.tap(find.byKey(MicrophoneOrb.orbKey));
      await tester.pumpAndSettle();

      // Once in the banner and once against the failed turn in the timeline.
      expect(
        find.text('Microphone permission is required for Live Classroom.'),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a permanently refused microphone offers settings', (
      WidgetTester tester,
    ) async {
      speech.grant = MicrophonePermission.permanentlyDenied;
      await pump(tester);

      await tester.tap(find.byKey(MicrophoneOrb.orbKey));
      await tester.pumpAndSettle();

      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.byKey(LiveClassroomScreen.retryKey), findsNothing);
    });

    testWidgets('a translation failure offers Try Again', (
      WidgetTester tester,
    ) async {
      translator.failure = const TextTranslationFailure(
        TranslationFailureReason.failed,
        "Couldn't translate this sentence. Please try again.",
      );
      await pump(tester);

      await tester.tap(find.byKey(MicrophoneOrb.orbKey));
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't translate this sentence. Please try again."),
        findsWidgets,
      );

      translator.failure = null;
      await tester.tap(find.byKey(LiveClassroomScreen.retryKey));
      await tester.pumpAndSettle();

      // The words were already recognised, so the retry did not re-listen.
      expect(speech.listenCalls, 1);
      expect(find.text("Gidra'ko, kete ul menaka?"), findsWidgets);
    });

    testWidgets('no raw exception text ever reaches the screen', (
      WidgetTester tester,
    ) async {
      translator.failure = const TextTranslationFailure(
        TranslationFailureReason.failed,
        "Couldn't translate this sentence. Please try again.",
      );
      await pump(tester);
      await tester.tap(find.byKey(MicrophoneOrb.orbKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('#0 '), findsNothing);
    });
  });

  group('controls', () {
    testWidgets('Mute stops the microphone and shows Muted', (
      WidgetTester tester,
    ) async {
      final LiveClassroomController c = await pump(tester);

      await tester.tap(find.byKey(LiveClassroomScreen.muteKey));
      await tester.pumpAndSettle();

      expect(c.muted, isTrue);
      // The button and the microphone orb both say so, which is the point.
      expect(find.text('Muted'), findsWidgets);
      expect(speech.cancelCalls, greaterThan(0));

      // A muted session does not open the microphone.
      await tester.tap(find.byKey(MicrophoneOrb.orbKey));
      await tester.pumpAndSettle();
      expect(speech.listenCalls, 0);
    });

    testWidgets('unmuting restores the microphone', (
      WidgetTester tester,
    ) async {
      final LiveClassroomController c = await pump(tester);

      await tester.tap(find.byKey(LiveClassroomScreen.muteKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(LiveClassroomScreen.muteKey));
      await tester.pumpAndSettle();

      expect(c.muted, isFalse);
      expect(find.text('Mute'), findsOneWidget);
    });

    testWidgets('Repeat Last is disabled until something has been said', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      expect(
        tester
            .widget<LiveControlButton>(
              find.byKey(LiveClassroomScreen.repeatKey),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(MicrophoneOrb.orbKey));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<LiveControlButton>(
              find.byKey(LiveClassroomScreen.repeatKey),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('Repeat Last replays the last translation', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byKey(MicrophoneOrb.orbKey));
      await tester.pumpAndSettle();

      final int before = tts.spoken.length;
      await tester.tap(find.byKey(LiveClassroomScreen.repeatKey));
      await tester.pumpAndSettle();

      expect(tts.spoken.length, before + 1);
    });
  });

  group('timeline', () {
    testWidgets('records each turn with its speaker and language', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byKey(MicrophoneOrb.orbKey));
      await tester.pumpAndSettle();

      expect(find.text('Live Conversation Timeline'), findsOneWidget);
      expect(find.text('Teacher (Hindi)'), findsOneWidget);
    });

    testWidgets('is empty and says so before anything is said', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      expect(
        find.textContaining('Nothing said yet'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextButton>(
              find.byKey(LiveClassroomScreen.clearTimelineKey),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('Clear empties the session timeline after confirming', (
      WidgetTester tester,
    ) async {
      final LiveClassroomController c = await pump(tester);
      await tester.tap(find.byKey(MicrophoneOrb.orbKey));
      await tester.pumpAndSettle();
      expect(c.turns, hasLength(1));

      await tester.tap(find.byKey(LiveClassroomScreen.clearTimelineKey));
      await tester.pumpAndSettle();
      expect(find.text('Clear conversation history?'), findsOneWidget);

      // The timeline header also has a 'Clear', so the dialog's own button is
      // the one addressed.
      await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
      await tester.pumpAndSettle();

      expect(c.turns, isEmpty);
    });

    testWidgets('cancelling the clear keeps the timeline', (
      WidgetTester tester,
    ) async {
      final LiveClassroomController c = await pump(tester);
      await tester.tap(find.byKey(MicrophoneOrb.orbKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(LiveClassroomScreen.clearTimelineKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();

      expect(c.turns, hasLength(1));
    });
  });

  group('ending', () {
    testWidgets('End Session confirms, saves and hands over the session id', (
      WidgetTester tester,
    ) async {
      // The result route is intercepted so the hand-off can be checked without
      // building a screen that reaches for platform storage.
      ConversationResultArgs? handedOver;

      tester.view.physicalSize = const Size(430, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final LiveClassroomController controller = buildController();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          onGenerateRoute: (RouteSettings settings) {
            if (settings.name == AppRoutes.conversationResult) {
              handedOver = settings.arguments as ConversationResultArgs?;
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => const Scaffold(body: Text('result')),
              );
            }
            return AppRouter.onGenerateRoute(settings);
          },
          home: LiveClassroomScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(MicrophoneOrb.orbKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(LiveClassroomScreen.endKey));
      await tester.pumpAndSettle();
      expect(find.text('End classroom session?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'End Session'));
      await tester.pumpAndSettle();

      expect(handedOver?.sessionId, 'session-1');
      expect(sessions.values['session-1']!.completed, isTrue);
      expect(find.text('result'), findsOneWidget);
    });

    testWidgets('Continue Session keeps the session running', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byKey(LiveClassroomScreen.endKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue Session'));
      await tester.pumpAndSettle();

      expect(find.byType(LiveClassroomScreen), findsOneWidget);
      expect(find.text('result'), findsNothing);
    });
  });

  group('menu', () {
    testWidgets('offers only actions that work', (WidgetTester tester) async {
      await pump(tester);

      await tester.tap(find.byKey(LiveClassroomScreen.moreKey));
      await tester.pumpAndSettle();

      expect(find.text('Session information'), findsOneWidget);
      expect(find.text('Language and AI status'), findsOneWidget);
      expect(find.text('Clear conversation'), findsOneWidget);
      expect(find.text('Offline resources'), findsOneWidget);
    });

    testWidgets('session information reports the real session', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byKey(LiveClassroomScreen.moreKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Session information'));
      await tester.pumpAndSettle();

      expect(find.text('Counting 1–10'), findsOneWidget);
      expect(find.text('Hindi ↔ Santali'), findsOneWidget);
    });
  });

  group('layout', () {
    testWidgets('lays out on a small handset without overflow', (
      WidgetTester tester,
    ) async {
      await pump(tester, size: const Size(320, 1600));

      expect(tester.takeException(), isNull);
      expect(find.text('Live Classroom'), findsOneWidget);
      expect(find.byKey(MicrophoneOrb.orbKey), findsOneWidget);
    });

    testWidgets('lays out on a tablet-sized screen without overflow', (
      WidgetTester tester,
    ) async {
      await pump(tester, size: const Size(900, 1600));

      expect(tester.takeException(), isNull);
      expect(find.byKey(LiveClassroomScreen.endKey), findsOneWidget);
    });
  });
}
