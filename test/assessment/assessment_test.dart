import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/app/routes.dart';
import 'package:gyan_setu_ai/app/theme.dart';
import 'package:gyan_setu_ai/data/assessment_questions.dart';
import 'package:gyan_setu_ai/features/assessment/assessment_result_screen.dart';
import 'package:gyan_setu_ai/features/assessment/assessment_screen.dart';
import 'package:gyan_setu_ai/features/assessment/services/assessment_controller.dart';
import 'package:gyan_setu_ai/features/assessment/services/assessment_recommendation_service.dart';
import 'package:gyan_setu_ai/features/assessment/services/quiz_repository.dart';
import 'package:gyan_setu_ai/features/assessment/widgets/assessment_widgets.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/models/assessment_answer.dart';
import 'package:gyan_setu_ai/models/assessment_question.dart';
import 'package:gyan_setu_ai/models/assessment_result.dart';
import 'package:gyan_setu_ai/models/lesson.dart';
import 'package:gyan_setu_ai/services/audio/audio_resource_store.dart';
import 'package:gyan_setu_ai/services/audio/lesson_audio_service.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';

import '../classroom/live_classroom_doubles.dart' show FakeClipPlayer;
import '../lessons/lesson_detail_services_test.dart' show FakeTts;
import '../lessons/lesson_test_doubles.dart';
import '../setup/setup_test_doubles.dart' as setup_doubles;

const String kLessonId = AssessmentQuestionData.countingLessonId;

/// Holds the load open so the skeleton is observable.
class SlowQuizQuestionSource implements QuizQuestionSource {
  const SlowQuizQuestionSource();

  @override
  Future<List<QuizQuestion>> forLesson(String lessonId) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return AssessmentQuestionData.forLesson(lessonId);
  }
}

/// A short assessment, so a test can answer all of it without ten taps.
List<QuizQuestion> shortQuiz() => <QuizQuestion>[
      QuizQuestion(
        id: 'a',
        concept: QuizConcept.numbers1to5,
        prompt: 'Count the apples.',
        promptHindi: 'सेब गिनिए।',
        visual: const CountableObjects(QuizObject.apple, 3),
        options: const <QuizOption>[
          QuizOption(id: 'n2', label: '2'),
          QuizOption(id: 'n3', label: '3'),
          QuizOption(id: 'n4', label: '4'),
          QuizOption(id: 'n5', label: '5'),
        ],
        correctOptionId: 'n3',
      ),
      QuizQuestion(
        id: 'b',
        concept: QuizConcept.numbers6to10,
        prompt: 'Count the leaves.',
        promptHindi: 'पत्ते गिनिए।',
        visual: const CountableObjects(QuizObject.leaf, 7),
        options: const <QuizOption>[
          QuizOption(id: 'n6', label: '6'),
          QuizOption(id: 'n7', label: '7'),
          QuizOption(id: 'n8', label: '8'),
          QuizOption(id: 'n9', label: '9'),
        ],
        correctOptionId: 'n7',
      ),
    ];

void main() {
  late InMemorySecureStorageService storage;
  late setup_doubles.TestRepository classrooms;
  late FakeLessonRepository lessons;
  late FakeTts tts;
  late TtsLessonAudioService audio;
  late StaticConnectivityService connectivity;
  late DateTime clock;

  Lesson countingLesson() => Lesson(
        id: kLessonId,
        title: 'Counting 1–10',
        description: 'Count everyday objects aloud.',
        subject: ClassroomSubject.numeracy,
        classNumber: 1,
        learningOutcome: 'Count objects from 1 to 10.',
        durationMinutes: 10,
        lessonOrder: 1,
        createdAt: DateTime(2026, 6, 1),
        updatedAt: DateTime(2026, 6, 1),
      );

  setUp(() {
    storage = InMemorySecureStorageService();
    classrooms = setup_doubles.TestRepository(existing: testClassroom());
    lessons = FakeLessonRepository(catalogue: <Lesson>[countingLesson()]);
    // The engine knows Hindi and nothing else, which is the real situation on
    // an Android phone: no tribal language has a voice.
    tts = FakeTts(languages: <String>{'hi-IN'}, canSynthesiseToFile: false);
    connectivity = StaticConnectivityService(ConnectionStatus.offline);
    audio = TtsLessonAudioService(
      tts: tts,
      store: InMemoryAudioResourceStore(),
      player: FakeClipPlayer(),
      connectivity: connectivity,
    );
    clock = DateTime(2026, 8, 29, 10);
  });

  AssessmentController buildController({
    QuizRepository? quizzes,
    String lessonId = kLessonId,
    TargetLanguage target = TargetLanguage.santali,
  }) {
    if (target != TargetLanguage.santali) {
      classrooms = setup_doubles.TestRepository(
        existing: testClassroom(target: target),
      );
    }
    final AssessmentController controller = AssessmentController(
      quizzes: quizzes ?? LocalQuizRepository(storage: storage),
      classrooms: classrooms,
      audio: audio,
      connectivity: connectivity,
      teacherId: kTeacherId,
      lessonId: lessonId,
      lessons: lessons,
      recommendations: const LocalAssessmentRecommendationService(),
      clock: () => clock,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<AssessmentController> settle(AssessmentController c) async {
    while (c.stage == AssessmentStage.loading) {
      await Future<void>.delayed(Duration.zero);
    }
    return c;
  }

  /// Answers every question with the option named by [pick].
  Future<void> answerAll(
    AssessmentController c,
    String Function(QuizQuestion question) pick,
  ) async {
    for (int i = 0; i < c.total; i++) {
      await c.goTo(i);
      await c.select(pick(c.questions[i]));
    }
  }

  String correctFor(QuizQuestion q) => q.correctOptionId;

  String wrongFor(QuizQuestion q) =>
      q.options.firstWhere((QuizOption o) => o.id != q.correctOptionId).id;

  Future<AssessmentController> pump(
    WidgetTester tester, {
    AssessmentController? controller,
    QuizRepository? quizzes,
    Size size = const Size(430, 2400),
    RouteFactory? routes,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AssessmentController c =
        controller ?? buildController(quizzes: quizzes);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        onGenerateRoute: routes ?? AppRouter.onGenerateRoute,
        home: AssessmentScreen(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> reveal(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pumpAndSettle();
  }

  // --- The bundled questions ----------------------------------------------

  group('data', () {
    test('the counting lesson has ten questions', () {
      expect(AssessmentQuestionData.forLesson(kLessonId), hasLength(10));
    });

    test('every question offers four options including the right one', () {
      for (final QuizQuestion q in AssessmentQuestionData.countingOneToTen()) {
        expect(q.options, hasLength(4), reason: q.id);
        expect(
          q.options.map((QuizOption o) => o.id),
          contains(q.correctOptionId),
          reason: q.id,
        );
        // Two tiles showing the same numeral would make one of them wrong for
        // no reason a child could see.
        expect(
          q.options.map((QuizOption o) => o.label).toSet(),
          hasLength(4),
          reason: q.id,
        );
      }
    });

    test('the pictured group always matches the correct answer', () {
      for (final QuizQuestion q in AssessmentQuestionData.countingOneToTen()) {
        final QuizVisual? visual = q.visual;
        if (visual == null) continue;
        expect(visual.total.toString(), q.correctOption.label, reason: q.id);
      }
    });

    test('every picture is a bundled asset, never a URL', () {
      for (final QuizObject o in QuizObject.values) {
        expect(o.asset, startsWith('assets/'));
        expect(o.asset, isNot(contains('http')));
      }
    });

    test('the questions cover all six concepts', () {
      final Set<QuizConcept> covered = <QuizConcept>{
        for (final QuizQuestion q in AssessmentQuestionData.countingOneToTen())
          q.concept,
      };
      expect(covered, QuizConcept.values.toSet());
    });

    test('a lesson with no questions returns none rather than inventing any',
        () {
      expect(AssessmentQuestionData.forLesson('c1-num-shapes'), isEmpty);
      expect(AssessmentQuestionData.hasQuestionsFor('c1-num-shapes'), isFalse);
    });

    test('no question claims a mother-tongue wording nobody has written', () {
      for (final QuizQuestion q in AssessmentQuestionData.countingOneToTen()) {
        for (final TargetLanguage l in TargetLanguage.values) {
          expect(q.spokenTextFor(l), isNull, reason: '${q.id} / ${l.name}');
        }
      }
    });
  });

  // --- Marking -------------------------------------------------------------

  group('result', () {
    QuizResult resultFor(List<String> chosen) {
      final List<QuizQuestion> questions = shortQuiz();
      return QuizResult.from(
        lessonId: kLessonId,
        questions: questions,
        answers: <String, QuizAnswer>{
          for (int i = 0; i < chosen.length; i++)
            questions[i].id: QuizAnswer(
              questionId: questions[i].id,
              selectedOptionId: chosen[i],
              correct: questions[i].isCorrect(chosen[i]),
              answeredAt: DateTime(2026, 8, 29, 10, i),
            ),
        },
        startedAt: DateTime(2026, 8, 29, 10),
        finishedAt: DateTime(2026, 8, 29, 10, 2, 30),
      );
    }

    test('the score is the number of correct answers', () {
      expect(resultFor(<String>['n3', 'n7']).score, 2);
      expect(resultFor(<String>['n3', 'n8']).score, 1);
      expect(resultFor(<String>['n2', 'n8']).score, 0);
    });

    test('a concept is understood only when every question for it is right',
        () {
      final QuizResult mixed = resultFor(<String>['n3', 'n8']);

      expect(
        mixed.understood.map((ConceptPerformance c) => c.concept),
        <QuizConcept>[QuizConcept.numbers1to5],
      );
      expect(
        mixed.needsReinforcement.map((ConceptPerformance c) => c.concept),
        <QuizConcept>[QuizConcept.numbers6to10],
      );
    });

    test('the percentage is rounded from the real counts', () {
      expect(resultFor(<String>['n3', 'n8']).percentage, 50);
      expect(resultFor(<String>['n3', 'n7']).percentage, 100);
    });

    test('an unanswered question is marked wrong, not skipped', () {
      final QuizResult partial = resultFor(<String>['n3']);

      expect(partial.total, 2);
      expect(partial.score, 1);
      expect(partial.percentage, 50);
    });

    test('marking is redone against the questions, not the stored flag', () {
      final List<QuizQuestion> questions = shortQuiz();
      final QuizResult result = QuizResult.from(
        lessonId: kLessonId,
        questions: questions,
        answers: <String, QuizAnswer>{
          'a': QuizAnswer(
            questionId: 'a',
            selectedOptionId: 'n2',
            // A stale record that claims to be right. The question disagrees.
            correct: true,
            answeredAt: DateTime(2026, 8, 29, 10),
          ),
        },
        startedAt: DateTime(2026, 8, 29, 10),
        finishedAt: DateTime(2026, 8, 29, 10, 1),
      );

      expect(result.score, 0);
    });

    test('a duration that was never measured reads as a dash', () {
      final QuizResult result = QuizResult.from(
        lessonId: kLessonId,
        questions: shortQuiz(),
        answers: const <String, QuizAnswer>{},
        startedAt: DateTime(2026, 8, 29, 10),
        finishedAt: DateTime(2026, 8, 29, 10),
      );

      expect(result.durationLabel, '--');
    });

    test('a result survives a round trip through storage', () {
      final QuizResult before = resultFor(<String>['n3', 'n8']);
      final QuizResult after = QuizResult.fromJson(before.toJson());

      expect(after.score, before.score);
      expect(after.total, before.total);
      expect(after.percentage, before.percentage);
      expect(after.concepts, hasLength(before.concepts.length));
      expect(after.answers.keys, before.answers.keys);
    });
  });

  // --- What to practise next ----------------------------------------------

  group('recommendation', () {
    const LocalAssessmentRecommendationService rules =
        LocalAssessmentRecommendationService();

    QuizResult resultWith({required int correct, required int total}) {
      final List<QuizQuestion> questions = <QuizQuestion>[
        for (int i = 0; i < total; i++)
          QuizQuestion(
            id: 'q$i',
            concept: i.isEven
                ? QuizConcept.numbers1to5
                : QuizConcept.countingMixedObjects,
            prompt: 'Count.',
            promptHindi: 'गिनिए।',
            options: const <QuizOption>[
              QuizOption(id: 'right', label: '1'),
              QuizOption(id: 'wrong', label: '2'),
            ],
            correctOptionId: 'right',
          ),
      ];
      return QuizResult.from(
        lessonId: kLessonId,
        questions: questions,
        answers: <String, QuizAnswer>{
          for (int i = 0; i < total; i++)
            'q$i': QuizAnswer(
              questionId: 'q$i',
              selectedOptionId: i < correct ? 'right' : 'wrong',
              correct: i < correct,
              answeredAt: DateTime(2026, 8, 29, 10, i),
            ),
        },
        startedAt: DateTime(2026, 8, 29, 10),
        finishedAt: DateTime(2026, 8, 29, 10, 5),
      );
    }

    test('everything correct suggests moving on', () {
      final PracticeSuggestion s = rules.suggest(
        resultWith(correct: 10, total: 10),
      );

      expect(s.action, SuggestedAction.moveOn);
      expect(s.concepts, isEmpty);
    });

    test('a high score with one weak concept suggests a worksheet', () {
      final PracticeSuggestion s = rules.suggest(
        resultWith(correct: 8, total: 10),
      );

      expect(s.action, SuggestedAction.worksheet);
      expect(s.body, contains('Counting Mixed Objects'));
    });

    test('a middling score suggests going back to flashcards', () {
      final PracticeSuggestion s = rules.suggest(
        resultWith(correct: 5, total: 10),
      );

      expect(s.action, SuggestedAction.flashcards);
    });

    test('a low score suggests teaching the lesson again', () {
      final PracticeSuggestion s = rules.suggest(
        resultWith(correct: 2, total: 10),
      );

      expect(s.action, SuggestedAction.repeatLesson);
    });

    test('the same result always gives the same suggestion', () {
      final QuizResult result = resultWith(correct: 8, total: 10);

      expect(rules.suggest(result).body, rules.suggest(result).body);
    });

    test('the suggestion never claims to have been written by a model', () {
      for (final int correct in <int>[0, 5, 8, 10]) {
        final PracticeSuggestion s =
            rules.suggest(resultWith(correct: correct, total: 10));

        expect(s.sourceNote, contains('rule on this phone'));
        expect(s.sourceNote.toLowerCase(), isNot(contains('ai ')));
        expect(s.headline.toLowerCase(), isNot(contains('ai ')));
      }
    });
  });

  // --- The controller ------------------------------------------------------

  group('controller', () {
    test('loads the lesson and starts at the first question', () async {
      final AssessmentController c = await settle(buildController());

      expect(c.stage, AssessmentStage.inProgress);
      expect(c.total, 10);
      expect(c.index, 0);
      expect(c.progressLabel, 'Question 1 of 10');
      expect(c.subtitle, 'Class 1  •  Counting 1–10');
    });

    test('progress counts answers given, not questions paged past', () async {
      final AssessmentController c = await settle(buildController());

      expect(c.percentComplete, 0);
      await c.select(c.current!.correctOptionId);
      expect(c.percentComplete, 10);

      await c.next();
      // Paging on does not move the bar; answering does.
      expect(c.progressLabel, 'Question 2 of 10');
      expect(c.percentComplete, 10);

      await c.select(c.current!.correctOptionId);
      expect(c.percentComplete, 20);
    });

    test('choosing an option records it without moving on', () async {
      final AssessmentController c = await settle(buildController());
      final String first = c.current!.id;

      await c.select(c.current!.correctOptionId);

      expect(c.index, 0);
      expect(c.isAnswered, isTrue);
      expect(c.answers[first]!.correct, isTrue);
    });

    test('Next refuses while the question is unanswered and says why',
        () async {
      final AssessmentController c = await settle(buildController());

      await c.next();

      expect(c.index, 0);
      expect(c.message, 'Choose an answer before moving on.');
    });

    test('going back keeps the answer that was given', () async {
      final AssessmentController c = await settle(buildController());
      final String chosen = c.current!.options.last.id;

      await c.select(chosen);
      await c.next();
      expect(c.selectedOptionId, isNull);

      await c.previous();

      expect(c.index, 0);
      expect(c.selectedOptionId, chosen);
    });

    test('changing an answer replaces it rather than adding a second',
        () async {
      final AssessmentController c = await settle(buildController());
      final QuizQuestion q = c.current!;

      await c.select(q.options.first.id);
      await c.select(q.options.last.id);

      expect(c.answers, hasLength(1));
      expect(c.selectedOptionId, q.options.last.id);
    });

    test('there is no result until every question is answered', () async {
      final AssessmentController c = await settle(buildController());

      for (int i = 0; i < c.total - 1; i++) {
        await c.goTo(i);
        await c.select(c.questions[i].correctOptionId);
      }

      expect(c.allAnswered, isFalse);
      expect(c.result, isNull);
      expect(c.suggestion, isNull);
      expect(c.stage, AssessmentStage.inProgress);
    });

    test('the result appears on the last answer', () async {
      final AssessmentController c = await settle(buildController());
      await answerAll(c, correctFor);

      expect(c.stage, AssessmentStage.completed);
      expect(c.result!.score, 10);
      expect(c.result!.percentage, 100);
      expect(c.suggestion!.action, SuggestedAction.moveOn);
    });

    test('a wrong answer is scored as wrong', () async {
      final AssessmentController c = await settle(buildController());
      await answerAll(c, wrongFor);

      expect(c.result!.score, 0);
      expect(c.result!.understood, isEmpty);
      expect(c.result!.needsReinforcement, hasLength(QuizConcept.values.length));
    });

    test('changing an answer after finishing recomputes the score', () async {
      final AssessmentController c = await settle(buildController());
      await answerAll(c, correctFor);
      expect(c.result!.score, 10);

      await c.goTo(0);
      await c.select(wrongFor(c.questions.first));

      expect(c.stage, AssessmentStage.completed);
      expect(c.result!.score, 9);
    });

    test('an interrupted assessment resumes at the first unanswered question',
        () async {
      final LocalQuizRepository quizzes =
          LocalQuizRepository(storage: storage);
      final AssessmentController first =
          await settle(buildController(quizzes: quizzes));

      for (int i = 0; i < 3; i++) {
        await first.goTo(i);
        await first.select(first.questions[i].correctOptionId);
      }

      final AssessmentController resumed = await settle(
        buildController(quizzes: LocalQuizRepository(storage: storage)),
      );

      expect(resumed.answeredCount, 3);
      expect(resumed.index, 3);
      expect(resumed.progressLabel, 'Question 4 of 10');
    });

    test('starting again clears every answer', () async {
      final AssessmentController c = await settle(buildController());
      await answerAll(c, correctFor);

      await c.restart();

      expect(c.answeredCount, 0);
      expect(c.index, 0);
      expect(c.result, isNull);
      expect(c.stage, AssessmentStage.inProgress);
    });

    test('a finished result is kept for the lesson', () async {
      final LocalQuizRepository quizzes =
          LocalQuizRepository(storage: storage);
      final AssessmentController c =
          await settle(buildController(quizzes: quizzes));
      await answerAll(c, correctFor);
      await Future<void>.delayed(Duration.zero);

      final QuizResult? saved = await quizzes.latestResult(kLessonId);

      expect(saved, isNotNull);
      expect(saved!.score, 10);
    });

    test('the listen button names the language it will actually use',
        () async {
      final AssessmentController c = await settle(buildController());

      // Nobody has written these questions in Santali, so the button must not
      // promise Santali.
      expect(c.hasTargetLanguageReading, isFalse);
      expect(c.spokenIn, SpokenIn.teachingMedium);
      expect(c.listenLabel, 'Hear question in Hindi');
      expect(c.listenNote, contains('Santali'));
    });

    test('a source that fails leaves a retryable error', () async {
      final AssessmentController c = await settle(
        buildController(
          quizzes: LocalQuizRepository(
            storage: storage,
            source: const FailingQuizQuestionSource(),
          ),
        ),
      );

      expect(c.stage, AssessmentStage.error);
    });

    test('a lesson with no questions is reported, not treated as an error',
        () async {
      final AssessmentController c = await settle(
        buildController(lessonId: 'c1-num-shapes'),
      );

      expect(c.stage, AssessmentStage.noQuestions);
      expect(c.total, 0);
    });
  });

  // --- The screen ----------------------------------------------------------

  group('screen', () {
    testWidgets('shows the question, its wording and four options',
        (WidgetTester tester) async {
      final AssessmentController c = await pump(tester);
      final QuizQuestion q = c.current!;

      expect(find.text('Quick Assessment'), findsOneWidget);
      expect(find.text('Class 1  •  Counting 1–10'), findsOneWidget);
      expect(find.text('Question 1 of 10'), findsOneWidget);
      expect(find.text(q.prompt), findsOneWidget);
      expect(find.text(q.promptHindi), findsOneWidget);
      for (final QuizOption o in q.options) {
        expect(find.byKey(AssessmentScreen.optionKey(o.id)), findsOneWidget);
      }
    });

    testWidgets('the summary is absent until every question is answered',
        (WidgetTester tester) async {
      final AssessmentController c = await pump(tester);

      expect(find.byKey(AssessmentScreen.completionKey), findsNothing);

      for (int i = 0; i < c.total - 1; i++) {
        await c.goTo(i);
        await c.select(c.questions[i].correctOptionId);
      }
      await tester.pumpAndSettle();

      expect(find.byKey(AssessmentScreen.completionKey), findsNothing);
    });

    testWidgets('the summary appears once the last question is answered',
        (WidgetTester tester) async {
      final AssessmentController c = await pump(tester);
      await answerAll(c, correctFor);
      await tester.pumpAndSettle();

      await reveal(tester, AssessmentScreen.completionKey);

      expect(find.byKey(AssessmentScreen.completionKey), findsOneWidget);
      expect(find.text('Assessment Completed'), findsOneWidget);
      expect(find.byType(ScoreRing), findsOneWidget);
    });

    testWidgets('Next is disabled until an option is chosen',
        (WidgetTester tester) async {
      final AssessmentController c = await pump(tester);

      FilledButton next() =>
          tester.widget<FilledButton>(find.byKey(AssessmentScreen.nextKey));

      expect(next().onPressed, isNull);

      await tester.tap(
        find.byKey(AssessmentScreen.optionKey(c.current!.correctOptionId)),
      );
      await tester.pumpAndSettle();

      expect(next().onPressed, isNotNull);
    });

    testWidgets('tapping an option and Next moves to the next question',
        (WidgetTester tester) async {
      final AssessmentController c = await pump(tester);

      await tester.tap(
        find.byKey(AssessmentScreen.optionKey(c.current!.correctOptionId)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AssessmentScreen.nextKey));
      await tester.pumpAndSettle();

      expect(c.index, 1);
      expect(find.text('Question 2 of 10'), findsOneWidget);
    });

    testWidgets('Back returns with the answer still selected',
        (WidgetTester tester) async {
      final AssessmentController c = await pump(tester);
      final String chosen = c.current!.correctOptionId;

      await tester.tap(find.byKey(AssessmentScreen.optionKey(chosen)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AssessmentScreen.nextKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(AssessmentScreen.previousKey));
      await tester.pumpAndSettle();

      expect(c.index, 0);
      expect(c.selectedOptionId, chosen);
    });

    testWidgets('the listen button says which language it will read in',
        (WidgetTester tester) async {
      await pump(tester);

      expect(find.text('Hear question in Hindi'), findsOneWidget);
      expect(find.textContaining('Hear question in Santali'), findsNothing);
    });

    testWidgets('the loading state shows a skeleton, never an empty page',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final AssessmentController c = buildController(
        quizzes: LocalQuizRepository(
          storage: storage,
          source: const SlowQuizQuestionSource(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: AssessmentScreen(controller: c)),
      );
      await tester.pump();

      expect(find.byKey(AssessmentScreen.skeletonKey), findsOneWidget);

      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.byKey(AssessmentScreen.skeletonKey), findsNothing);
    });

    testWidgets('a failing source offers a retry', (WidgetTester tester) async {
      await pump(
        tester,
        controller: buildController(
          quizzes: LocalQuizRepository(
            storage: storage,
            source: const FailingQuizQuestionSource(),
          ),
        ),
      );

      expect(find.byKey(AssessmentScreen.retryKey), findsOneWidget);
    });

    testWidgets('a lesson without questions says so plainly',
        (WidgetTester tester) async {
      await pump(
        tester,
        controller: buildController(lessonId: 'c1-num-shapes'),
      );

      expect(find.text('No assessment for this lesson yet.'), findsOneWidget);
    });

    testWidgets('opened without a lesson, it explains rather than guessing',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: AssessmentScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Open an assessment from a lesson.'), findsOneWidget);
    });

    testWidgets('nothing overflows on a 320dp phone',
        (WidgetTester tester) async {
      final AssessmentController c =
          await pump(tester, size: const Size(320, 2600));
      await answerAll(c, wrongFor);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('the header names GyanSetu AI and never BhashaSetu',
        (WidgetTester tester) async {
      await pump(tester);

      expect(
        find.textContaining('BhashaSetu', findRichText: true),
        findsNothing,
      );
      expect(find.bySemanticsLabel('GyanSetu AI'), findsWidgets);
    });

    testWidgets('View Details opens the detailed result screen',
        (WidgetTester tester) async {
      Object? args;
      final AssessmentController c = await pump(
        tester,
        routes: (RouteSettings settings) {
          if (settings.name == AppRoutes.assessmentResult) {
            args = settings.arguments;
          }
          return AppRouter.onGenerateRoute(settings);
        },
      );
      await answerAll(c, correctFor);
      await tester.pumpAndSettle();

      await reveal(tester, AssessmentScreen.viewDetailsKey);
      await tester.tap(find.byKey(AssessmentScreen.viewDetailsKey));
      await tester.pumpAndSettle();

      expect(args, isA<AssessmentResultArgs>());
      expect((args! as AssessmentResultArgs).result.score, 10);
      expect(find.text('Assessment Details'), findsOneWidget);
    });
  });

  // --- The detailed result screen -----------------------------------------

  group('result screen', () {
    List<QuizQuestion> questions() =>
        AssessmentQuestionData.countingOneToTen();

    /// Built without the controller: a `testWidgets` body runs in fake async,
    /// where waiting on the controller's own load would never complete.
    QuizResult finishedResult({required bool allCorrect}) {
      final List<QuizQuestion> qs = questions();
      final DateTime start = DateTime(2026, 8, 29, 10);
      return QuizResult.from(
        lessonId: kLessonId,
        questions: qs,
        answers: <String, QuizAnswer>{
          for (int i = 0; i < qs.length; i++)
            qs[i].id: QuizAnswer(
              questionId: qs[i].id,
              selectedOptionId:
                  allCorrect ? correctFor(qs[i]) : wrongFor(qs[i]),
              correct: allCorrect,
              answeredAt: start.add(Duration(seconds: 20 * (i + 1))),
            ),
        },
        startedAt: start,
        finishedAt: start.add(Duration(seconds: 20 * qs.length)),
      );
    }

    Future<void> pumpResult(
      WidgetTester tester, {
      required QuizResult result,
      PracticeSuggestion? suggestion,
      Size size = const Size(430, 3000),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          onGenerateRoute: AppRouter.onGenerateRoute,
          home: AssessmentResultScreen(
            args: AssessmentResultArgs(
              result: result,
              questions: questions(),
              suggestion: suggestion,
              lessonTitle: 'Counting 1–10',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the real score and every question',
        (WidgetTester tester) async {
      final QuizResult result = finishedResult(allCorrect: true);
      await pumpResult(tester, result: result);

      expect(find.text('10 of 10'), findsOneWidget);
      expect(find.text('100%'), findsWidgets);
      for (final QuizQuestion q in questions()) {
        expect(
          find.byKey(AssessmentResultScreen.questionKey(q.id)),
          findsOneWidget,
        );
      }
    });

    testWidgets('a wrong answer is shown beside the correct one',
        (WidgetTester tester) async {
      final QuizResult result = finishedResult(allCorrect: false);
      await pumpResult(tester, result: result);

      expect(find.textContaining('Correct answer'), findsWidgets);
      expect(find.text('0 of 10'), findsOneWidget);
    });

    testWidgets('the suggestion is offered with an action that goes somewhere',
        (WidgetTester tester) async {
      final QuizResult result = finishedResult(allCorrect: false);
      const LocalAssessmentRecommendationService rules =
          LocalAssessmentRecommendationService();

      await pumpResult(
        tester,
        result: result,
        suggestion: rules.suggest(result),
      );

      await reveal(tester, AssessmentResultScreen.suggestionActionKey);
      expect(
        find.byKey(AssessmentResultScreen.suggestionActionKey),
        findsOneWidget,
      );
      expect(find.textContaining('rule on this phone'), findsOneWidget);
    });

    testWidgets('reached without a result, it says so instead of showing zero',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: AssessmentResultScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('No assessment result to show.'), findsOneWidget);
      expect(find.byType(ScoreRing), findsNothing);
    });
  });

  // --- Routing -------------------------------------------------------------

  group('routes', () {
    test('both assessment routes are registered', () {
      expect(AppRouter.registeredRoutes, contains(AppRoutes.assessment));
      expect(AppRouter.registeredRoutes, contains(AppRoutes.assessmentResult));
    });

    test('the assessment route is not the lesson quick-check route', () {
      expect(AppRoutes.assessment, isNot(AppRoutes.lessonAssessment));
    });
  });
}
