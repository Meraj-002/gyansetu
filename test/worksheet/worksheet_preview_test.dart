import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/app/theme.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/features/worksheet/services/local_worksheet_generation_service.dart';
import 'package:gyan_setu_ai/features/worksheet/services/worksheet_generation_service.dart';
import 'package:gyan_setu_ai/features/worksheet/services/worksheet_preview_controller.dart';
import 'package:gyan_setu_ai/features/worksheet/services/worksheet_repository.dart';
import 'package:gyan_setu_ai/features/worksheet/widgets/worksheet_paper.dart';
import 'package:gyan_setu_ai/features/worksheet/worksheet_preview_screen.dart';
import 'package:gyan_setu_ai/models/lesson.dart';
import 'package:gyan_setu_ai/models/question.dart';
import 'package:gyan_setu_ai/models/worksheet.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';
import 'package:gyan_setu_ai/services/worksheet_pdf_service.dart';

import '../lessons/lesson_test_doubles.dart';
import 'worksheet_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryWorksheetRepository worksheets;
  late FakeLessonRepository lessons;
  late FakeWorksheetOutputService output;
  late FakeWorksheetGenerationService generator;
  late PdfWorksheetService pdfService;
  late StaticConnectivityService connectivity;
  late LocalWorksheetGenerationService localGenerator;

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
    worksheets = InMemoryWorksheetRepository();
    lessons = FakeLessonRepository(catalogue: <Lesson>[countingLesson()]);
    output = FakeWorksheetOutputService();
    generator = FakeWorksheetGenerationService();
    pdfService = PdfWorksheetService();
    connectivity = StaticConnectivityService(ConnectionStatus.offline);
    localGenerator = LocalWorksheetGenerationService();
  });

  Future<Worksheet> makeWorksheet({
    int questions = 10,
    TargetLanguage target = TargetLanguage.santali,
    int classNumber = 1,
    WorksheetDifficulty difficulty = WorksheetDifficulty.easy,
    int variant = 0,
  }) =>
      localGenerator.generate(
        testRequest(
          numberOfQuestions: questions,
          target: target,
          classNumber: classNumber,
          difficulty: difficulty,
        ).copyWithVariant(variant),
      );

  WorksheetPreviewController buildController(
    Worksheet worksheet, {
    WorksheetPdfService? pdf,
    WorksheetGenerationService? gen,
  }) {
    final WorksheetPreviewController controller = WorksheetPreviewController(
      worksheetId: worksheet.id,
      worksheets: worksheets,
      pdfService: pdf ?? pdfService,
      output: output,
      lessons: lessons,
      connectivity: connectivity,
      generator: gen ?? generator,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<WorksheetPreviewController> pump(
    WidgetTester tester,
    Worksheet worksheet, {
    Size size = const Size(430, 2600),
    WorksheetPdfService? pdf,
    WorksheetGenerationService? gen,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final WorksheetPreviewController controller =
        buildController(worksheet, pdf: pdf, gen: gen);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: WorksheetPreviewScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  group('loading', () {
    testWidgets('loads the worksheet named by the id it was given', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet();
      await worksheets.save(worksheet);
      final WorksheetPreviewController c = await pump(tester, worksheet);

      expect(c.worksheet!.id, worksheet.id);
      expect(c.worksheet!.lessonId, 'c1-num-counting-1-10');
    });

    testWidgets('an unknown id shows the error state with a retry', (
      WidgetTester tester,
    ) async {
      final WorksheetPreviewController controller =
          WorksheetPreviewController(
        worksheetId: 'missing',
        worksheets: worksheets,
        pdfService: pdfService,
        output: output,
        lessons: lessons,
        connectivity: connectivity,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: WorksheetPreviewScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load this worksheet."), findsOneWidget);
      expect(find.byKey(WorksheetPreviewScreen.retryKey), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
    });
  });

  group('worksheet paper', () {
    testWidgets('shows the class, subject, topic and language pair', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet();
      await worksheets.save(worksheet);
      await pump(tester, worksheet);

      expect(find.text('Class 1   •   Numeracy'), findsOneWidget);
      expect(find.text('Topic: Counting 1–10'), findsOneWidget);
      expect(find.text('Language: Hindi + Santali'), findsOneWidget);
      expect(find.text('Name:'), findsOneWidget);
      expect(find.text('Date:'), findsOneWidget);
    });

    testWidgets('follows a worksheet built for another class and language', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet(
        target: TargetLanguage.mundari,
        classNumber: 2,
      );
      await worksheets.save(worksheet);
      await pump(tester, worksheet);

      expect(find.text('Class 2   •   Numeracy'), findsOneWidget);
      expect(find.text('Language: Hindi + Mundari'), findsOneWidget);
      expect(find.textContaining('Santali'), findsNothing);
    });

    testWidgets('renders exactly the generated questions, in order', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet(questions: 5);
      await worksheets.save(worksheet);
      await pump(tester, worksheet);

      expect(find.byType(PaperQuestion), findsNWidgets(5));
      for (int i = 1; i <= 5; i++) {
        expect(find.text('$i.'), findsOneWidget);
      }
    });

    testWidgets('renders the Hindi question text as generated', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet(questions: 5);
      await worksheets.save(worksheet);
      await pump(tester, worksheet);

      expect(find.text(worksheet.questions.first.questionText), findsWidgets);
      expect(worksheet.questions.first.questionText, contains('सेब'));
    });

    testWidgets('draws the counted objects, not an image from the network', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet(
        questions: 5,
      );
      await worksheets.save(worksheet);
      await pump(tester, worksheet);

      expect(find.byType(WorksheetObjects), findsWidgets);
      // Nothing on the paper is an Image, so nothing needs a connection.
      expect(
        find.descendant(
          of: find.byKey(WorksheetPreviewScreen.paperKey),
          matching: find.byType(Image),
        ),
        findsNothing,
      );
    });

    testWidgets('a question with no picture says so instead of breaking', (
      WidgetTester tester,
    ) async {
      final Worksheet base = await makeWorksheet(questions: 5);
      final Worksheet broken = worksheetWith(
        base,
        questions: <WorksheetQuestion>[
          WorksheetQuestion(
            id: base.questions.first.id,
            type: QuestionType.countingObjects,
            questionText: base.questions.first.questionText,
            correctAnswer: base.questions.first.correctAnswer,
            order: 1,
            // Names an object this build cannot draw.
            visualAsset: 'spaceship',
            visualCount: 3,
          ),
          ...base.questions.skip(1),
        ],
      );
      await worksheets.save(broken);
      await pump(tester, broken);

      expect(find.text('No picture for this question.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('says which questions have no mother-tongue text', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet(questions: 5);
      await worksheets.save(worksheet);
      await pump(tester, worksheet);

      expect(
        find.text('No Santali text for this question yet.'),
        findsWidgets,
      );
    });

    testWidgets('shows the bilingual line when a translation exists', (
      WidgetTester tester,
    ) async {
      final LocalWorksheetGenerationService bilingual =
          LocalWorksheetGenerationService(
        translator: FakeWorksheetTranslator(translated: 'Kete ul menaka?'),
      );
      final Worksheet worksheet =
          await bilingual.generate(testRequest(numberOfQuestions: 5));
      await worksheets.save(worksheet);
      await pump(tester, worksheet);

      expect(find.text('Kete ul menaka?'), findsWidgets);
    });

    testWidgets('the answer key is hidden until the teacher asks for it', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet(questions: 5);
      await worksheets.save(worksheet);
      await pump(tester, worksheet);

      expect(find.textContaining('Answer:'), findsNothing);

      await tester.tap(find.byKey(WorksheetPreviewScreen.moreKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(WorksheetPreviewScreen.answersKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('Answer:'), findsWidgets);
    });
  });

  group('status', () {
    testWidgets('a locally generated worksheet is not called AI-generated', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet();
      await worksheets.save(worksheet);
      await pump(tester, worksheet);

      expect(find.text('Generated Offline'), findsOneWidget);
      expect(find.text('Curriculum aligned'), findsOneWidget);
      expect(find.text('AI-Generated'), findsNothing);
    });

    testWidgets('a model-written worksheet earns the AI label', (
      WidgetTester tester,
    ) async {
      final Worksheet base = await makeWorksheet();
      final Worksheet ai = worksheetWith(
        base,
        source: GenerationSource.remoteAi,
      );
      await worksheets.save(ai);
      await pump(tester, ai);

      expect(find.text('AI-Generated'), findsOneWidget);
    });
  });

  group('pdf', () {
    test('builds real bytes with the pages the indicator promised', () async {
      final Worksheet worksheet = await makeWorksheet(questions: 5);
      final WorksheetPdf pdf = await pdfService.build(worksheet);

      expect(pdf.bytes, isNotEmpty);
      expect(pdf.bytes.length, greaterThan(1000));
      // A real PDF begins with %PDF-.
      expect(
        String.fromCharCodes(pdf.bytes.take(5)),
        '%PDF-',
      );
      expect(pdf.pageCount, pdfService.pageCountFor(worksheet));
    });

    test('paginates instead of squeezing every question onto one page',
        () async {
      final Worksheet five = await makeWorksheet(questions: 5);
      final Worksheet ten = await makeWorksheet(questions: 10);
      final Worksheet fifteen = await makeWorksheet(questions: 15);

      // Five per page, plus the answer key page.
      expect(pdfService.pageCountFor(five), 2);
      expect(pdfService.pageCountFor(ten), 3);
      expect(pdfService.pageCountFor(fifteen), 4);
      expect(pdfService.pageCountFor(five, includeAnswerKey: false), 1);

      expect((await pdfService.build(fifteen)).pageCount, 4);
    });

    test('names the file after the lesson and the class', () async {
      final Worksheet worksheet = await makeWorksheet();

      expect(
        pdfService.fileNameFor(worksheet),
        'GyanSetu_Counting_1-10_Class_1.pdf',
      );
    });

    test('a longer worksheet produces a bigger document', () async {
      final Worksheet five = await makeWorksheet(questions: 5);
      final Worksheet fifteen = await makeWorksheet(questions: 15);

      expect(
        (await pdfService.build(fifteen)).bytes.length,
        greaterThan((await pdfService.build(five)).bytes.length),
      );
    });

    testWidgets('Download builds the PDF and reports where it went', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet(questions: 5);
      await worksheets.save(worksheet);
      final WorksheetPreviewController c = await pump(tester, worksheet);

      await tester.runAsync(c.savePdf);
      await tester.pumpAndSettle();

      expect(c.pdf, isNotNull);
      expect(c.pdf!.bytes, isNotEmpty);
      // The test host has no writable app directory, so the controller says so
      // rather than reporting a save that never happened.
      expect(c.message, isNotNull);
    });

    testWidgets('Print sends the same bytes the preview was built from', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet(questions: 5);
      await worksheets.save(worksheet);
      final WorksheetPreviewController c = await pump(tester, worksheet);

      await tester.runAsync(c.printPdf);
      await tester.pumpAndSettle();

      expect(output.printed, isNotNull);
      expect(output.printed!.bytes, c.pdf!.bytes);
    });

    testWidgets('Share sends the same bytes as well', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet(questions: 5);
      await worksheets.save(worksheet);
      final WorksheetPreviewController c = await pump(tester, worksheet);

      await tester.runAsync(c.sharePdf);
      await tester.pumpAndSettle();

      expect(output.shared, isNotNull);
      expect(output.shared!.bytes, c.pdf!.bytes);
      expect(output.shared!.fileName, endsWith('.pdf'));
    });

    testWidgets('a device that cannot print says so and does not pretend', (
      WidgetTester tester,
    ) async {
      output.canPrint = false;
      final Worksheet worksheet = await makeWorksheet(questions: 5);
      await worksheets.save(worksheet);
      final WorksheetPreviewController c = await pump(tester, worksheet);

      final bool printed = (await tester.runAsync(c.printPdf))!;
      await tester.pumpAndSettle();

      expect(printed, isFalse);
      expect(c.message, 'Printing isn’t available on this device.');
      expect(output.printed, isNull);
    });

    testWidgets('a PDF failure is reported, not swallowed', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet(questions: 5);
      await worksheets.save(worksheet);
      final WorksheetPreviewController c = await pump(
        tester,
        worksheet,
        pdf: FailingPdfService(),
      );

      await tester.runAsync(c.savePdf);
      await tester.pumpAndSettle();

      expect(c.lastActionFailed, isTrue);
      expect(c.message, 'Couldn’t save the worksheet.');
    });

    testWidgets('an empty document is never handed on', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet(questions: 5);
      await worksheets.save(worksheet);
      final WorksheetPreviewController c = await pump(
        tester,
        worksheet,
        pdf: EmptyPdfService(),
      );

      await tester.runAsync(c.savePdf);
      await tester.pumpAndSettle();

      expect(c.lastActionFailed, isTrue);
      expect(output.printed, isNull);
    });

    testWidgets('one heavy job at a time', (WidgetTester tester) async {
      final Worksheet worksheet = await makeWorksheet(questions: 5);
      await worksheets.save(worksheet);
      final WorksheetPreviewController c = await pump(
        tester,
        worksheet,
        pdf: SlowPdfService(pdfService),
      );

      await tester.runAsync(() async {
        final Future<void> first = c.savePdf();
        // A second heavy job is refused while the first is running.
        expect(c.busy, isTrue);
        await c.printPdf();
        await first;
      });
      await tester.pumpAndSettle();

      expect(output.printed, isNull);
    });
  });

  group('regenerate', () {
    testWidgets('asks before replacing the worksheet', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet(questions: 5);
      await worksheets.save(worksheet);
      await pump(tester, worksheet, gen: generator);

      await tester.tap(find.byKey(WorksheetPreviewScreen.regenerateKey));
      await tester.pumpAndSettle();

      expect(find.text('Generate a new worksheet?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(generator.calls, 0);
    });

    testWidgets('keeps every choice and changes the sheet', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet(
        questions: 5,
        difficulty: WorksheetDifficulty.medium,
      );
      await worksheets.save(worksheet);
      final WorksheetPreviewController c =
          await pump(tester, worksheet, gen: localGenerator);

      final Worksheet? next =
          await tester.runAsync<Worksheet?>(() => c.regenerate());
      await tester.pumpAndSettle();

      expect(next, isNotNull);
      expect(next!.id, isNot(worksheet.id));
      expect(next.variant, worksheet.variant + 1);

      // Everything the teacher chose survives.
      expect(next.lessonId, worksheet.lessonId);
      expect(next.classNumber, worksheet.classNumber);
      expect(next.difficulty, WorksheetDifficulty.medium);
      expect(next.questionCount, 5);
      expect(next.questionTypes, worksheet.questionTypes);
      expect(next.targetLanguage, worksheet.targetLanguage);
      expect(next.teachingLanguage, worksheet.teachingLanguage);
      expect(next.visualExamples, worksheet.visualExamples);
      expect(
        next.culturallyFamiliarExamples,
        worksheet.culturallyFamiliarExamples,
      );

      // And it is a different sheet, not the same one again.
      expect(
        <String>[for (final WorksheetQuestion q in next.questions) q.correctAnswer],
        isNot(<String>[
          for (final WorksheetQuestion q in worksheet.questions) q.correctAnswer,
        ]),
      );
    });

    testWidgets('saves the new worksheet and drops the old PDF', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet(questions: 5);
      await worksheets.save(worksheet);
      final WorksheetPreviewController c =
          await pump(tester, worksheet, gen: localGenerator);

      await tester.runAsync(c.savePdf);
      expect(c.pdf, isNotNull);

      final Worksheet? next =
          await tester.runAsync<Worksheet?>(() => c.regenerate());
      await tester.pumpAndSettle();

      expect(worksheets.values[next!.id], isNotNull);
      // The old document belonged to the old worksheet.
      expect(c.pdf, isNull);
      expect(c.savedFile, isNull);
    });

    testWidgets('a generation failure is reported plainly', (
      WidgetTester tester,
    ) async {
      generator.failure = const WorksheetGenerationFailure(
        WorksheetFailureReason.failed,
        'Couldn’t generate a new worksheet.',
      );
      final Worksheet worksheet = await makeWorksheet(questions: 5);
      await worksheets.save(worksheet);
      final WorksheetPreviewController c =
          await pump(tester, worksheet, gen: generator);

      await tester.runAsync(c.regenerate);
      await tester.pumpAndSettle();

      expect(c.lastActionFailed, isTrue);
      expect(c.message, 'Couldn’t generate a new worksheet.');
      // The teacher keeps the sheet they had.
      expect(c.worksheet!.id, worksheet.id);
    });
  });

  group('chrome', () {
    testWidgets('carries GyanSetu AI branding and no other', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet(questions: 5);
      await worksheets.save(worksheet);
      await pump(tester, worksheet);

      expect(
        find.textContaining('GyanSetu AI', findRichText: true),
        findsWidgets,
      );
      expect(
        find.textContaining('BhashaSetu', findRichText: true),
        findsNothing,
      );
    });

    testWidgets('shows the real page count', (WidgetTester tester) async {
      final Worksheet worksheet = await makeWorksheet(questions: 15);
      await worksheets.save(worksheet);
      // Tall enough that the indicator below fifteen questions is built.
      await pump(tester, worksheet, size: const Size(430, 4600));

      expect(find.text('1 / 4'), findsOneWidget);
    });

    testWidgets('the footer claims only what the app does', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet(questions: 5);
      await worksheets.save(worksheet);
      await pump(tester, worksheet);

      expect(
        find.text('Works offline. No internet required.'),
        findsOneWidget,
      );
      expect(
        find.text('Designed for every child. In every language.'),
        findsOneWidget,
      );
    });

    testWidgets('back returns to whatever pushed this screen', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet(questions: 5);
      await worksheets.save(worksheet);
      final WorksheetPreviewController controller =
          buildController(worksheet);

      tester.view.physicalSize = const Size(430, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          WorksheetPreviewScreen(controller: controller),
                    ),
                  ),
                  child: const Text('open preview'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open preview'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(WorksheetPreviewScreen.backKey));
      await tester.pumpAndSettle();

      expect(find.text('open preview'), findsOneWidget);
    });
  });

  group('validation', () {
    testWidgets('a broken worksheet is flagged rather than shown as fine', (
      WidgetTester tester,
    ) async {
      final Worksheet base = await makeWorksheet(questions: 10);
      final Worksheet short = worksheetWith(
        base,
        questions: base.questions.take(3).toList(),
      );
      await worksheets.save(short);
      final WorksheetPreviewController c = await pump(tester, short);

      expect(c.isValid, isFalse);
      expect(find.text('This worksheet has a problem.'), findsOneWidget);
    });
  });

  group('layout', () {
    testWidgets('lays out on a small handset without overflow', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet(questions: 5);
      await worksheets.save(worksheet);
      await pump(tester, worksheet, size: const Size(320, 2600));

      expect(tester.takeException(), isNull);
      expect(find.text('Worksheet Preview'), findsOneWidget);
    });

    testWidgets('lays out on a tablet-sized screen without overflow', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet(questions: 5);
      await worksheets.save(worksheet);
      await pump(tester, worksheet, size: const Size(900, 2600));

      expect(tester.takeException(), isNull);
    });

    testWidgets('handles fifteen questions without overflow', (
      WidgetTester tester,
    ) async {
      final Worksheet worksheet = await makeWorksheet(questions: 15);
      await worksheets.save(worksheet);
      await pump(tester, worksheet, size: const Size(390, 4200));

      expect(tester.takeException(), isNull);
      expect(find.byType(PaperQuestion), findsNWidgets(15));
    });
  });
}

/// A print and share target the test can inspect.
class FakeWorksheetOutputService implements WorksheetOutputService {
  FakeWorksheetOutputService({this.canPrint = true, this.canShare = true});

  bool canPrint;
  bool canShare;

  WorksheetPdf? printed;
  WorksheetPdf? shared;

  @override
  Future<PrintingCapability> capability() async =>
      PrintingCapability(canPrint: canPrint, canShare: canShare);

  @override
  Future<bool> printPdf(WorksheetPdf pdf) async {
    printed = pdf;
    return true;
  }

  @override
  Future<bool> sharePdf(WorksheetPdf pdf) async {
    shared = pdf;
    return true;
  }
}

class FailingPdfService implements WorksheetPdfService {
  @override
  Future<WorksheetPdf> build(
    Worksheet worksheet, {
    bool includeAnswerKey = true,
  }) async =>
      throw StateError('pdf engine unavailable');

  @override
  String fileNameFor(Worksheet worksheet) => 'x.pdf';

  @override
  int pageCountFor(Worksheet worksheet, {bool includeAnswerKey = true}) => 1;
}

class EmptyPdfService implements WorksheetPdfService {
  @override
  Future<WorksheetPdf> build(
    Worksheet worksheet, {
    bool includeAnswerKey = true,
  }) async =>
      WorksheetPdf(bytes: Uint8List(0), pageCount: 1, fileName: 'x.pdf');

  @override
  String fileNameFor(Worksheet worksheet) => 'x.pdf';

  @override
  int pageCountFor(Worksheet worksheet, {bool includeAnswerKey = true}) => 1;
}

/// Holds the build open so the in-flight state can be inspected.
class SlowPdfService implements WorksheetPdfService {
  SlowPdfService(this._inner);

  final WorksheetPdfService _inner;

  @override
  Future<WorksheetPdf> build(
    Worksheet worksheet, {
    bool includeAnswerKey = true,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return _inner.build(worksheet, includeAnswerKey: includeAnswerKey);
  }

  @override
  String fileNameFor(Worksheet worksheet) => _inner.fileNameFor(worksheet);

  @override
  int pageCountFor(Worksheet worksheet, {bool includeAnswerKey = true}) =>
      _inner.pageCountFor(worksheet, includeAnswerKey: includeAnswerKey);
}
