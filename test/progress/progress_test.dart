import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/app/routes.dart';
import 'package:gyan_setu_ai/app/theme.dart';
import 'package:gyan_setu_ai/features/assessment/services/quiz_repository.dart';
import 'package:gyan_setu_ai/features/classroom/models/classroom_session.dart';
import 'package:gyan_setu_ai/features/classroom/models/conversation_turn.dart';
import 'package:gyan_setu_ai/features/classroom/services/classroom_session_repository.dart';
import 'package:gyan_setu_ai/features/flashcards/flashcards_screen.dart'
    show FlashcardsArgs;
import 'package:gyan_setu_ai/features/lessons/lesson_navigation.dart';
import 'package:gyan_setu_ai/features/lessons/services/assessment_repository.dart';
import 'package:gyan_setu_ai/features/progress/models/learning_insights.dart';
import 'package:gyan_setu_ai/features/progress/progress_screen.dart';
import 'package:gyan_setu_ai/features/progress/services/learning_progress_repository.dart';
import 'package:gyan_setu_ai/features/progress/services/learning_recommendation_service.dart';
import 'package:gyan_setu_ai/features/progress/services/progress_analytics_service.dart';
import 'package:gyan_setu_ai/features/progress/services/progress_controller.dart';
import 'package:gyan_setu_ai/features/progress/services/student_repository.dart';
import 'package:gyan_setu_ai/features/progress/student_progress_screen.dart';
import 'package:gyan_setu_ai/features/progress/widgets/progress_widgets.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/models/assessment_answer.dart';
import 'package:gyan_setu_ai/models/assessment_question.dart';
import 'package:gyan_setu_ai/models/assessment_result.dart';
import 'package:gyan_setu_ai/models/lesson.dart';
import 'package:gyan_setu_ai/models/lesson_plan.dart' as plan;
import 'package:gyan_setu_ai/models/progress_event.dart';
import 'package:gyan_setu_ai/models/student_progress.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';

import '../lessons/lesson_test_doubles.dart';
import '../setup/setup_test_doubles.dart' as setup_doubles;

/// Wednesday of the week 25–31 August 2026.
final DateTime kNow = DateTime(2026, 8, 26, 10);

/// An analytics service that always fails, for the error state.
class FailingAnalytics implements ProgressAnalyticsService {
  const FailingAnalytics();

  @override
  Future<LearningInsights> insights({
    required InsightPeriod period,
    DateRange? customRange,
    DateTime? now,
  }) async =>
      throw StateError('analytics unavailable');
}

/// Holds the calculation open so the skeleton is observable.
class SlowAnalytics implements ProgressAnalyticsService {
  SlowAnalytics(this._inner);

  final ProgressAnalyticsService _inner;

  @override
  Future<LearningInsights> insights({
    required InsightPeriod period,
    DateRange? customRange,
    DateTime? now,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return _inner.insights(period: period, customRange: customRange, now: now);
  }
}

void main() {
  late InMemorySecureStorageService storage;
  late FakeLessonRepository lessons;
  late FakeProgressRepository lessonProgress;
  late InMemoryQuizRepository quizzes;
  late InMemoryAssessmentRepository quickChecks;
  late InMemoryClassroomSessionRepository sessions;
  late InMemoryLearningProgressRepository events;
  late setup_doubles.TestRepository classrooms;

  Lesson lesson({
    required String id,
    required String title,
    ClassroomSubject subject = ClassroomSubject.numeracy,
    int classNumber = 1,
    List<String> concepts = const <String>[],
  }) =>
      Lesson(
        id: id,
        title: title,
        description: 'A lesson.',
        subject: subject,
        classNumber: classNumber,
        learningOutcome: 'Outcome.',
        durationMinutes: 10,
        lessonOrder: 1,
        createdAt: DateTime(2026, 6),
        updatedAt: DateTime(2026, 6),
        concepts: concepts,
      );

  List<Lesson> catalogue() => <Lesson>[
        lesson(
          id: 'c1-num-counting-1-10',
          title: 'Counting 1–10',
          concepts: <String>['Numbers 6–10', 'Counting Objects'],
        ),
        lesson(id: 'c1-num-shapes', title: 'Shapes Around Us'),
        lesson(
          id: 'c1-lit-swar',
          title: 'Swar: A, AA, I',
          subject: ClassroomSubject.foundationalLiteracy,
        ),
        lesson(
          id: 'c1-lit-family',
          title: 'My Family',
          subject: ClassroomSubject.foundationalLiteracy,
        ),
        // Another class, so scoping can be asserted.
        lesson(id: 'c2-num-addition', title: 'Addition to 10', classNumber: 2),
      ];

  ConversationTurn turn({
    required String id,
    required TurnSpeaker speaker,
    TurnStatus status = TurnStatus.played,
  }) =>
      ConversationTurn(
        id: id,
        sessionId: 'CLS-260826-1000',
        speaker: speaker,
        sourceLanguage: 'hi-IN',
        targetLanguage: 'sat',
        timestamp: kNow,
        status: status,
        sourceText: 'text',
      );

  ClassroomSession session({
    required DateTime savedAt,
    int teacherTurns = 2,
    int studentTurns = 3,
    int failedTurns = 0,
    int classNumber = 1,
  }) =>
      ClassroomSession(
        sessionId: 'CLS-${savedAt.millisecondsSinceEpoch}',
        lessonId: 'c1-num-counting-1-10',
        lessonTitle: 'Counting 1–10',
        classNumber: classNumber,
        subject: ClassroomSubject.numeracy,
        teachingLanguage: 'hi-IN',
        targetLanguage: 'sat',
        startedAt: savedAt.subtract(const Duration(minutes: 10)),
        endedAt: savedAt,
        completed: true,
        savedAt: savedAt,
        turns: <ConversationTurn>[
          for (int i = 0; i < teacherTurns; i++)
            turn(id: 't$i', speaker: TurnSpeaker.teacher),
          for (int i = 0; i < studentTurns; i++)
            turn(id: 's$i', speaker: TurnSpeaker.student),
          for (int i = 0; i < failedTurns; i++)
            turn(
              id: 'f$i',
              speaker: TurnSpeaker.student,
              status: TurnStatus.failed,
            ),
        ],
      );

  QuizResult quizResult({
    required String lessonId,
    required DateTime finishedAt,
    int correct = 8,
    int total = 10,
  }) {
    final List<QuizQuestion> questions = <QuizQuestion>[
      for (int i = 0; i < total; i++)
        QuizQuestion(
          id: 'q$i',
          concept: i < total ~/ 2
              ? QuizConcept.numbers1to5
              : QuizConcept.numbers6to10,
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
      lessonId: lessonId,
      questions: questions,
      answers: <String, QuizAnswer>{
        for (int i = 0; i < total; i++)
          'q$i': QuizAnswer(
            questionId: 'q$i',
            selectedOptionId: i < correct ? 'right' : 'wrong',
            correct: i < correct,
            answeredAt: finishedAt,
          ),
      },
      startedAt: finishedAt.subtract(const Duration(minutes: 4)),
      finishedAt: finishedAt,
    );
  }

  ProgressEvent completion(String lessonId, DateTime at) => ProgressEvent.of(
        type: ProgressEventType.lessonCompleted,
        occurredAt: at,
        lessonId: lessonId,
      );

  setUp(() {
    storage = InMemorySecureStorageService();
    lessons = FakeLessonRepository(catalogue: catalogue());
    lessonProgress = FakeProgressRepository();
    quizzes = InMemoryQuizRepository();
    quickChecks = InMemoryAssessmentRepository();
    sessions = InMemoryClassroomSessionRepository();
    events = InMemoryLearningProgressRepository();
    classrooms = setup_doubles.TestRepository(existing: testClassroom());
  });

  LocalProgressAnalyticsService buildAnalytics({
    StudentRepository? students,
  }) =>
      LocalProgressAnalyticsService(
        lessons: lessons,
        lessonProgress: lessonProgress,
        quizzes: quizzes,
        quickChecks: quickChecks,
        sessions: sessions,
        events: events,
        classrooms: classrooms,
        teacherId: kTeacherId,
        students: students ?? const DevelopmentStudentRepository(),
      );

  Future<LearningInsights> insightsFor({
    InsightPeriod period = InsightPeriod.thisWeek,
    StudentRepository? students,
    DateRange? custom,
  }) =>
      buildAnalytics(students: students).insights(
        period: period,
        customRange: custom,
        now: kNow,
      );

  ProgressController buildController({
    ProgressAnalyticsService? analytics,
    StudentRepository? students,
  }) {
    final ProgressController c = ProgressController(
      analytics: analytics ?? buildAnalytics(students: students),
      lessons: lessons,
      students: students ?? const DevelopmentStudentRepository(),
      recommendations: const LocalLearningRecommendationService(),
      clock: () => kNow,
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<ProgressController> settle(ProgressController c) async {
    while (c.state == InsightsState.loading) {
      await Future<void>.delayed(Duration.zero);
    }
    return c;
  }

  Future<ProgressController> pump(
    WidgetTester tester, {
    ProgressController? controller,
    ProgressAnalyticsService? analytics,
    StudentRepository? students,
    Size size = const Size(430, 3000),
    RouteFactory? routes,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ProgressController c = controller ??
        buildController(analytics: analytics, students: students);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        onGenerateRoute: routes ?? AppRouter.onGenerateRoute,
        home: ProgressScreen(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> reveal(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pumpAndSettle();
  }

  // --- 1. Progress event model --------------------------------------------

  group('progress event', () {
    test('an event carries its type, lesson and time', () {
      final ProgressEvent e = ProgressEvent.of(
        type: ProgressEventType.lessonCompleted,
        occurredAt: kNow,
        lessonId: 'c1-num-counting-1-10',
        metadata: <String, String>{'score': '8'},
      );

      expect(e.type, ProgressEventType.lessonCompleted);
      expect(e.lessonId, 'c1-num-counting-1-10');
      expect(e.occurredAt, kNow);
      expect(e.intValue('score'), 8);
      expect(e.intValue('missing'), isNull);
    });

    test('an event survives a round trip through storage', () {
      final ProgressEvent before = ProgressEvent.of(
        type: ProgressEventType.assessmentCompleted,
        occurredAt: kNow,
        lessonId: 'c1-num-counting-1-10',
        metadata: <String, String>{'percentage': '80'},
      );
      final ProgressEvent after = ProgressEvent.fromJson(before.toJson());

      expect(after.id, before.id);
      expect(after.type, before.type);
      expect(after.occurredAt, before.occurredAt);
      expect(after.intValue('percentage'), 80);
    });

    test('only finished work counts as classroom activity', () {
      expect(ProgressEventType.lessonCompleted.isClassroomActivity, isTrue);
      expect(ProgressEventType.lessonStarted.isClassroomActivity, isFalse);
      expect(ProgressEventType.flashcardViewed.isClassroomActivity, isFalse);
    });
  });

  // --- 2. StudentProgress model -------------------------------------------

  group('student progress', () {
    const StudentProgress child = StudentProgress(
      studentId: 's1',
      name: 'Aarti Murmu',
      classId: 'class-1',
      lessonsCompleted: 2,
      conceptsMastered: <String>['Numbers 1–5'],
      conceptsNeedingPractice: <String>['Numbers 6–10'],
      engagementScore: 70,
      assessmentScores: <String, int>{'a': 60, 'b': 80},
    );

    test('initials come from the name, never a photograph', () {
      expect(child.initials, 'AM');
      expect(
        const StudentProgress(
          studentId: 's2',
          name: 'Lalan',
          classId: 'class-1',
          lessonsCompleted: 0,
          conceptsMastered: <String>[],
          conceptsNeedingPractice: <String>[],
          engagementScore: 0,
        ).initials,
        'LA',
      );
    });

    test('a child with no assessment has no average, not a zero', () {
      expect(child.averageScore, 70);
      expect(
        const StudentProgress(
          studentId: 's3',
          name: 'Gita Kisku',
          classId: 'class-1',
          lessonsCompleted: 0,
          conceptsMastered: <String>[],
          conceptsNeedingPractice: <String>[],
          engagementScore: 0,
        ).averageScore,
        isNull,
      );
    });

    test('concept matching ignores case', () {
      expect(child.needsPracticeWith('numbers 6–10'), isTrue);
      expect(child.needsPracticeWith('Numbers 1–5'), isFalse);
    });

    test('a record survives a round trip through storage', () {
      final StudentProgress after =
          StudentProgress.fromJson(child.toJson());

      expect(after.name, child.name);
      expect(after.conceptsNeedingPractice, child.conceptsNeedingPractice);
      expect(after.engagementScore, child.engagementScore);
    });
  });

  // --- 3. Date ranges ------------------------------------------------------

  group('date range', () {
    test('a week runs Monday to Sunday', () {
      final DateRange week = DateRange.weekOf(kNow);

      expect(week.start, DateTime(2026, 8, 24));
      expect(week.end, DateTime(2026, 8, 30));
      expect(week.start.weekday, DateTime.monday);
      expect(week.end.weekday, DateTime.sunday);
    });

    test('the label collapses a shared month and year', () {
      expect(DateRange.weekOf(kNow).label, '24 – 30 Aug 2026');
      expect(
        DateRange(
          start: DateTime(2026, 8, 30),
          end: DateTime(2026, 9, 5),
        ).label,
        '30 Aug – 5 Sep 2026',
      );
    });

    test('the previous range is the same length, immediately before', () {
      final DateRange previous = DateRange.weekOf(kNow).previous;

      expect(previous.start, DateTime(2026, 8, 17));
      expect(previous.end, DateTime(2026, 8, 23));
    });

    test('a range includes both ends, whatever the time of day', () {
      final DateRange week = DateRange.weekOf(kNow);

      expect(week.contains(DateTime(2026, 8, 24)), isTrue);
      expect(week.contains(DateTime(2026, 8, 30, 23, 59)), isTrue);
      expect(week.contains(DateTime(2026, 8, 31)), isFalse);
      expect(week.contains(DateTime(2026, 8, 23, 23, 59)), isFalse);
    });
  });

  // --- 4. Storage ----------------------------------------------------------

  group('event log', () {
    test('events are kept and read back in time order', () async {
      final LocalLearningProgressRepository log =
          LocalLearningProgressRepository(storage);

      await log.record(completion('b', DateTime(2026, 8, 26)));
      await log.record(completion('a', DateTime(2026, 8, 24)));

      final LocalLearningProgressRepository reopened =
          LocalLearningProgressRepository(storage);
      final List<ProgressEvent> all = await reopened.all();

      expect(all.map((ProgressEvent e) => e.lessonId), <String>['a', 'b']);
    });

    test('the same event recorded twice is kept once', () async {
      final LocalLearningProgressRepository log =
          LocalLearningProgressRepository(storage);
      final ProgressEvent e = completion('a', DateTime(2026, 8, 24));

      await log.record(e);
      await log.record(e);

      expect(await log.all(), hasLength(1));
    });

    test('a range query returns only what falls inside it', () async {
      final LocalLearningProgressRepository log =
          LocalLearningProgressRepository(storage);
      await log.record(completion('a', DateTime(2026, 8, 26)));
      await log.record(completion('b', DateTime(2026, 8, 19)));

      final List<ProgressEvent> week =
          await log.inRange(DateRange.weekOf(kNow));

      expect(week.map((ProgressEvent e) => e.lessonId), <String>['a']);
    });

    test('unreadable stored events are reported as none, not as a crash',
        () async {
      await storage.write('progress.events', 'this is not json');

      expect(await LocalLearningProgressRepository(storage).all(), isEmpty);
    });

    test('the recorder swallows a storage failure', () async {
      const ProgressRecorder recorder =
          ProgressRecorder(FailingLearningProgressRepository());

      await expectLater(
        recorder.record(ProgressEventType.lessonCompleted, lessonId: 'a'),
        completes,
      );
    });

    test('a recorder with no log keeps nothing and does not fail', () async {
      const ProgressRecorder recorder = ProgressRecorder.none();

      await expectLater(
        recorder.record(ProgressEventType.lessonCompleted),
        completes,
      );
    });
  });

  // --- 5. Analytics --------------------------------------------------------

  group('analytics', () {
    test('learning progress averages this class only', () async {
      lessonProgress = FakeProgressRepository(<String, int>{
        'c1-num-counting-1-10': 100,
        'c1-num-shapes': 50,
        'c1-lit-swar': 50,
        'c1-lit-family': 0,
        // Class 2 must not move a Class 1 figure.
        'c2-num-addition': 100,
      });

      final LearningInsights insights = await insightsFor();

      expect(
        insights.statFor(InsightStatKind.learningProgress).value,
        50,
      );
    });

    test('lessons completed counts only lessons at 100 per cent', () async {
      lessonProgress = FakeProgressRepository(<String, int>{
        'c1-num-counting-1-10': 100,
        'c1-num-shapes': 99,
        'c1-lit-swar': 100,
      });

      final LearningInsights insights = await insightsFor();

      expect(insights.statFor(InsightStatKind.lessonsCompleted).value, 2);
    });

    test('assessments count finished quizzes and quick checks', () async {
      await quizzes.saveResult(
        quizResult(lessonId: 'c1-num-counting-1-10', finishedAt: kNow),
      );
      await quickChecks.record(
        plan.AssessmentResult(
          lessonId: 'c1-lit-swar',
          assessmentId: 'qa-1',
          outcomes: const <String, plan.AssessmentOutcome>{},
          recordedAt: kNow,
        ),
      );

      final LearningInsights insights = await insightsFor();

      expect(insights.statFor(InsightStatKind.assessments).value, 2);
      expect(
        insights.statFor(InsightStatKind.assessments).delta.amount,
        2,
      );
    });

    test('engagement is the share of turns that were the children', () async {
      await sessions.save(
        session(savedAt: kNow, teacherTurns: 2, studentTurns: 3),
      );

      final LearningInsights insights = await insightsFor();

      // 3 of 5 turns.
      expect(insights.statFor(InsightStatKind.engagement).value, 60);
    });

    test('a week with no session reports no engagement, not zero', () async {
      final LearningInsights insights = await insightsFor();

      expect(insights.statFor(InsightStatKind.engagement).value, isNull);
      expect(insights.statFor(InsightStatKind.engagement).display, '--');
    });

    test('learning areas are calculated per subject', () async {
      lessonProgress = FakeProgressRepository(<String, int>{
        'c1-num-counting-1-10': 100,
        'c1-num-shapes': 60,
        'c1-lit-swar': 40,
        'c1-lit-family': 40,
      });

      final LearningInsights insights = await insightsFor();

      expect(insights.areaFor(LearningArea.numeracy)!.percentage, 80);
      expect(
        insights.areaFor(LearningArea.foundationalLiteracy)!.percentage,
        40,
      );
    });

    test('an area with nothing recorded says so instead of showing zero',
        () async {
      final LearningAreaInsight language =
          (await insightsFor()).areaFor(LearningArea.languageUnderstanding)!;

      expect(language.hasData, isFalse);
      expect(language.percentage, isNull);
      expect(language.band, 'No data yet');
      expect(language.basis, contains('No live classroom session'));
    });

    test('language understanding is the share of turns that got through',
        () async {
      await sessions.save(
        session(
          savedAt: kNow,
          teacherTurns: 2,
          studentTurns: 2,
          failedTurns: 1,
        ),
      );

      final LearningAreaInsight language =
          (await insightsFor()).areaFor(LearningArea.languageUnderstanding)!;

      // 4 of 5 turns reached audio.
      expect(language.percentage, 80);
      expect(language.band, 'Proficient');
    });

    test('the band follows the percentage', () {
      LearningAreaInsight at(int p) => LearningAreaInsight(
            area: LearningArea.numeracy,
            percentage: p,
            improvement: const InsightDelta.unknown(),
            basis: '',
          );

      expect(at(82).band, 'Proficient');
      expect(at(74).band, 'Developing');
      expect(at(45).band, 'Emerging');
      expect(at(20).band, 'Needs support');
    });

    test('a weak concept from a real assessment reaches Needs Attention',
        () async {
      await quizzes.saveResult(
        quizResult(
          lessonId: 'c1-num-counting-1-10',
          finishedAt: kNow,
          correct: 5,
          total: 10,
        ),
      );

      final LearningInsights insights = await insightsFor(
        students: const EmptyStudentRepository(),
      );

      expect(insights.attention, isNotEmpty);
      expect(
        insights.attention.map((AttentionGroup g) => g.concept),
        contains(QuizConcept.numbers6to10.label),
      );
    });

    test('with no roster the class is described, not a count of children',
        () async {
      await quizzes.saveResult(
        quizResult(
          lessonId: 'c1-num-counting-1-10',
          finishedAt: kNow,
          correct: 5,
          total: 10,
        ),
      );

      final AttentionGroup group = (await insightsFor(
        students: const EmptyStudentRepository(),
      ))
          .weakest!;

      expect(group.students, isEmpty);
      expect(group.headline, startsWith('This class needs'));
    });

    test('with a roster the children behind are counted and named', () async {
      final LearningInsights insights = await insightsFor();
      final AttentionGroup group = insights.weakest!;

      expect(insights.usesPrototypeStudents, isTrue);
      expect(insights.studentCount, 24);
      expect(group.count, 6);
      expect(group.headline, '6 learners need more practice with '
          '${QuizConcept.numbers6to10.label}.');
    });

    test('the weakest concept is the one with the most children behind',
        () async {
      final LearningInsights insights = await insightsFor();

      expect(insights.attention.first.count, 6);
      expect(
        insights.attention.first.count >= insights.attention.last.count,
        isTrue,
      );
    });

    test('a group points at the lesson that teaches its concept', () async {
      final AttentionGroup group = (await insightsFor()).weakest!;

      expect(group.lessonId, 'c1-num-counting-1-10');
    });
  });

  // --- 6. Week filtering ---------------------------------------------------

  group('period filtering', () {
    test('this week and last week count different events', () async {
      await events.record(
        completion('c1-num-counting-1-10', DateTime(2026, 8, 26)),
      );
      await events.record(completion('c1-num-shapes', DateTime(2026, 8, 19)));

      final LearningInsights thisWeek = await insightsFor();
      final LearningInsights lastWeek =
          await insightsFor(period: InsightPeriod.lastWeek);

      expect(
        thisWeek.statFor(InsightStatKind.lessonsCompleted).delta.amount,
        1,
      );
      expect(
        lastWeek.statFor(InsightStatKind.lessonsCompleted).delta.amount,
        1,
      );
      expect(thisWeek.range.start, DateTime(2026, 8, 24));
      expect(lastWeek.range.start, DateTime(2026, 8, 17));
    });

    test('a custom range is honoured', () async {
      await events.record(
        completion('c1-num-counting-1-10', DateTime(2026, 8, 5)),
      );

      final LearningInsights insights = await insightsFor(
        period: InsightPeriod.custom,
        custom: DateRange(
          start: DateTime(2026, 8),
          end: DateTime(2026, 8, 10),
        ),
      );

      expect(insights.range.label, '1 – 10 Aug 2026');
      expect(insights.eventsInRange, 1);
    });

    test('the same lesson finished twice in a week counts once', () async {
      await events.record(
        completion('c1-num-counting-1-10', DateTime(2026, 8, 25)),
      );
      await events.record(
        completion('c1-num-counting-1-10', DateTime(2026, 8, 26)),
      );

      final LearningInsights insights = await insightsFor();

      expect(
        insights.statFor(InsightStatKind.lessonsCompleted).delta.amount,
        1,
      );
    });

    test('a delta with nothing behind it reads as unknown, not as zero', () {
      const InsightDelta unknown = InsightDelta.unknown();

      expect(unknown.known, isFalse);
      expect(unknown.labelFor('week'), 'No earlier week to compare');
      expect(
        const InsightDelta(amount: 0, unit: '').labelFor('week'),
        'No change this week',
      );
      expect(
        const InsightDelta(amount: 3, unit: '').labelFor('week'),
        '3 this week',
      );
      expect(
        const InsightDelta(amount: 8, unit: '%').labelFor('week'),
        '8% this week',
      );
    });
  });

  // --- 7. Recommendations --------------------------------------------------

  group('recommendation', () {
    const LocalLearningRecommendationService rules =
        LocalLearningRecommendationService();

    test('with nothing recorded it asks for a lesson rather than guessing',
        () async {
      final LearningInsights insights =
          await insightsFor(students: const EmptyStudentRepository());
      final LearningAction action =
          rules.recommend(insights: insights, lessons: catalogue());

      expect(action.kind, LearningActionKind.needsData);
      expect(action.lessonId, isNull);
    });

    test('a weakness across half the class points at the lesson', () async {
      final LearningInsights insights = await insightsFor();
      final LearningAction action =
          rules.recommend(insights: insights, lessons: catalogue());

      // 6 of 24 is a quarter, so the smaller step is offered.
      expect(action.kind, LearningActionKind.flashcards);
      expect(action.flashcardCategory?.name, 'numbers');
      expect(action.concept, QuizConcept.numbers6to10.label);
      expect(action.lessonId, 'c1-num-counting-1-10');
    });

    test('a weakness in most of the class points at reteaching', () async {
      await quizzes.saveResult(
        quizResult(
          lessonId: 'c1-num-counting-1-10',
          finishedAt: kNow,
          correct: 5,
          total: 10,
        ),
      );
      final LearningInsights insights =
          await insightsFor(students: const EmptyStudentRepository());
      final LearningAction action =
          rules.recommend(insights: insights, lessons: catalogue());

      expect(action.kind, LearningActionKind.reinforcementLesson);
      expect(action.lessonId, 'c1-num-counting-1-10');
    });

    test('the same insights always give the same recommendation', () async {
      final LearningInsights insights = await insightsFor();

      expect(
        rules.recommend(insights: insights, lessons: catalogue()).body,
        rules.recommend(insights: insights, lessons: catalogue()).body,
      );
    });

    test('the recommendation never claims to have been written by a model',
        () async {
      final LearningInsights insights = await insightsFor();
      final LearningAction action =
          rules.recommend(insights: insights, lessons: catalogue());

      expect(action.sourceNote, contains('rule rather than a model'));
      expect(action.headline.toLowerCase(), isNot(contains('ai ')));
    });
  });

  // --- 8. Controller -------------------------------------------------------

  group('controller', () {
    test('loads insights and a recommendation together', () async {
      final ProgressController c = await settle(buildController());

      expect(c.state, InsightsState.ready);
      expect(c.insights, isNotNull);
      expect(c.action, isNotNull);
      expect(c.classSummary, 'Class 1  •  24 students');
    });

    test('changing the period recalculates', () async {
      await events.record(
        completion('c1-num-counting-1-10', DateTime(2026, 8, 19)),
      );
      final ProgressController c = await settle(buildController());

      expect(c.range.start, DateTime(2026, 8, 24));
      expect(
        c.insights!.statFor(InsightStatKind.lessonsCompleted).delta.amount,
        0,
      );

      await c.selectPeriod(InsightPeriod.lastWeek);

      expect(c.range.start, DateTime(2026, 8, 17));
      expect(
        c.insights!.statFor(InsightStatKind.lessonsCompleted).delta.amount,
        1,
      );
    });

    test('refresh picks up work done since the screen opened', () async {
      final ProgressController c = await settle(buildController());
      expect(c.insights!.statFor(InsightStatKind.assessments).value, 0);

      await quizzes.saveResult(
        quizResult(lessonId: 'c1-num-counting-1-10', finishedAt: kNow),
      );
      await c.refresh();

      expect(c.insights!.statFor(InsightStatKind.assessments).value, 1);
    });

    test('a failing analytics service leaves a retryable error', () async {
      final ProgressController c = await settle(
        buildController(analytics: const FailingAnalytics()),
      );

      expect(c.state, InsightsState.error);
      expect(c.insights, isNull);
    });

    test('with no roster the class summary says so', () async {
      final ProgressController c = await settle(
        buildController(students: const EmptyStudentRepository()),
      );

      expect(c.classSummary, 'Class 1  •  No pupil records');
      expect(c.usesPrototypeStudents, isFalse);
    });

    test('the reinforcement lesson resolves to a real lesson', () async {
      final ProgressController c = await settle(buildController());

      expect(c.reinforcementLesson?.id, 'c1-num-counting-1-10');
    });
  });

  // --- 9. Screen -----------------------------------------------------------

  group('screen', () {
    testWidgets('shows the title, the range and the four figures',
        (WidgetTester tester) async {
      await pump(tester);

      expect(find.text('Learning Insights'), findsOneWidget);
      expect(
        find.text('Understand your classroom’s progress at a glance.'),
        findsOneWidget,
      );
      expect(find.text('24 – 30 Aug 2026'), findsOneWidget);
      for (final InsightStatKind kind in InsightStatKind.values) {
        expect(find.byKey(ProgressScreen.statKey(kind)), findsOneWidget);
      }
    });

    testWidgets('shows the three learning areas', (WidgetTester tester) async {
      await pump(tester);

      for (final LearningArea area in LearningArea.values) {
        await reveal(tester, ProgressScreen.areaKey(area));
        expect(find.byKey(ProgressScreen.areaKey(area)), findsOneWidget);
      }
      expect(find.text('Learning Areas Overview'), findsOneWidget);
    });

    testWidgets('names the sample pupil data as a sample',
        (WidgetTester tester) async {
      await pump(tester);

      await reveal(tester, ProgressScreen.sampleDataKey);
      expect(find.byKey(ProgressScreen.sampleDataKey), findsOneWidget);
      expect(find.textContaining('sample class'), findsWidgets);
    });

    testWidgets('a real roster shows no sample-data warning',
        (WidgetTester tester) async {
      await pump(tester, students: const EmptyStudentRepository());

      expect(find.byKey(ProgressScreen.sampleDataKey), findsNothing);
    });

    testWidgets('an empty period says so rather than showing invented activity',
        (WidgetTester tester) async {
      await pump(tester);

      await reveal(tester, ProgressScreen.emptyPeriodKey);
      expect(find.byKey(ProgressScreen.emptyPeriodKey), findsOneWidget);
    });

    testWidgets('a period with activity has no empty state',
        (WidgetTester tester) async {
      await events.record(
        completion('c1-num-counting-1-10', DateTime(2026, 8, 26)),
      );
      await pump(tester);

      expect(find.byKey(ProgressScreen.emptyPeriodKey), findsNothing);
    });

    testWidgets('How is this calculated opens an explanation',
        (WidgetTester tester) async {
      await pump(tester);

      await reveal(tester, ProgressScreen.howCalculatedKey);
      await tester.tap(find.byKey(ProgressScreen.howCalculatedKey));
      await tester.pumpAndSettle();

      expect(
        find.text('How these figures are worked out'),
        findsOneWidget,
      );
      expect(find.textContaining('none of it was'), findsOneWidget);
    });

    testWidgets('the period selector changes the range',
        (WidgetTester tester) async {
      final ProgressController c = await pump(tester);

      await reveal(tester, ProgressScreen.periodKey);
      await tester.tap(find.byKey(ProgressScreen.periodKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last Week'));
      await tester.pumpAndSettle();

      expect(c.period, InsightPeriod.lastWeek);
      expect(find.text('17 – 23 Aug 2026'), findsOneWidget);
    });

    testWidgets('the class selector opens the classroom details',
        (WidgetTester tester) async {
      await pump(tester);

      await reveal(tester, ProgressScreen.classKey);
      await tester.tap(find.byKey(ProgressScreen.classKey));
      await tester.pumpAndSettle();

      expect(find.text('Change the class in Classroom Setup'), findsOneWidget);
    });

    testWidgets('the recommendation is shown and named as a rule',
        (WidgetTester tester) async {
      await pump(tester);

      await reveal(tester, ProgressScreen.recommendationKey);
      expect(find.text('Recommended Action'), findsOneWidget);
      expect(find.textContaining('rule rather than a model'), findsOneWidget);
    });

    testWidgets('the loading state shows a skeleton, never a blank page',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ProgressScreen(
            controller: buildController(
              analytics: SlowAnalytics(buildAnalytics()),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(ProgressScreen.skeletonKey), findsOneWidget);

      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.byKey(ProgressScreen.skeletonKey), findsNothing);
    });

    testWidgets('an error offers a retry that works',
        (WidgetTester tester) async {
      await pump(tester, analytics: const FailingAnalytics());

      expect(find.text('Unable to load learning insights.'), findsOneWidget);
      expect(find.byKey(ProgressScreen.retryKey), findsOneWidget);

      await tester.tap(find.byKey(ProgressScreen.retryKey));
      await tester.pumpAndSettle();

      // Still failing, and still offering the retry rather than crashing.
      expect(find.byKey(ProgressScreen.retryKey), findsOneWidget);
    });

    testWidgets('nothing overflows on a 320dp phone',
        (WidgetTester tester) async {
      await pump(tester, size: const Size(320, 3400));

      expect(tester.takeException(), isNull);
    });

    testWidgets('nothing overflows on a wide screen',
        (WidgetTester tester) async {
      await pump(tester, size: const Size(1024, 2200));

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
  });

  // --- 10. Navigation ------------------------------------------------------

  group('navigation', () {
    testWidgets('Start Reinforcement Lesson opens the lesson it names',
        (WidgetTester tester) async {
      Object? args;
      String? opened;
      await pump(
        tester,
        routes: (RouteSettings settings) {
          if (settings.name == AppRoutes.lessonDetail ||
              settings.name == AppRoutes.lessons) {
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

      await reveal(tester, ProgressScreen.reinforcementKey);
      await tester.tap(find.byKey(ProgressScreen.reinforcementKey));
      await tester.pumpAndSettle();

      expect(opened, AppRoutes.lessonDetail);
      expect(args, isA<LessonDetailArgs>());
      expect(
        (args! as LessonDetailArgs).lessonId,
        'c1-num-counting-1-10',
      );
    });

    testWidgets('with no matching lesson it opens the library instead',
        (WidgetTester tester) async {
      // A catalogue with nothing covering the weak concept.
      lessons = FakeLessonRepository(
        catalogue: <Lesson>[lesson(id: 'c1-other', title: 'Something else')],
      );
      String? opened;
      await pump(
        tester,
        routes: (RouteSettings settings) {
          if (settings.name == AppRoutes.lessons ||
              settings.name == AppRoutes.lessonDetail) {
            opened = settings.name;
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Scaffold(body: Text('library')),
            );
          }
          return AppRouter.onGenerateRoute(settings);
        },
      );

      await reveal(tester, ProgressScreen.reinforcementKey);
      await tester.tap(find.byKey(ProgressScreen.reinforcementKey));
      await tester.pumpAndSettle();

      expect(opened, AppRoutes.lessons);
    });

    testWidgets('Practice with Flashcards opens the deck it names',
        (WidgetTester tester) async {
      Object? args;
      await pump(
        tester,
        routes: (RouteSettings settings) {
          if (settings.name == AppRoutes.flashcards) {
            args = settings.arguments;
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Scaffold(body: Text('flashcards')),
            );
          }
          return AppRouter.onGenerateRoute(settings);
        },
      );

      await reveal(tester, ProgressScreen.flashcardsKey);
      await tester.tap(find.byKey(ProgressScreen.flashcardsKey));
      await tester.pumpAndSettle();

      expect(args, isA<FlashcardsArgs>());
      expect((args! as FlashcardsArgs).category?.name, 'numbers');
    });

    testWidgets('View all students opens the student list',
        (WidgetTester tester) async {
      Object? args;
      await pump(
        tester,
        routes: (RouteSettings settings) {
          if (settings.name == AppRoutes.students) {
            args = settings.arguments;
          }
          return AppRouter.onGenerateRoute(settings);
        },
      );

      await reveal(tester, ProgressScreen.viewStudentsKey);
      await tester.tap(find.byKey(ProgressScreen.viewStudentsKey));
      await tester.pumpAndSettle();

      expect(args, isA<StudentProgressArgs>());
      expect((args! as StudentProgressArgs).students, hasLength(6));
      expect(find.text('Learners to support'), findsOneWidget);
    });

    test('both progress routes are registered', () {
      expect(AppRouter.registeredRoutes, contains(AppRoutes.progress));
      expect(AppRouter.registeredRoutes, contains(AppRoutes.students));
    });
  });

  // --- 11. The student list ------------------------------------------------

  group('student list', () {
    Future<void> pumpStudents(
      WidgetTester tester, {
      required List<StudentProgress> students,
      bool prototype = true,
      Size size = const Size(430, 2400),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: StudentProgressScreen(
            args: StudentProgressArgs(
              group: AttentionGroup(
                concept: QuizConcept.numbers6to10.label,
                students: students,
                headline: '${students.length} learners need more practice.',
                detail: 'They can count to five but lose track beyond it.',
              ),
              students: students,
              usesPrototypeData: prototype,
              classLabel: 'Class 1  •  24 students',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists each child with their concepts',
        (WidgetTester tester) async {
      final List<StudentProgress> students =
          await const DevelopmentStudentRepository().needingPracticeWith(
        QuizConcept.numbers6to10.label,
        classLevel: 1,
      );

      await pumpStudents(tester, students: students);

      expect(find.byKey(StudentProgressScreen.sampleDataKey), findsOneWidget);
      for (final StudentProgress s in students) {
        await tester.ensureVisible(
          find.byKey(StudentProgressScreen.studentKey(s.studentId)),
        );
        expect(
          find.byKey(StudentProgressScreen.studentKey(s.studentId)),
          findsOneWidget,
        );
      }
    });

    testWidgets('an empty list says so rather than showing nothing',
        (WidgetTester tester) async {
      await pumpStudents(
        tester,
        students: const <StudentProgress>[],
        prototype: false,
      );

      expect(find.textContaining('No pupil records'), findsOneWidget);
      expect(find.byKey(StudentProgressScreen.sampleDataKey), findsNothing);
    });

    testWidgets('reached without a group it explains instead of crashing',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: StudentProgressScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('No learners to show.'), findsOneWidget);
      expect(find.byType(StudentAvatar), findsNothing);
    });

    test('the sample class is a fixed 24 children, not a random one',
        () async {
      const DevelopmentStudentRepository repo = DevelopmentStudentRepository();

      expect(await repo.forClass(1), hasLength(24));
      // Another class has no sample data rather than a copy of Class 1.
      expect(await repo.forClass(3), isEmpty);
      expect(repo.isRealRoster, isFalse);
    });
  });
}
