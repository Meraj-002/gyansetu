import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/app/routes.dart';
import 'package:gyan_setu_ai/app/theme.dart';
import 'package:gyan_setu_ai/features/lessons/lesson_activity_screen.dart';
import 'package:gyan_setu_ai/features/lessons/lesson_assessment_screen.dart';
import 'package:gyan_setu_ai/features/lessons/lesson_detail_screen.dart';
import 'package:gyan_setu_ai/features/lessons/lesson_navigation.dart';
import 'package:gyan_setu_ai/features/lessons/services/lesson_detail_controller.dart';
import 'package:gyan_setu_ai/features/lessons/services/assessment_repository.dart';
import 'package:gyan_setu_ai/features/lessons/services/translation_service.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/features/setup/models/offline_resource_status.dart';
import 'package:gyan_setu_ai/features/setup/services/offline_resource_manager.dart';
import 'package:gyan_setu_ai/models/lesson.dart';
import 'package:gyan_setu_ai/models/lesson_plan.dart';
import 'package:gyan_setu_ai/services/audio/lesson_audio_service.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';

import '../setup/setup_test_doubles.dart' as setup_doubles;
import 'lesson_detail_doubles.dart';
import 'lesson_test_doubles.dart';

void main() {
  late FakeLessonRepository lessons;
  late FakeContentRepository content;
  late FakeTranslationService translations;
  late FakeAudioService audio;
  late FakeProgressRepository progress;
  late InMemoryAssessmentRepository assessments;
  late setup_doubles.TestRepository classrooms;
  late StaticConnectivityService connectivity;

  setUp(() {
    lessons = FakeLessonRepository(
      catalogue: <Lesson>[
        testLesson(
          id: 'a',
          title: 'Counting 1–10',
          outcome: 'Count objects from 1 to 10.',
          minutes: 10,
        ),
        testLesson(
          id: 'b',
          title: 'Swar: A, AA, I',
          subject: ClassroomSubject.foundationalLiteracy,
          outcome: 'Identify and read basic swar letters.',
        ),
      ],
    );
    content = FakeContentRepository(plan: testPlan());
    translations = FakeTranslationService();
    audio = FakeAudioService();
    progress = FakeProgressRepository();
    assessments = InMemoryAssessmentRepository();
    classrooms = setup_doubles.TestRepository(existing: testClassroom());
    connectivity = StaticConnectivityService(ConnectionStatus.online);
  });

  LessonDetailController buildController({String lessonId = 'a'}) =>
      LessonDetailController(
        lessonId: lessonId,
        lessons: lessons,
        content: content,
        translations: translations,
        audio: audio,
        progress: progress,
        assessments: assessments,
        classrooms: classrooms,
        resources: const StaticOfflineResourceManager(
          OfflineResourceStatus(readiness: OfflineReadiness.needsSync),
        ),
        connectivity: connectivity,
        teacherId: kTeacherId,
      );

  /// The screen inside a real router, so navigation is exercised rather than
  /// stubbed.
  Future<LessonDetailController> pumpScreen(
    WidgetTester tester, {
    String lessonId = 'a',
    Size size = const Size(430, 1700),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final LessonDetailController controller = buildController(
      lessonId: lessonId,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        onGenerateRoute: AppRouter.onGenerateRoute,
        home: LessonDetailScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  group('lesson', () {
    testWidgets('resolves the lesson from the id it was given', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, lessonId: 'b');

      expect(find.text('Swar: A, AA, I'), findsOneWidget);
      expect(find.text('Counting 1–10'), findsNothing);
    });

    testWidgets('shows the title, class, subject and learning outcome', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Counting 1–10'), findsOneWidget);
      expect(find.text('Class 1'), findsOneWidget);
      expect(find.text('Numeracy'), findsOneWidget);
      expect(find.text('Learning Outcome'), findsOneWidget);
      expect(find.text('Count objects from 1 to 10.'), findsOneWidget);
    });

    testWidgets('shows the teacher script in the teaching medium', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Teacher Script'), findsOneWidget);
      expect(find.text('Hindi'), findsOneWidget);
      expect(find.text('(Teaching Language)'), findsOneWidget);
      expect(
        find.text('बच्चों, आज हम 1 से 10 तक गिनती सीखेंगे।'),
        findsOneWidget,
      );
    });

    testWidgets('an unknown id shows the not-found state', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, lessonId: 'missing');

      expect(find.text("Couldn't find this lesson."), findsOneWidget);
    });

    testWidgets('a lesson with no plan shows the missing-content state', (
      WidgetTester tester,
    ) async {
      content.plan = null;
      await pumpScreen(tester);

      // The lesson itself still renders; only its body is missing.
      expect(find.text('Counting 1–10'), findsOneWidget);
      expect(
        find.text("Lesson content isn't available for this lesson yet."),
        findsOneWidget,
      );
      expect(find.byKey(LessonDetailScreen.playButtonKey), findsNothing);
    });

    testWidgets('shows a skeleton while the plan is being read', (
      WidgetTester tester,
    ) async {
      content.latency = const Duration(milliseconds: 300);
      final LessonDetailController controller = buildController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: LessonDetailScreen(controller: controller),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('lesson-detail-skeleton')), findsOneWidget);

      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('lesson-detail-skeleton')), findsNothing);
    });
  });

  group('badges', () {
    testWidgets('authored content is not labelled AI-generated', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);

      expect(find.textContaining('Curriculum aligned'), findsOneWidget);
      expect(find.textContaining('AI-generated'), findsNothing);
    });

    testWidgets('AI-generated content is labelled', (
      WidgetTester tester,
    ) async {
      content.plan = testPlan(provenance: ContentProvenance.aiGenerated);
      await pumpScreen(tester);

      expect(find.textContaining('AI-generated'), findsOneWidget);
    });

    testWidgets('a tip written by a person is not called an AI tip', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Tip for Teachers'), findsOneWidget);
      expect(find.text('AI Tip for Teachers'), findsNothing);
    });

    testWidgets('a tip written by the AI layer is labelled as one', (
      WidgetTester tester,
    ) async {
      content.plan = testPlan(
        tip: const TeachingTip(
          text: 'Try grouping the seeds in fives.',
          provenance: ContentProvenance.aiGenerated,
        ),
      );
      await pumpScreen(tester);

      expect(find.text('AI Tip for Teachers'), findsOneWidget);
    });
  });

  group('translation', () {
    testWidgets('the button names the classroom target language', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Translate to Santali'), findsOneWidget);
    });

    testWidgets('changing the classroom changes every language label', (
      WidgetTester tester,
    ) async {
      classrooms = setup_doubles.TestRepository(
        existing: testClassroom(target: TargetLanguage.mundari),
      );
      await pumpScreen(tester);

      expect(find.text('Translate to Mundari'), findsOneWidget);
      expect(find.text('Play Mundari'), findsOneWidget);
      expect(find.text('Translate to Santali'), findsNothing);
    });

    testWidgets('shows a loading state while translating', (
      WidgetTester tester,
    ) async {
      translations.latency = const Duration(milliseconds: 300);
      await pumpScreen(tester);

      await tester.tap(find.byKey(LessonDetailScreen.translateButtonKey));
      await tester.pump();

      expect(find.text('Translating…'), findsOneWidget);

      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('Translating…'), findsNothing);
    });

    testWidgets('a successful translation is shown and labelled', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(LessonDetailScreen.translateButtonKey));
      await tester.pumpAndSettle();

      expect(find.text('Translated to Santali'), findsOneWidget);
      expect(
        find.text("Johar gidra'ko! Mit', bar, pe, pon, more."),
        findsOneWidget,
      );
      expect(find.text('(Mother Tongue)'), findsOneWidget);
    });

    testWidgets('an unreviewed translation says so', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(LessonDetailScreen.translateButtonKey));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('not yet checked by a Santali speaker'),
        findsOneWidget,
      );
    });

    testWidgets('a failure shows a friendly message and Try Again', (
      WidgetTester tester,
    ) async {
      translations.outcome = const TranslationFailed(
        "Couldn't translate this lesson right now.",
      );
      await pumpScreen(tester);

      await tester.tap(find.byKey(LessonDetailScreen.translateButtonKey));
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't translate this lesson right now."),
        findsOneWidget,
      );
      expect(find.text('Try Again'), findsOneWidget);

      translations.outcome = null;
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      expect(find.text('Translated to Santali'), findsOneWidget);
    });

    testWidgets('offline with nothing saved explains and does not invent', (
      WidgetTester tester,
    ) async {
      connectivity = StaticConnectivityService(ConnectionStatus.offline);
      translations.outcome = const TranslationNeedsConnection(
        "This translation isn't available offline yet.",
      );
      await pumpScreen(tester);

      await tester.tap(find.byKey(LessonDetailScreen.translateButtonKey));
      await tester.pumpAndSettle();

      expect(
        find.text("This translation isn't available offline yet."),
        findsOneWidget,
      );
    });

    testWidgets('a cached translation is shown offline with no request', (
      WidgetTester tester,
    ) async {
      connectivity = StaticConnectivityService(ConnectionStatus.offline);
      translations.cachedTranslation = testTranslation();
      await pumpScreen(tester);

      expect(find.text('Translated to Santali'), findsOneWidget);
      expect(translations.translateCalls, 0);
    });
  });

  group('audio', () {
    testWidgets('the player names the classroom target language', (
      WidgetTester tester,
    ) async {
      translations.cachedTranslation = testTranslation();
      await pumpScreen(tester);

      expect(find.text('Play Santali'), findsOneWidget);
    });

    testWidgets('tapping play asks the audio service for the passage', (
      WidgetTester tester,
    ) async {
      translations.cachedTranslation = testTranslation();
      await pumpScreen(tester);

      await tester.tap(find.byKey(LessonDetailScreen.playButtonKey));
      await tester.pumpAndSettle();

      expect(audio.playCalls, 1);
      expect(audio.lastPassage?.localeId, 'sat');
      expect(find.text('Playing Santali'), findsOneWidget);
    });

    testWidgets('tapping again pauses', (WidgetTester tester) async {
      translations.cachedTranslation = testTranslation();
      await pumpScreen(tester);

      await tester.tap(find.byKey(LessonDetailScreen.playButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(LessonDetailScreen.playButtonKey));
      await tester.pumpAndSettle();

      expect(audio.calls, contains('pause'));
      expect(find.text('Resume Santali'), findsOneWidget);
    });

    testWidgets('completion returns the player to a resting label', (
      WidgetTester tester,
    ) async {
      translations.cachedTranslation = testTranslation();
      await pumpScreen(tester);

      await tester.tap(find.byKey(LessonDetailScreen.playButtonKey));
      await tester.pumpAndSettle();

      audio.emit(PlaybackState.completed);
      await tester.pumpAndSettle();

      expect(find.text('Playing Santali'), findsNothing);
      expect(find.text('Play Santali'), findsOneWidget);
    });

    testWidgets('the script speaker plays the script, not the translation', (
      WidgetTester tester,
    ) async {
      translations.cachedTranslation = testTranslation();
      await pumpScreen(tester);

      await tester.tap(find.byKey(LessonDetailScreen.scriptSpeakKey));
      await tester.pumpAndSettle();

      expect(audio.lastPassage?.localeId, 'hi-IN');
    });

    testWidgets('Slow changes the real playback speed', (
      WidgetTester tester,
    ) async {
      translations.cachedTranslation = testTranslation();
      await pumpScreen(tester);

      await tester.tap(find.byKey(LessonDetailScreen.slowButtonKey));
      await tester.pumpAndSettle();

      expect(audio.speed, AudioSpeed.slow);
      expect(find.text('0.75x'), findsOneWidget);

      await tester.tap(find.byKey(LessonDetailScreen.slowButtonKey));
      await tester.pumpAndSettle();

      expect(audio.speed, AudioSpeed.normal);
      expect(find.text('Slow'), findsOneWidget);
    });

    testWidgets('Repeat restarts playback rather than showing a message', (
      WidgetTester tester,
    ) async {
      translations.cachedTranslation = testTranslation();
      await pumpScreen(tester);

      await tester.tap(find.byKey(LessonDetailScreen.repeatButtonKey));
      await tester.pumpAndSettle();

      expect(audio.repeatCalls, 1);
    });

    testWidgets('Save Audio saves and then reports it is saved', (
      WidgetTester tester,
    ) async {
      translations.cachedTranslation = testTranslation();
      await pumpScreen(tester);

      await tester.tap(find.byKey(LessonDetailScreen.saveAudioButtonKey));
      await tester.pumpAndSettle();

      expect(audio.saveCalls, 1);
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Saved for offline use.'), findsOneWidget);
    });

    testWidgets('a refused save says why and stays unsaved', (
      WidgetTester tester,
    ) async {
      translations.cachedTranslation = testTranslation();
      audio.saveOutcome = const SaveBlocked(
        'Saving audio needs the phone app.',
      );
      await pumpScreen(tester);

      await tester.tap(find.byKey(LessonDetailScreen.saveAudioButtonKey));
      await tester.pumpAndSettle();

      expect(find.text('Saving audio needs the phone app.'), findsOneWidget);
      expect(find.text('Save Audio'), findsOneWidget);
    });

    testWidgets('an already-saved clip is shown as available offline', (
      WidgetTester tester,
    ) async {
      translations.cachedTranslation = testTranslation();
      audio.availabilityResult = const AudioAvailability(
        kind: AudioVoiceKind.savedClip,
        saved: true,
        note: 'Saved on this device',
      );
      await pumpScreen(tester);

      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Saved on this device'), findsOneWidget);
    });

    testWidgets('a language with no voice says so and disables playback', (
      WidgetTester tester,
    ) async {
      translations.cachedTranslation = testTranslation();
      audio.availabilityResult = const AudioAvailability(
        kind: AudioVoiceKind.none,
        blockedReason:
            'Audio in Santali is not available on this device yet.',
      );
      await pumpScreen(tester);

      expect(
        find.text('Audio in Santali is not available on this device yet.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(LessonDetailScreen.playButtonKey));
      await tester.pumpAndSettle();
      expect(audio.playCalls, 0);
    });

    testWidgets('an approximate voice is labelled as approximate', (
      WidgetTester tester,
    ) async {
      translations.cachedTranslation = testTranslation();
      audio.availabilityResult = const AudioAvailability(
        kind: AudioVoiceKind.approximateVoice,
        note: 'Approximate voice — no Santali voice on this device yet.',
      );
      await pumpScreen(tester);

      expect(find.textContaining('Approximate voice'), findsOneWidget);
    });

    testWidgets('with no translation the player explains what is needed', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);

      expect(
        find.text('Audio will be prepared when you translate this lesson.'),
        findsOneWidget,
      );
    });
  });

  group('progress', () {
    testWidgets('opening the lesson records nothing', (
      WidgetTester tester,
    ) async {
      final LessonDetailController controller = await pumpScreen(tester);

      expect(controller.completionPercentage, 0);
      expect(await progress.percentFor('a'), 0);
    });

    testWidgets('translating records progress', (WidgetTester tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(LessonDetailScreen.translateButtonKey));
      await tester.pumpAndSettle();

      expect(await progress.percentFor('a'), LessonMilestone.translated.percent);
    });

    testWidgets('progress is restored when the lesson is reopened', (
      WidgetTester tester,
    ) async {
      await progress.setPercent('a', 75);
      final LessonDetailController controller = await pumpScreen(tester);

      expect(controller.completionPercentage, 75);
    });

    testWidgets('progress never goes backwards', (WidgetTester tester) async {
      await progress.setPercent('a', 100);
      final LessonDetailController controller = await pumpScreen(tester);

      await tester.tap(find.byKey(LessonDetailScreen.translateButtonKey));
      await tester.pumpAndSettle();

      expect(controller.completionPercentage, 100);
    });
  });

  group('activity and assessment', () {
    testWidgets('the activity comes from the plan, not the widget', (
      WidgetTester tester,
    ) async {
      content.plan = testPlan();
      await pumpScreen(tester);

      expect(find.text('Classroom Activity'), findsOneWidget);
      expect(
        find.text('Show 5 objects and ask children to count them.'),
        findsOneWidget,
      );
    });

    testWidgets('tapping the activity opens it with the lesson context', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Classroom Activity'));
      await tester.pumpAndSettle();

      expect(find.byType(LessonActivityScreen), findsOneWidget);
      expect(find.text('Count with real objects'), findsOneWidget);
      expect(find.text('Put five seeds on the desk.'), findsOneWidget);
    });

    testWidgets('returning from the activity records progress', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Classroom Activity'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(LessonActivityScreen.startedButtonKey));
      await tester.pumpAndSettle();

      expect(
        await progress.percentFor('a'),
        LessonMilestone.activityOpened.percent,
      );
    });

    testWidgets('tapping the assessment opens its questions', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Quick Assessment'));
      await tester.pumpAndSettle();

      expect(find.byType(LessonAssessmentScreen), findsOneWidget);
      expect(find.text('Ask the child to show 3 objects.'), findsWidgets);
      expect(find.text('Ask the child to count 7 stones.'), findsOneWidget);
    });

    testWidgets('a completed assessment is saved and reflected in progress', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Quick Assessment'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          LessonAssessmentScreen.outcomeKey('q1', AssessmentOutcome.achieved),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
          LessonAssessmentScreen.outcomeKey('q2', AssessmentOutcome.notYet),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(LessonAssessmentScreen.saveButtonKey));
      await tester.pumpAndSettle();

      final AssessmentResult? saved = await assessments.latestFor('a');
      expect(saved, isNotNull);
      expect(saved!.achievedCount, 1);
      expect(saved.total, 2);
      expect(await progress.percentFor('a'), LessonMilestone.assessed.percent);
      expect(find.text('Last recorded: 1 of 2 can do'), findsOneWidget);
    });

    testWidgets('the assessment cannot be saved half-marked', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Quick Assessment'));
      await tester.pumpAndSettle();

      final Finder save = find.byKey(LessonAssessmentScreen.saveButtonKey);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
    });
  });

  group('live classroom', () {
    testWidgets('is handed the lesson, class and both languages', (
      WidgetTester tester,
    ) async {
      translations.cachedTranslation = testTranslation();

      // The arguments are captured at the route rather than read off the live
      // classroom's widgets: what matters here is the hand-off, and the live
      // session opens a microphone this test has no business starting.
      LiveClassroomArgs? handedOver;

      final LessonDetailController controller = buildController();
      addTearDown(controller.dispose);

      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          onGenerateRoute: (RouteSettings settings) {
            if (settings.name == AppRoutes.liveClassroom) {
              handedOver = settings.arguments as LiveClassroomArgs?;
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => const Scaffold(body: Text('live')),
              );
            }
            return AppRouter.onGenerateRoute(settings);
          },
          home: LessonDetailScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(LessonDetailScreen.liveClassroomKey),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(LessonDetailScreen.liveClassroomKey));
      await tester.pumpAndSettle();

      expect(handedOver, isNotNull);
      expect(handedOver!.lessonId, 'a');
      expect(handedOver!.lessonTitle, 'Counting 1–10');
      expect(handedOver!.learningOutcome, 'Count objects from 1 to 10.');
      expect(handedOver!.classLevel, 1);
      expect(handedOver!.subject, ClassroomSubject.numeracy);
      expect(handedOver!.teachingMedium, TeachingMedium.hindi);
      expect(handedOver!.targetLanguage, TargetLanguage.santali);
      expect(handedOver!.translatedScript, isNotNull);
    });

    testWidgets('stops playback before starting a session', (
      WidgetTester tester,
    ) async {
      translations.cachedTranslation = testTranslation();
      await pumpScreen(tester);

      await tester.tap(find.byKey(LessonDetailScreen.playButtonKey));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(LessonDetailScreen.liveClassroomKey),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(LessonDetailScreen.liveClassroomKey));
      await tester.pumpAndSettle();

      expect(audio.calls, contains('stop'));
    });
  });

  group('chrome', () {
    testWidgets('carries the GyanSetu AI branding and no other', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);

      // The wordmark is one rich span so 'GyanSetu' and 'AI' can carry
      // different colours; it is matched as such.
      expect(
        find.textContaining('GyanSetu AI', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('BhashaSetu', findRichText: true),
        findsNothing,
      );
    });

    testWidgets('the offline pill reports the real state', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);
      expect(find.text('Online'), findsOneWidget);

      connectivity.set(ConnectionStatus.offline);
      await tester.pumpAndSettle();
      expect(find.text('Sync Required'), findsOneWidget);
      expect(find.text('Offline Ready'), findsNothing);
    });

    testWidgets('claims Offline Ready only when resources really are', (
      WidgetTester tester,
    ) async {
      final LessonDetailController controller = LessonDetailController(
        lessonId: 'a',
        lessons: lessons,
        content: content,
        translations: translations,
        audio: audio,
        progress: progress,
        assessments: assessments,
        classrooms: classrooms,
        resources: const StaticOfflineResourceManager(
          OfflineResourceStatus(readiness: OfflineReadiness.ready),
        ),
        connectivity: StaticConnectivityService(ConnectionStatus.offline),
        teacherId: kTeacherId,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: LessonDetailScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Offline Ready'), findsOneWidget);
    });

    testWidgets('back returns to whatever pushed this screen', (
      WidgetTester tester,
    ) async {
      final LessonDetailController controller = buildController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          // The detail route is served with the test's controller so the push
          // exercises real navigation without reaching for platform storage.
          onGenerateRoute: (RouteSettings settings) =>
              settings.name == AppRoutes.lessonDetail
                  ? MaterialPageRoute<void>(
                      settings: settings,
                      builder: (_) =>
                          LessonDetailScreen(controller: controller),
                    )
                  : AppRouter.onGenerateRoute(settings),
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pushNamed(
                    AppRoutes.lessonDetail,
                    arguments: const LessonDetailArgs('a'),
                  ),
                  child: const Text('open lesson'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open lesson'));
      await tester.pumpAndSettle();

      expect(find.byType(LessonDetailScreen), findsOneWidget);

      await tester.tap(find.byKey(LessonDetailScreen.backButtonKey));
      await tester.pumpAndSettle();

      expect(find.text('open lesson'), findsOneWidget);
    });

    testWidgets('the more menu offers only actions that work', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(LessonDetailScreen.moreMenuKey));
      await tester.pumpAndSettle();

      expect(find.text('Lesson information'), findsOneWidget);
      expect(find.text('Manage offline downloads'), findsOneWidget);
      expect(find.text('Save Santali audio'), findsOneWidget);

      await tester.tap(find.text('Lesson information'));
      await tester.pumpAndSettle();

      expect(find.text('Curriculum authored'), findsOneWidget);
    });
  });

  group('layout', () {
    testWidgets('lays out on a small handset without overflow', (
      WidgetTester tester,
    ) async {
      translations.cachedTranslation = testTranslation();
      await pumpScreen(tester, size: const Size(320, 1500));

      expect(tester.takeException(), isNull);
      expect(find.text('Counting 1–10'), findsOneWidget);
      expect(find.byKey(LessonDetailScreen.playButtonKey), findsOneWidget);
    });

    testWidgets('lays out on a large screen without overflow', (
      WidgetTester tester,
    ) async {
      translations.cachedTranslation = testTranslation();
      await pumpScreen(tester, size: const Size(900, 1500));

      expect(tester.takeException(), isNull);
      expect(find.text('Play Santali'), findsOneWidget);
    });
  });
}
