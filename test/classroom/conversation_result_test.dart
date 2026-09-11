import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/app/routes.dart';
import 'package:gyan_setu_ai/app/theme.dart';
import 'package:gyan_setu_ai/features/classroom/conversation_result_screen.dart';
import 'package:gyan_setu_ai/features/classroom/models/classroom_insights.dart';
import 'package:gyan_setu_ai/features/classroom/models/classroom_session.dart';
import 'package:gyan_setu_ai/features/classroom/models/conversation_turn.dart';
import 'package:gyan_setu_ai/features/classroom/models/voice_pipeline_metrics.dart';
import 'package:gyan_setu_ai/features/classroom/services/classroom_insight_service.dart';
import 'package:gyan_setu_ai/features/classroom/services/classroom_session_repository.dart';
import 'package:gyan_setu_ai/features/classroom/services/conversation_result_controller.dart';
import 'package:gyan_setu_ai/features/classroom/widgets/conversation_result_widgets.dart';
import 'package:gyan_setu_ai/features/lessons/lesson_navigation.dart';
import 'package:gyan_setu_ai/features/assessment/assessment_screen.dart'
    show AssessmentArgs;
import 'package:gyan_setu_ai/features/worksheet/worksheet_generator_screen.dart'
    show WorksheetGeneratorArgs;
import 'package:gyan_setu_ai/features/lessons/services/assessment_repository.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/models/lesson.dart';
import 'package:gyan_setu_ai/models/lesson_plan.dart';
import 'package:gyan_setu_ai/services/audio/audio_resource_store.dart';
import 'package:gyan_setu_ai/services/audio/lesson_audio_service.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';
import 'package:gyan_setu_ai/services/translation/text_translation_service.dart';

import '../lessons/lesson_detail_doubles.dart';
import '../lessons/lesson_detail_services_test.dart' show FakeTts;
import '../lessons/lesson_test_doubles.dart';
import 'live_classroom_doubles.dart';

/// The label a bottom action is currently showing.
String _actionLabel(WidgetTester tester, Key key) =>
    tester.widget<ResultAction>(find.byKey(key)).label;

/// Scrolls a bottom-of-page control into view before tapping it.
Future<void> _reveal(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    300,
    // The key sits on the ListView; scrollUntilVisible needs the Scrollable
    // inside it.
    scrollable: find.descendant(
      of: find.byKey(ConversationResultScreen.scrollKey),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const String sessionId = 'CLS-290826-1024';
  final DateTime startedAt = DateTime(2026, 8, 29, 10, 24);

  late InMemoryClassroomSessionRepository sessions;
  late FakeLessonRepository lessons;
  late FakeContentRepository content;
  late FakeProgressRepository progress;
  late InMemoryAssessmentRepository assessments;
  late LocalRuleBasedInsightService insights;
  late FakeTts tts;
  late InMemoryAudioResourceStore clips;
  late FakeClipPlayer player;
  late TtsLessonAudioService audio;
  late StaticConnectivityService connectivity;

  Lesson countingLesson() => Lesson(
        id: 'c1-num-counting-1-10',
        title: 'Counting 1–10',
        description: 'Count everyday objects aloud.',
        subject: ClassroomSubject.numeracy,
        classNumber: 1,
        learningOutcome: 'Count objects from 1 to 10.',
        durationMinutes: 10,
        lessonOrder: 1,
        createdAt: startedAt,
        updatedAt: startedAt,
        concepts: const <String>[
          'Counting 1–10',
          'Number Sequence',
          'After, Before, Between',
        ],
      );

  ConversationTurn teacherTurn({
    String id = 'turn-1',
    int second = 23,
    double? confidence = 0.95,
    Duration latency = const Duration(milliseconds: 1700),
    TurnStatus status = TurnStatus.played,
    bool offline = true,
  }) =>
      ConversationTurn(
        id: id,
        sessionId: sessionId,
        speaker: TurnSpeaker.teacher,
        sourceLanguage: 'hi-IN',
        targetLanguage: 'sat',
        timestamp: startedAt.add(Duration(seconds: second)),
        status: status,
        sourceText: 'गिनती में 5 के बाद क्या आता है?',
        translatedText: 'Pisa re 5 ko lagid kana aschey?',
        translatedSpokenText: 'पिसा रे 5 को लागिद काना असेय?',
        confidence: confidence,
        wasOffline: offline,
        metrics: VoicePipelineMetrics(
          asrDuration: const Duration(milliseconds: 600),
          translationDuration: const Duration(milliseconds: 700),
          ttsDuration: const Duration(milliseconds: 400),
          totalDuration: latency,
          timestamp: startedAt.add(Duration(seconds: second)),
        ),
      );

  ConversationTurn studentTurn({bool offline = true}) => ConversationTurn(
        id: 'turn-2',
        sessionId: sessionId,
        speaker: TurnSpeaker.student,
        sourceLanguage: 'sat',
        targetLanguage: 'hi-IN',
        timestamp: startedAt.add(const Duration(seconds: 30)),
        status: TurnStatus.played,
        sourceText: 'Pisa re 5 ko lagid 6 aschey.',
        translatedText: '5 के बाद 6 आता है।',
        confidence: 0.88,
        wasOffline: offline,
        metrics: VoicePipelineMetrics(
          asrDuration: const Duration(milliseconds: 500),
          translationDuration: const Duration(milliseconds: 600),
          ttsDuration: const Duration(milliseconds: 400),
          totalDuration: const Duration(milliseconds: 1500),
          timestamp: startedAt.add(const Duration(seconds: 30)),
        ),
      );

  ClassroomSession session({
    List<ConversationTurn>? turns,
    DateTime? endedAt,
    DateTime? savedAt,
    TargetLanguage target = TargetLanguage.santali,
    int classNumber = 1,
  }) =>
      ClassroomSession(
        sessionId: sessionId,
        lessonId: 'c1-num-counting-1-10',
        lessonTitle: 'Counting 1–10',
        classNumber: classNumber,
        subject: ClassroomSubject.numeracy,
        teachingLanguage: 'hi-IN',
        targetLanguage: target.localeId,
        startedAt: startedAt,
        endedAt: endedAt ?? startedAt.add(const Duration(minutes: 8, seconds: 42)),
        completed: true,
        savedAt: savedAt,
        turns: turns ?? <ConversationTurn>[teacherTurn(), studentTurn()],
      );

  setUp(() {
    sessions = InMemoryClassroomSessionRepository();
    lessons = FakeLessonRepository(catalogue: <Lesson>[countingLesson()]);
    content = FakeContentRepository(
      plan: testPlan(lessonId: 'c1-num-counting-1-10'),
    );
    progress = FakeProgressRepository();
    assessments = InMemoryAssessmentRepository();
    insights = LocalRuleBasedInsightService(InMemorySecureStorageService());
    tts = FakeTts(languages: <String>{'hi-IN'}, canSynthesiseToFile: false);
    clips = InMemoryAudioResourceStore();
    player = FakeClipPlayer();
    connectivity = StaticConnectivityService(ConnectionStatus.offline);
    audio = TtsLessonAudioService(
      tts: tts,
      store: clips,
      player: player,
      connectivity: connectivity,
    );
  });

  ConversationResultController buildController({String id = sessionId}) {
    final ConversationResultController controller =
        ConversationResultController(
      sessionId: id,
      sessions: sessions,
      insights: insights,
      lessons: lessons,
      content: content,
      progress: progress,
      assessments: assessments,
      audio: audio,
      connectivity: connectivity,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<ConversationResultController> pump(
    WidgetTester tester, {
    String id = sessionId,
    Size size = const Size(430, 1600),
    RouteFactory? routes,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ConversationResultController controller = buildController(id: id);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        onGenerateRoute: routes ?? AppRouter.onGenerateRoute,
        home: ConversationResultScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  group('session data', () {
    testWidgets('loads the session named by the id it was given', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      final ConversationResultController c = await pump(tester);

      expect(c.session!.sessionId, sessionId);
      expect(c.session!.lessonId, 'c1-num-counting-1-10');
      expect(find.text('Session ID: $sessionId'), findsOneWidget);
    });

    testWidgets('shows the class and language pair from the session', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      await pump(tester);

      expect(find.text('Class 1  •  Hindi ↔ Santali'), findsOneWidget);
    });

    testWidgets('follows a session recorded in Mundari', (
      WidgetTester tester,
    ) async {
      await sessions.save(
        session(
          target: TargetLanguage.mundari,
          classNumber: 2,
          turns: const <ConversationTurn>[],
        ),
      );
      await pump(tester);

      expect(find.text('Class 2  •  Hindi ↔ Mundari'), findsOneWidget);
      expect(find.textContaining('Santali'), findsNothing);
    });

    testWidgets('shows the session start date and time', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      await pump(tester);

      expect(find.textContaining('29 Aug 2026'), findsOneWidget);
    });

    testWidgets('an unknown session id shows the error state', (
      WidgetTester tester,
    ) async {
      await pump(tester, id: 'missing');

      expect(
        find.text("Couldn't load this classroom session."),
        findsOneWidget,
      );
    });
  });

  group('metrics', () {
    testWidgets('duration comes from the session timestamps', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      await pump(tester);

      expect(find.text('08:42'), findsOneWidget);
    });

    testWidgets('translation count is counted from the turns', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      await pump(tester);

      expect(find.text('Translations'), findsOneWidget);
      expect(find.text('2'), findsWidgets);
    });

    testWidgets('average latency is the mean of the measured turns', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      final ConversationResultController c = await pump(tester);

      // (1700 + 1500) / 2 = 1600ms
      expect(c.session!.averageLatency, const Duration(milliseconds: 1600));
      expect(find.text('1.6'), findsOneWidget);
    });

    testWidgets('no measured turn shows a dash, never a number', (
      WidgetTester tester,
    ) async {
      await sessions.save(
        session(
          turns: <ConversationTurn>[
            ConversationTurn(
              id: 'turn-1',
              sessionId: sessionId,
              speaker: TurnSpeaker.teacher,
              sourceLanguage: 'hi-IN',
              targetLanguage: 'sat',
              timestamp: startedAt,
              status: TurnStatus.failed,
              failureMessage: "Couldn't understand the speech.",
            ),
          ],
        ),
      );
      await pump(tester);

      expect(find.text('--'), findsOneWidget);
    });

    testWidgets('a fully offline session reports 100%', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      await pump(tester);

      expect(find.text('Offline Mode'), findsWidgets);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('Active'), findsWidgets);
    });

    testWidgets('a mixed session reports partial rather than rounding', (
      WidgetTester tester,
    ) async {
      await sessions.save(
        session(
          turns: <ConversationTurn>[
            teacherTurn(),
            studentTurn(offline: false),
          ],
        ),
      );
      await pump(tester);

      // The header pill and the metric both say it, which is the point.
      expect(find.text('Partial'), findsWidgets);
      expect(find.text('50%'), findsOneWidget);
    });
  });

  group('timeline', () {
    testWidgets('expands each turn into the speaker and the AI line', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      final ConversationResultController c = await pump(tester);

      expect(c.timeline, hasLength(4));
      expect(find.text('Teacher — Hindi'), findsOneWidget);
      expect(find.text('GyanSetu — Santali Translation'), findsOneWidget);
      expect(find.text('Student — Santali'), findsOneWidget);
      expect(find.text('GyanSetu — Hindi Meaning'), findsOneWidget);
    });

    testWidgets('labels the AI line with the source that actually answered', (
      WidgetTester tester,
    ) async {
      await sessions.save(
        session(
          turns: <ConversationTurn>[
            teacherTurn(),
            studentTurn().copyWith(source: TranslationSource.phrasebook),
          ],
        ),
      );
      final ConversationResultController c = await pump(tester);

      // The honest source, phrased so a teacher never reads "AI" for an answer
      // a phrasebook or a cache produced.
      expect(find.text('GyanSetu Phrasebook — Hindi Meaning'), findsOneWidget);
      expect(c.timeline, hasLength(4));
    });

    testWidgets('shows the recognised and translated text as recorded', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      await pump(tester);

      expect(find.text('गिनती में 5 के बाद क्या आता है?'), findsOneWidget);
      expect(find.text('Pisa re 5 ko lagid kana aschey?'), findsOneWidget);
      expect(find.text('(पिसा रे 5 को लागिद काना असेय?)'), findsOneWidget);
      expect(find.text('5 के बाद 6 आता है।'), findsOneWidget);
    });

    testWidgets('shows confidence when the provider reported one', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      await pump(tester);

      expect(find.text('Confidence 95%'), findsWidgets);
      expect(find.text('Confidence 88%'), findsWidgets);
    });

    testWidgets('hides confidence when none was reported', (
      WidgetTester tester,
    ) async {
      await sessions.save(
        session(
          turns: <ConversationTurn>[teacherTurn(confidence: null)],
        ),
      );
      await pump(tester);

      expect(find.textContaining('Confidence'), findsNothing);
    });

    testWidgets('playing a line speaks the words that were recorded', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      await pump(tester);

      await tester.tap(find.byKey(ConversationResultScreen.playKey(1)));
      await tester.pumpAndSettle();

      // The Devanagari form is what the engine can pronounce.
      expect(tts.spoken.last, 'पिसा रे 5 को लागिद काना असेय?');
    });

    testWidgets('a line with no voice reports it instead of pretending', (
      WidgetTester tester,
    ) async {
      await sessions.save(
        session(
          turns: <ConversationTurn>[
            ConversationTurn(
              id: 'turn-1',
              sessionId: sessionId,
              speaker: TurnSpeaker.teacher,
              sourceLanguage: 'hi-IN',
              targetLanguage: 'sat',
              timestamp: startedAt,
              status: TurnStatus.ready,
              sourceText: 'कितने आम हैं?',
              translatedText: 'Kete ul menaka?',
              // No pronounceable form, and no Santali voice exists.
            ),
          ],
        ),
      );
      await pump(tester);

      await tester.tap(find.byKey(ConversationResultScreen.playKey(1)));
      await tester.pumpAndSettle();

      expect(find.textContaining('not available on this device'), findsWidgets);
      expect(tts.spoken, isEmpty);
    });

    testWidgets('a session with no turns says so', (
      WidgetTester tester,
    ) async {
      await sessions.save(session(turns: const <ConversationTurn>[]));
      await pump(tester);

      expect(
        find.text('No conversation data was recorded for this session.'),
        findsOneWidget,
      );
      // Saving and continuing are still offered.
      expect(
        find.byKey(ConversationResultScreen.saveSessionKey),
        findsOneWidget,
      );
    });
  });

  group('insights', () {
    testWidgets('interactions are counted from completed turns', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      final ConversationResultController c = await pump(tester);

      expect(c.insights!.interactionsCompleted, 2);
      expect(find.text('Interactions completed'), findsOneWidget);
    });

    testWidgets('reinforcement is unknown until an assessment is run', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      final ConversationResultController c = await pump(tester);

      // Null, not zero: nobody has checked.
      expect(c.insights!.conceptsNeedingReinforcement, isNull);
      expect(
        find.textContaining('Complete an assessment'),
        findsOneWidget,
      );
    });

    testWidgets('reinforcement names the concepts a child could not do', (
      WidgetTester tester,
    ) async {
      await assessments.record(
        AssessmentResult(
          lessonId: 'c1-num-counting-1-10',
          assessmentId: 'qa-1',
          outcomes: const <String, AssessmentOutcome>{
            'q1': AssessmentOutcome.achieved,
            'q2': AssessmentOutcome.notYet,
          },
          recordedAt: startedAt,
        ),
      );
      content.plan = testPlan(lessonId: 'c1-num-counting-1-10').withConcepts();
      await sessions.save(session());
      final ConversationResultController c = await pump(tester);

      expect(c.insights!.conceptsNeedingReinforcement, 1);
      expect(
        c.insights!.reinforcementConcepts.single.concept,
        'Number Sequence',
      );
    });

    testWidgets('engagement is read from pupil turns', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      final ConversationResultController c = await pump(tester);

      expect(c.insights!.engagement, EngagementLevel.active);
      expect(find.text('Students responded actively'), findsOneWidget);
    });

    testWidgets('a session with no pupil turns does not claim engagement', (
      WidgetTester tester,
    ) async {
      await sessions.save(
        session(turns: <ConversationTurn>[teacherTurn()]),
      );
      final ConversationResultController c = await pump(tester);

      expect(c.insights!.engagement, EngagementLevel.quiet);
      expect(find.text('Students responded actively'), findsNothing);
    });

    testWidgets('an empty session reports engagement as unavailable', (
      WidgetTester tester,
    ) async {
      await sessions.save(session(turns: const <ConversationTurn>[]));
      final ConversationResultController c = await pump(tester);

      expect(c.insights!.engagement, EngagementLevel.unknown);
      expect(find.text('Engagement data unavailable'), findsOneWidget);
    });

    testWidgets('top concepts come from the lesson', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      await pump(tester);

      expect(find.text('Top Concepts Discussed'), findsOneWidget);
      expect(find.text('Counting 1–10'), findsWidgets);
      expect(find.text('Number Sequence'), findsOneWidget);
      expect(find.text('After, Before, Between'), findsOneWidget);
    });

    testWidgets('a lesson with no concepts says so rather than inventing any', (
      WidgetTester tester,
    ) async {
      lessons.catalogue = <Lesson>[
        testLesson(id: 'c1-num-counting-1-10', title: 'Counting 1–10'),
      ];
      await sessions.save(session());
      await pump(tester);

      expect(
        find.textContaining('does not name its concepts yet'),
        findsOneWidget,
      );
    });

    testWidgets('insights are not recomputed on every rebuild', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      final ConversationResultController c = await pump(tester);
      final DateTime first = c.insights!.generatedAt;

      await tester.pump();
      expect(c.insights!.generatedAt, first);
    });
  });

  group('saving', () {
    testWidgets('Save Session writes the session and reports it', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      final int before = sessions.saveCalls;
      final ConversationResultController c = await pump(tester);

      await _reveal(tester, ConversationResultScreen.saveSessionKey);
      await tester.tap(find.byKey(ConversationResultScreen.saveSessionKey));
      await tester.pumpAndSettle();

      expect(c.saveState, SaveState.saved);
      expect(sessions.saveCalls, greaterThan(before));
      expect(sessions.values[sessionId]!.savedAt, isNotNull);
      await _reveal(tester, ConversationResultScreen.saveSessionKey);
      expect(
        _actionLabel(tester, ConversationResultScreen.saveSessionKey),
        'Session Saved',
      );
    });

    testWidgets('a second tap does not save twice', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      await pump(tester);

      await _reveal(tester, ConversationResultScreen.saveSessionKey);
      await tester.tap(find.byKey(ConversationResultScreen.saveSessionKey));
      await tester.pumpAndSettle();
      final int afterFirst = sessions.saveCalls;

      await _reveal(tester, ConversationResultScreen.saveSessionKey);
      await tester.tap(
        find.byKey(ConversationResultScreen.saveSessionKey),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(sessions.saveCalls, afterFirst);
    });

    testWidgets('an already-saved session opens as saved', (
      WidgetTester tester,
    ) async {
      await sessions.save(session(savedAt: startedAt));
      final ConversationResultController c = await pump(tester);

      expect(c.saveState, SaveState.saved);
      await _reveal(tester, ConversationResultScreen.saveSessionKey);
      expect(
        _actionLabel(tester, ConversationResultScreen.saveSessionKey),
        'Session Saved',
      );
    });

    testWidgets('saving works with no connection', (
      WidgetTester tester,
    ) async {
      connectivity = StaticConnectivityService(ConnectionStatus.offline);
      await sessions.save(session());
      final ConversationResultController c = await pump(tester);

      await _reveal(tester, ConversationResultScreen.saveSessionKey);
      await tester.tap(find.byKey(ConversationResultScreen.saveSessionKey));
      await tester.pumpAndSettle();

      expect(c.saveState, SaveState.saved);
      expect(
        sessions.values[sessionId]!.syncStatus,
        SessionSyncStatus.localOnly,
      );
    });
  });

  group('navigation', () {
    testWidgets('Continue Lesson opens the lesson it recorded', (
      WidgetTester tester,
    ) async {
      Object? args;
      await sessions.save(session());
      await pump(
        tester,
        routes: (RouteSettings settings) {
          if (settings.name == AppRoutes.lessonDetail) {
            args = settings.arguments;
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Scaffold(body: Text('lesson detail')),
            );
          }
          return AppRouter.onGenerateRoute(settings);
        },
      );

      await _reveal(tester, ConversationResultScreen.continueLessonKey);
      await tester.tap(find.byKey(ConversationResultScreen.continueLessonKey));
      await tester.pumpAndSettle();

      expect(args, isA<LessonDetailArgs>());
      expect((args! as LessonDetailArgs).lessonId, 'c1-num-counting-1-10');
    });

    testWidgets('Start Assessment opens the assessment, not the worksheet', (
      WidgetTester tester,
    ) async {
      Object? args;
      String? opened;
      await sessions.save(session());
      await pump(
        tester,
        routes: (RouteSettings settings) {
          if (settings.name == AppRoutes.assessment ||
              settings.name == AppRoutes.worksheet) {
            opened = settings.name;
            args = settings.arguments;
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Scaffold(body: Text('opened')),
            );
          }
          return AppRouter.onGenerateRoute(settings);
        },
      );

      await _reveal(tester, ConversationResultScreen.startAssessmentKey);
      await tester.tap(find.byKey(ConversationResultScreen.startAssessmentKey));
      await tester.pumpAndSettle();

      expect(opened, AppRoutes.assessment);
      expect(args, isA<AssessmentArgs>());
      expect((args! as AssessmentArgs).lessonId, 'c1-num-counting-1-10');
    });

    testWidgets('Create Worksheet opens the worksheet generator', (
      WidgetTester tester,
    ) async {
      Object? args;
      await sessions.save(session());
      await pump(
        tester,
        routes: (RouteSettings settings) {
          if (settings.name == AppRoutes.worksheet) {
            args = settings.arguments;
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Scaffold(body: Text('worksheet')),
            );
          }
          return AppRouter.onGenerateRoute(settings);
        },
      );

      await _reveal(tester, ConversationResultScreen.createWorksheetKey);
      await tester.tap(find.byKey(ConversationResultScreen.createWorksheetKey));
      await tester.pumpAndSettle();

      expect(args, isA<WorksheetGeneratorArgs>());
      expect(
        (args! as WorksheetGeneratorArgs).lessonId,
        'c1-num-counting-1-10',
      );
    });

    testWidgets('an assessment recorded elsewhere updates the insights', (
      WidgetTester tester,
    ) async {
      // The quick assessment is run from the lesson's own card; this screen
      // only has to reflect the result once it exists.
      content.plan = testPlan(lessonId: 'c1-num-counting-1-10').withConcepts();
      await sessions.save(session());
      final ConversationResultController c = await pump(tester);

      expect(c.insights!.conceptsNeedingReinforcement, isNull);

      await c.recordAssessment(
        AssessmentResult(
          lessonId: 'c1-num-counting-1-10',
          assessmentId: 'qa-1',
          outcomes: const <String, AssessmentOutcome>{
            'q1': AssessmentOutcome.achieved,
            'q2': AssessmentOutcome.notYet,
          },
          recordedAt: startedAt,
        ),
      );
      await tester.pumpAndSettle();

      expect(c.insights!.conceptsNeedingReinforcement, 1);
      expect(await assessments.latestFor('c1-num-counting-1-10'), isNotNull);
    });

    testWidgets('View Detailed Report opens the report with the session id', (
      WidgetTester tester,
    ) async {
      Object? args;
      await sessions.save(session());
      await pump(
        tester,
        routes: (RouteSettings settings) {
          if (settings.name == AppRoutes.sessionReport) {
            args = settings.arguments;
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Scaffold(body: Text('report')),
            );
          }
          return AppRouter.onGenerateRoute(settings);
        },
      );

      await _reveal(tester, ConversationResultScreen.detailedReportKey);
      await tester.tap(find.byKey(ConversationResultScreen.detailedReportKey));
      await tester.pumpAndSettle();

      expect(args, isA<ConversationResultArgs>());
      expect((args! as ConversationResultArgs).sessionId, sessionId);
    });

    testWidgets('back returns to whatever pushed this screen', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      final ConversationResultController controller = buildController();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          onGenerateRoute: (RouteSettings settings) =>
              settings.name == AppRoutes.conversationResult
                  ? MaterialPageRoute<void>(
                      settings: settings,
                      builder: (_) => ConversationResultScreen(
                        controller: controller,
                      ),
                    )
                  : AppRouter.onGenerateRoute(settings),
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context)
                      .pushNamed(AppRoutes.conversationResult),
                  child: const Text('open result'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open result'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ConversationResultScreen.backKey));
      await tester.pumpAndSettle();

      expect(find.text('open result'), findsOneWidget);
    });
  });

  group('lesson progress', () {
    testWidgets('a taught session moves progress along, but not to complete', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      await pump(tester);

      expect(await progress.percentFor('c1-num-counting-1-10'), 75);
    });

    testWidgets('a session with no interactions changes nothing', (
      WidgetTester tester,
    ) async {
      await sessions.save(session(turns: const <ConversationTurn>[]));
      await pump(tester);

      expect(await progress.percentFor('c1-num-counting-1-10'), 0);
    });

    testWidgets('progress never goes backwards', (WidgetTester tester) async {
      await progress.setPercent('c1-num-counting-1-10', 100);
      await sessions.save(session());
      await pump(tester);

      expect(await progress.percentFor('c1-num-counting-1-10'), 100);
    });
  });

  group('chrome', () {
    testWidgets('carries GyanSetu AI branding and no other', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      await pump(tester);

      expect(
        find.textContaining('GyanSetu AI', findRichText: true),
        findsWidgets,
      );
      expect(
        find.textContaining('BhashaSetu', findRichText: true),
        findsNothing,
      );
    });

    testWidgets('the footer claims only what the app does', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      await pump(tester);

      expect(
        find.text('This session is stored on this device. No internet needed.'),
        findsOneWidget,
      );
    });
  });

  group('layout', () {
    testWidgets('lays out on a small handset without overflow', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      await pump(tester, size: const Size(320, 1800));

      expect(tester.takeException(), isNull);
      expect(find.text('Conversation Summary'), findsOneWidget);
    });

    testWidgets('lays out on a tablet-sized screen without overflow', (
      WidgetTester tester,
    ) async {
      await sessions.save(session());
      await pump(tester, size: const Size(900, 1800));

      expect(tester.takeException(), isNull);
    });

    testWidgets('handles a long conversation without overflow', (
      WidgetTester tester,
    ) async {
      await sessions.save(
        session(
          turns: <ConversationTurn>[
            for (int i = 0; i < 30; i++)
              teacherTurn(id: 'turn-$i', second: i * 2),
          ],
        ),
      );
      final ConversationResultController c = await pump(tester);

      expect(tester.takeException(), isNull);
      expect(c.timeline, hasLength(60));
    });
  });
}

/// The curated plan with its questions tied to the lesson's concepts, which is
/// what lets a failed answer name a concept.
extension on LessonPlan {
  LessonPlan withConcepts() => LessonPlan(
        lessonId: lessonId,
        scriptMedium: scriptMedium,
        teacherScript: teacherScript,
        activity: activity,
        assessment: QuickAssessment(
          id: assessment.id,
          title: assessment.title,
          summary: assessment.summary,
          questions: const <AssessmentQuestion>[
            AssessmentQuestion(
              id: 'q1',
              prompt: 'Ask the child to show 3 objects.',
              successCriteria: 'Picks up exactly three.',
              concept: 'Counting 1–10',
            ),
            AssessmentQuestion(
              id: 'q2',
              prompt: 'Ask the child to count 7 stones.',
              successCriteria: 'Counts to seven.',
              concept: 'Number Sequence',
            ),
          ],
        ),
        generatedAt: generatedAt,
        tip: tip,
        provenance: provenance,
        curriculumAligned: curriculumAligned,
        flnCompetency: flnCompetency,
        version: version,
      );
}
