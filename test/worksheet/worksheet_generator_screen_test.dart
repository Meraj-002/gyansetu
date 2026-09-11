import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/app/routes.dart';
import 'package:gyan_setu_ai/app/theme.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/features/worksheet/services/worksheet_generation_service.dart';
import 'package:gyan_setu_ai/features/worksheet/services/worksheet_generator_controller.dart';
import 'package:gyan_setu_ai/features/worksheet/services/worksheet_repository.dart';
import 'package:gyan_setu_ai/features/worksheet/worksheet_generator_screen.dart';
import 'package:gyan_setu_ai/features/worksheet/worksheet_preview_screen.dart'
    show WorksheetPreviewArgs;
import 'package:gyan_setu_ai/models/lesson.dart';
import 'package:gyan_setu_ai/models/question.dart';
import 'package:gyan_setu_ai/models/worksheet.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';

import '../lessons/lesson_test_doubles.dart';
import '../setup/setup_test_doubles.dart' as setup_doubles;
import 'worksheet_doubles.dart';

/// Scrolls a control into view before tapping it.
Future<void> _reveal(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    300,
    scrollable: find.descendant(
      of: find.byKey(WorksheetGeneratorScreen.scrollKey),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late FakeLessonRepository lessons;
  late setup_doubles.TestRepository classrooms;
  late FakeWorksheetGenerationService generator;
  late InMemoryWorksheetRepository worksheets;
  late StaticConnectivityService connectivity;
  late InMemorySecureStorageService storage;

  Lesson countingLesson() => Lesson(
        id: 'c1-num-counting-1-10',
        title: 'Counting 1–10',
        description: 'Count everyday objects aloud.',
        subject: ClassroomSubject.numeracy,
        classNumber: 1,
        learningOutcome: 'Count and identify numbers 1–10',
        durationMinutes: 10,
        lessonOrder: 1,
        createdAt: DateTime(2026, 6, 1),
        updatedAt: DateTime(2026, 6, 1),
        concepts: kCountingConcepts,
      );

  setUp(() {
    lessons = FakeLessonRepository(catalogue: <Lesson>[countingLesson()]);
    classrooms = setup_doubles.TestRepository(existing: testClassroom());
    generator = FakeWorksheetGenerationService();
    worksheets = InMemoryWorksheetRepository();
    connectivity = StaticConnectivityService(ConnectionStatus.offline);
    storage = InMemorySecureStorageService();
  });

  WorksheetGeneratorController buildController({
    String lessonId = 'c1-num-counting-1-10',
  }) {
    final WorksheetGeneratorController controller =
        WorksheetGeneratorController(
      lessonId: lessonId,
      lessons: lessons,
      classrooms: classrooms,
      generator: generator,
      worksheets: worksheets,
      connectivity: connectivity,
      storage: storage,
      teacherId: kTeacherId,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<WorksheetGeneratorController> pump(
    WidgetTester tester, {
    String lessonId = 'c1-num-counting-1-10',
    Size size = const Size(430, 1700),
    RouteFactory? routes,
    WorksheetGeneratorController? controller,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final WorksheetGeneratorController c =
        controller ?? buildController(lessonId: lessonId);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        onGenerateRoute: routes ?? AppRouter.onGenerateRoute,
        home: WorksheetGeneratorScreen(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  group('context', () {
    testWidgets('shows the lesson it was opened with', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      expect(find.text('Create Worksheet'), findsOneWidget);
      expect(find.text('Counting 1–10'), findsOneWidget);
      expect(find.text('Count and identify numbers 1–10'), findsOneWidget);
    });

    testWidgets('shows the language pair from the classroom', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      expect(find.text('Hindi  +  Santali'), findsOneWidget);
    });

    testWidgets('follows a classroom set to Mundari', (
      WidgetTester tester,
    ) async {
      classrooms = setup_doubles.TestRepository(
        existing: testClassroom(target: TargetLanguage.mundari),
      );
      await pump(tester);

      expect(find.text('Hindi  +  Mundari'), findsOneWidget);
      expect(find.textContaining('Santali'), findsNothing);
    });

    testWidgets('an unknown lesson shows the error state', (
      WidgetTester tester,
    ) async {
      await pump(tester, lessonId: 'missing');

      expect(find.text("Couldn't load this lesson."), findsOneWidget);
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

    testWidgets('a local generator is not labelled AI-generated', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      expect(find.textContaining('Curriculum aligned'), findsOneWidget);
      expect(find.textContaining('AI-generated'), findsNothing);
    });

    testWidgets('a real model does earn the AI label', (
      WidgetTester tester,
    ) async {
      generator.sourceOverride = GenerationSource.remoteAi;
      await pump(tester);

      expect(find.textContaining('AI-generated'), findsOneWidget);
    });
  });

  group('offline status', () {
    testWidgets('says Offline Ready when the generator really can run', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      expect(find.text('Offline Ready'), findsOneWidget);
    });

    testWidgets('says so plainly when generation is unavailable', (
      WidgetTester tester,
    ) async {
      generator.available = false;
      await pump(tester);

      expect(find.text('Offline generation unavailable'), findsOneWidget);
    });
  });

  group('choices', () {
    testWidgets('difficulty is single select and defaults to Easy', (
      WidgetTester tester,
    ) async {
      final WorksheetGeneratorController c = await pump(tester);
      expect(c.difficulty, WorksheetDifficulty.easy);

      await tester.tap(
        find.byKey(
          WorksheetGeneratorScreen.difficultyKey(WorksheetDifficulty.medium),
        ),
      );
      await tester.pumpAndSettle();

      expect(c.difficulty, WorksheetDifficulty.medium);
    });

    testWidgets('question types are multi select', (
      WidgetTester tester,
    ) async {
      final WorksheetGeneratorController c = await pump(tester);

      await _reveal(
        tester,
        WorksheetGeneratorScreen.questionTypeKey(QuestionType.fillInTheBlanks),
      );
      await tester.tap(
        find.byKey(
          WorksheetGeneratorScreen.questionTypeKey(
            QuestionType.fillInTheBlanks,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(c.questionTypes, <QuestionType>{
        QuestionType.countingObjects,
        QuestionType.fillInTheBlanks,
      });
    });

    testWidgets('the last question type cannot be removed', (
      WidgetTester tester,
    ) async {
      final WorksheetGeneratorController c = await pump(tester);

      await _reveal(
        tester,
        WorksheetGeneratorScreen.questionTypeKey(QuestionType.countingObjects),
      );
      await tester.tap(
        find.byKey(
          WorksheetGeneratorScreen.questionTypeKey(
            QuestionType.countingObjects,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(c.questionTypes, hasLength(1));
      expect(find.text('Keep at least one question type.'), findsOneWidget);
    });

    testWidgets('question count defaults to 10 and can be changed', (
      WidgetTester tester,
    ) async {
      final WorksheetGeneratorController c = await pump(tester);
      expect(c.numberOfQuestions, 10);

      await _reveal(tester, WorksheetGeneratorScreen.countKey(15));
      await tester.tap(find.byKey(WorksheetGeneratorScreen.countKey(15)));
      await tester.pumpAndSettle();

      expect(c.numberOfQuestions, 15);
    });

    testWidgets('visual examples are multi select', (
      WidgetTester tester,
    ) async {
      final WorksheetGeneratorController c = await pump(tester);

      await _reveal(
        tester,
        WorksheetGeneratorScreen.visualKey(VisualExample.trees),
      );
      await tester.tap(
        find.byKey(WorksheetGeneratorScreen.visualKey(VisualExample.trees)),
      );
      await tester.pumpAndSettle();

      expect(c.visualExamples, contains(VisualExample.trees));
      expect(c.visualExamples, contains(VisualExample.apples));
    });

    testWidgets('the cultural toggle is on by default and can be turned off', (
      WidgetTester tester,
    ) async {
      final WorksheetGeneratorController c = await pump(tester);
      expect(c.culturallyFamiliar, isTrue);

      await _reveal(tester, WorksheetGeneratorScreen.culturalToggleKey);
      await tester.tap(find.byKey(WorksheetGeneratorScreen.culturalToggleKey));
      await tester.pumpAndSettle();

      expect(c.culturallyFamiliar, isFalse);
    });

    testWidgets('choices are remembered for the next visit', (
      WidgetTester tester,
    ) async {
      final WorksheetGeneratorController first = await pump(tester);
      await tester.tap(
        find.byKey(
          WorksheetGeneratorScreen.difficultyKey(WorksheetDifficulty.advanced),
        ),
      );
      await tester.pumpAndSettle();
      expect(first.difficulty, WorksheetDifficulty.advanced);

      // A fresh controller over the same storage.
      final WorksheetGeneratorController second = buildController();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: WorksheetGeneratorScreen(controller: second),
        ),
      );
      await tester.pumpAndSettle();

      expect(second.difficulty, WorksheetDifficulty.advanced);
    });
  });

  group('request', () {
    testWidgets('is built from the lesson and the classroom', (
      WidgetTester tester,
    ) async {
      final WorksheetGeneratorController c = await pump(tester);
      final WorksheetGenerationRequest request = c.buildRequest()!;

      expect(request.lessonId, 'c1-num-counting-1-10');
      expect(request.lessonTitle, 'Counting 1–10');
      expect(request.learningOutcome, 'Count and identify numbers 1–10');
      expect(request.classNumber, 1);
      expect(request.teachingLanguage, TeachingMedium.hindi);
      expect(request.targetLanguage, TargetLanguage.santali);
      expect(request.concepts, kCountingConcepts);
    });

    testWidgets('carries every choice through to the generator', (
      WidgetTester tester,
    ) async {
      final WorksheetGeneratorController c = await pump(tester);
      c
        ..setDifficulty(WorksheetDifficulty.medium)
        ..setQuestionCount(15)
        ..toggleQuestionType(QuestionType.fillInTheBlanks)
        ..toggleVisualExample(VisualExample.trees)
        ..setCulturallyFamiliar(false);
      await tester.pumpAndSettle();

      await c.generate();

      final WorksheetGenerationRequest sent = generator.lastRequest!;
      expect(sent.difficulty, WorksheetDifficulty.medium);
      expect(sent.numberOfQuestions, 15);
      expect(sent.questionTypes, contains(QuestionType.fillInTheBlanks));
      expect(sent.visualExamples, contains(VisualExample.trees));
      expect(sent.culturallyFamiliarExamples, isFalse);
    });
  });

  group('validation', () {
    testWidgets('refuses to generate without a classroom', (
      WidgetTester tester,
    ) async {
      classrooms = setup_doubles.TestRepository();
      final WorksheetGeneratorController c = await pump(tester);

      expect(c.canGenerate, isFalse);
      expect(
        c.validationMessage,
        contains('Finish classroom setup'),
      );

      await c.generate();
      expect(generator.calls, 0);
    });

    testWidgets('refuses when the generator is unavailable', (
      WidgetTester tester,
    ) async {
      generator.available = false;
      final WorksheetGeneratorController c = await pump(tester);

      expect(c.canGenerate, isFalse);
      await c.generate();
      expect(generator.calls, 0);
    });
  });

  group('generating', () {
    testWidgets('shows the stages while it works', (
      WidgetTester tester,
    ) async {
      generator.latency = const Duration(milliseconds: 300);
      // A viewport tall enough for the whole form, so the button and the
      // progress panel are both built rather than culled by the list.
      final WorksheetGeneratorController c =
          await pump(tester, size: const Size(430, 3200));

      unawaitedGenerate(c);
      await tester.pump();

      expect(find.text('Generating Worksheet…'), findsOneWidget);
      expect(find.text('Generating questions…'), findsOneWidget);

      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      expect(find.text('Generating Worksheet…'), findsNothing);
    });

    testWidgets('a second tap does not start a second worksheet', (
      WidgetTester tester,
    ) async {
      generator.latency = const Duration(milliseconds: 300);
      final WorksheetGeneratorController c =
          await pump(tester, size: const Size(430, 3200));

      unawaitedGenerate(c);
      await tester.pump();
      // The button is disabled while one is running.
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(WorksheetGeneratorScreen.generateKey),
            )
            .onPressed,
        isNull,
      );
      unawaitedGenerate(c);

      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      expect(generator.calls, 1);
    });

    testWidgets('saves the worksheet before showing it', (
      WidgetTester tester,
    ) async {
      final WorksheetGeneratorController c = await pump(tester);
      final Worksheet? worksheet = await c.generate();

      expect(worksheet, isNotNull);
      expect(worksheets.values[worksheet!.id], isNotNull);
      expect(worksheets.values[worksheet.id]!.questionCount, 10);
    });

    testWidgets('a failure is reported plainly with a retry', (
      WidgetTester tester,
    ) async {
      generator.failure = const WorksheetGenerationFailure(
        WorksheetFailureReason.failed,
        "Couldn't generate the worksheet.",
      );
      final WorksheetGeneratorController c =
          await pump(tester, size: const Size(430, 3200));

      await c.generate();
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't generate the worksheet."),
        findsOneWidget,
      );
      expect(find.text('Try Again'), findsOneWidget);
      expect(c.generationState, GenerationState.failed);
    });

    testWidgets('retry runs the same request again', (
      WidgetTester tester,
    ) async {
      generator.failure = const WorksheetGenerationFailure(
        WorksheetFailureReason.failed,
        'nope',
      );
      final WorksheetGeneratorController c = await pump(tester);
      await c.generate();
      await tester.pumpAndSettle();

      generator.failure = null;
      final Worksheet? worksheet = await c.retry();

      expect(worksheet, isNotNull);
      expect(generator.calls, 2);
    });

    testWidgets('output that fails validation is refused, not shown', (
      WidgetTester tester,
    ) async {
      // A generator that returns three questions when ten were asked for.
      final WorksheetGeneratorController probe = buildController();
      await tester.pumpWidget(
        MaterialApp(home: WorksheetGeneratorScreen(controller: probe)),
      );
      await tester.pumpAndSettle();

      final Worksheet full = await FakeWorksheetGenerationService()
          .generate(probe.buildRequest()!);
      generator.worksheet = worksheetWith(
        full,
        questions: full.questions.take(3).toList(),
      );

      final WorksheetGeneratorController c = buildController();
      await tester.pumpWidget(
        MaterialApp(home: WorksheetGeneratorScreen(controller: c)),
      );
      await tester.pumpAndSettle();

      final Worksheet? worksheet = await c.generate();

      expect(worksheet, isNull);
      expect(c.generationState, GenerationState.failed);
      expect(worksheets.values, isEmpty);
    });

    testWidgets('generation works with no connection', (
      WidgetTester tester,
    ) async {
      connectivity = StaticConnectivityService(ConnectionStatus.offline);
      final WorksheetGeneratorController c = await pump(tester);

      final Worksheet? worksheet = await c.generate();

      expect(worksheet, isNotNull);
      expect(worksheet!.generationSource, GenerationSource.localOffline);
    });
  });

  group('preview', () {
    testWidgets('opens with the worksheet that was generated', (
      WidgetTester tester,
    ) async {
      Object? args;
      await pump(
        tester,
        routes: (RouteSettings settings) {
          if (settings.name == AppRoutes.worksheetPreview) {
            args = settings.arguments;
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Scaffold(body: Text('preview')),
            );
          }
          return AppRouter.onGenerateRoute(settings);
        },
      );

      await _reveal(tester, WorksheetGeneratorScreen.generateKey);
      await tester.tap(find.byKey(WorksheetGeneratorScreen.generateKey));
      await tester.pumpAndSettle();

      expect(args, isA<WorksheetPreviewArgs>());
      expect(
        (args! as WorksheetPreviewArgs).worksheetId,
        'ws-c1-num-counting-1-10',
      );
    });

    // What the preview then shows is covered by worksheet_preview_test.dart,
    // against the rewritten preview screen.
  });

  group('layout', () {
    testWidgets('lays out on a small handset without overflow', (
      WidgetTester tester,
    ) async {
      await pump(tester, size: const Size(320, 2000));

      expect(tester.takeException(), isNull);
      expect(find.text('Create Worksheet'), findsOneWidget);
    });

    testWidgets('lays out on a tablet-sized screen without overflow', (
      WidgetTester tester,
    ) async {
      await pump(tester, size: const Size(900, 2000));

      expect(tester.takeException(), isNull);
    });

    testWidgets('back returns to whatever pushed this screen', (
      WidgetTester tester,
    ) async {
      final WorksheetGeneratorController c = buildController();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          onGenerateRoute: (RouteSettings settings) =>
              settings.name == AppRoutes.worksheet
                  ? MaterialPageRoute<void>(
                      settings: settings,
                      builder: (_) =>
                          WorksheetGeneratorScreen(controller: c),
                    )
                  : AppRouter.onGenerateRoute(settings),
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      Navigator.of(context).pushNamed(AppRoutes.worksheet),
                  child: const Text('open generator'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open generator'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(WorksheetGeneratorScreen.backKey));
      await tester.pumpAndSettle();

      expect(find.text('open generator'), findsOneWidget);
    });
  });
}

/// Starts a generation without awaiting it, so the in-flight state can be
/// inspected.
void unawaitedGenerate(WorksheetGeneratorController controller) {
  controller.generate();
}
