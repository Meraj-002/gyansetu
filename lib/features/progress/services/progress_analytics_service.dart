// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import '../../../models/assessment_result.dart';
import '../../../models/lesson.dart';
import '../../../models/lesson_plan.dart' as plan;
import '../../../models/progress_event.dart';
import '../../../models/student_progress.dart';
import '../../assessment/services/quiz_repository.dart';
import '../../classroom/models/classroom_session.dart';
import '../../classroom/services/classroom_session_repository.dart';
import '../../lessons/services/assessment_repository.dart';
import '../../lessons/services/lesson_repository.dart';
import '../../setup/models/classroom_setup.dart';
import '../../setup/services/classroom_setup_repository.dart';
import '../models/learning_insights.dart';
import 'learning_progress_repository.dart';
import 'student_repository.dart';

/// Works out what a classroom's records add up to.
///
/// An interface so the same screen can later be served by a backend that has
/// every device's data rather than only this one's. Nothing here infers,
/// predicts or explains: every figure is a count or a mean over records the
/// app already holds, and each one carries a sentence saying which records.
abstract interface class ProgressAnalyticsService {
  Future<LearningInsights> insights({
    required InsightPeriod period,
    DateRange? customRange,
    DateTime? now,
  });
}

/// Counts and means over what is on this phone.
///
/// Reads the existing stores — lesson progress, assessment results, saved
/// classroom sessions, flashcard records — and the progress event log, which
/// exists only to supply the timestamps those stores lack. It does not keep a
/// second copy of anything.
class LocalProgressAnalyticsService implements ProgressAnalyticsService {
  LocalProgressAnalyticsService({
    required LessonRepository lessons,
    required LessonProgressRepository lessonProgress,
    required QuizRepository quizzes,
    required AssessmentRepository quickChecks,
    required ClassroomSessionRepository sessions,
    required LearningProgressRepository events,
    required ClassroomSetupRepository classrooms,
    required String teacherId,
    StudentRepository? students,
  })  : _lessons = lessons,
        _lessonProgress = lessonProgress,
        _quizzes = quizzes,
        _quickChecks = quickChecks,
        _sessions = sessions,
        _events = events,
        _classrooms = classrooms,
        _teacherId = teacherId,
        _students = students ?? const DevelopmentStudentRepository();

  /// A lesson counts as completed at this much progress. The lesson feature
  /// only ever reaches 100 by recording a finished assessment, so this is not
  /// a threshold that opening a screen can cross.
  static const int completedAt = 100;

  final LessonRepository _lessons;
  final LessonProgressRepository _lessonProgress;
  final QuizRepository _quizzes;
  final AssessmentRepository _quickChecks;
  final ClassroomSessionRepository _sessions;
  final LearningProgressRepository _events;
  final ClassroomSetupRepository _classrooms;
  final StudentRepository _students;
  final String _teacherId;

  @override
  Future<LearningInsights> insights({
    required InsightPeriod period,
    DateRange? customRange,
    DateTime? now,
  }) async {
    final DateTime at = now ?? DateTime.now();
    final DateRange range = switch (period) {
      InsightPeriod.thisWeek => DateRange.weekOf(at),
      InsightPeriod.lastWeek =>
        DateRange.weekOf(at.subtract(const Duration(days: 7))),
      InsightPeriod.custom => customRange ?? DateRange.weekOf(at),
    };

    final ClassroomSetup? classroom = await _classrooms.load(_teacherId);
    final int classLevel = classroom?.classLevel ?? 1;

    final List<Lesson> lessons = <Lesson>[
      for (final Lesson l in await _lessons.lessons())
        if (l.classNumber == classLevel) l,
    ];
    final Map<String, int> percents = await _lessonProgress.all();
    final List<QuizResult> quizzes = await _quizzes.allResults();
    final List<plan.AssessmentResult> quickChecks = await _quickChecks.all();
    final List<ClassroomSession> sessions = await _sessions.recent(limit: 500);
    final List<ProgressEvent> events = await _events.all();
    final List<StudentProgress> students =
        await _students.forClass(classLevel);

    final Set<String> lessonIds = <String>{
      for (final Lesson l in lessons) l.id,
    };

    // Only this class's records count towards this class's insights.
    final List<QuizResult> ourQuizzes = <QuizResult>[
      for (final QuizResult r in quizzes)
        if (lessonIds.contains(r.lessonId)) r,
    ];
    final List<plan.AssessmentResult> ourChecks = <plan.AssessmentResult>[
      for (final plan.AssessmentResult r in quickChecks)
        if (lessonIds.contains(r.lessonId)) r,
    ];
    final List<ClassroomSession> ourSessions = <ClassroomSession>[
      for (final ClassroomSession s in sessions)
        if (s.classNumber == classLevel) s,
    ];

    final int eventsInRange = <ProgressEvent>[
      for (final ProgressEvent e in events)
        if (range.contains(e.occurredAt)) e,
    ].length +
        _sessionsIn(ourSessions, range).length;

    return LearningInsights(
      range: range,
      period: period,
      classroom: classroom,
      studentCount: students.isEmpty ? null : students.length,
      stats: _stats(
        lessons: lessons,
        percents: percents,
        quizzes: ourQuizzes,
        quickChecks: ourChecks,
        sessions: ourSessions,
        events: events,
        range: range,
      ),
      areas: _areas(
        lessons: lessons,
        percents: percents,
        quizzes: ourQuizzes,
        sessions: ourSessions,
        events: events,
        range: range,
      ),
      attention: await _attention(
        lessons: lessons,
        quizzes: ourQuizzes,
        students: students,
        classLevel: classLevel,
      ),
      eventsInRange: eventsInRange,
      usesPrototypeStudents: students.isNotEmpty && !_students.isRealRoster,
    );
  }

  // --- The four figures ----------------------------------------------------

  List<InsightStat> _stats({
    required List<Lesson> lessons,
    required Map<String, int> percents,
    required List<QuizResult> quizzes,
    required List<plan.AssessmentResult> quickChecks,
    required List<ClassroomSession> sessions,
    required List<ProgressEvent> events,
    required DateRange range,
  }) {
    final int completed = _completedCount(lessons, percents);
    final int completedInRange = _completionsIn(events, range, lessons);

    final int assessments = quizzes.length + quickChecks.length;
    final int assessmentsInRange = _assessmentsIn(quizzes, quickChecks, range);

    final int? engagement = _engagement(sessions, range);
    final int? engagementBefore = _engagement(sessions, range.previous);

    final int? progress = _learningProgress(lessons, percents, quizzes);

    return <InsightStat>[
      InsightStat(
        kind: InsightStatKind.learningProgress,
        value: progress,
        suffix: '%',
        // Percentage points of the class's lessons finished in this period.
        // A finished lesson is worth 100/(number of lessons) points.
        delta: lessons.isEmpty
            ? const InsightDelta.unknown()
            : InsightDelta(
                amount: ((completedInRange / lessons.length) * 100).round(),
                unit: '%',
              ),
      ),
      InsightStat(
        kind: InsightStatKind.lessonsCompleted,
        value: completed,
        delta: InsightDelta(amount: completedInRange, unit: ''),
      ),
      InsightStat(
        kind: InsightStatKind.assessments,
        value: assessments,
        delta: InsightDelta(amount: assessmentsInRange, unit: ''),
      ),
      InsightStat(
        kind: InsightStatKind.engagement,
        value: engagement,
        suffix: '%',
        delta: engagement == null || engagementBefore == null
            ? const InsightDelta.unknown()
            : InsightDelta(amount: engagement - engagementBefore, unit: '%'),
      ),
    ];
  }

  int _completedCount(List<Lesson> lessons, Map<String, int> percents) {
    int count = 0;
    for (final Lesson l in lessons) {
      if ((percents[l.id] ?? 0) >= completedAt) count++;
    }
    return count;
  }

  /// Overall learning progress.
  ///
  /// Six parts how far the class's lessons have got, four parts how the class
  /// scored when it was assessed. With no assessments yet it is simply how far
  /// the lessons have got, rather than a figure held down by an absence.
  int? _learningProgress(
    List<Lesson> lessons,
    Map<String, int> percents,
    List<QuizResult> quizzes,
  ) {
    if (lessons.isEmpty) return null;

    int sum = 0;
    for (final Lesson l in lessons) {
      sum += (percents[l.id] ?? 0).clamp(0, 100);
    }
    final double lessonMean = sum / lessons.length;

    if (quizzes.isEmpty) return lessonMean.round();

    final double assessmentMean = quizzes
            .map((QuizResult r) => r.percentage)
            .reduce((int a, int b) => a + b) /
        quizzes.length;

    return ((lessonMean * 0.6) + (assessmentMean * 0.4)).round();
  }

  int _completionsIn(
    List<ProgressEvent> events,
    DateRange range,
    List<Lesson> lessons,
  ) {
    final Set<String> ours = <String>{for (final Lesson l in lessons) l.id};
    final Set<String> counted = <String>{};
    for (final ProgressEvent e in events) {
      if (e.type != ProgressEventType.lessonCompleted) continue;
      if (!range.contains(e.occurredAt)) continue;
      final String? id = e.lessonId;
      if (id == null || !ours.contains(id)) continue;
      // A lesson finished twice in one week is one lesson completed.
      counted.add(id);
    }
    return counted.length;
  }

  int _assessmentsIn(
    List<QuizResult> quizzes,
    List<plan.AssessmentResult> quickChecks,
    DateRange range,
  ) {
    int count = 0;
    for (final QuizResult r in quizzes) {
      if (range.contains(r.finishedAt)) count++;
    }
    for (final plan.AssessmentResult r in quickChecks) {
      if (range.contains(r.recordedAt)) count++;
    }
    return count;
  }

  List<ClassroomSession> _sessionsIn(
    List<ClassroomSession> sessions,
    DateRange range,
  ) =>
      <ClassroomSession>[
        for (final ClassroomSession s in sessions)
          if (range.contains(s.savedAt ?? s.startedAt)) s,
      ];

  /// Engagement: of everything said in live sessions this period, how much of
  /// it was the children.
  ///
  /// Null when no session was held, because a week with no classroom is not a
  /// week with no engagement — it is a week with nothing to measure.
  int? _engagement(List<ClassroomSession> sessions, DateRange range) {
    final List<ClassroomSession> inRange = _sessionsIn(sessions, range);
    if (inRange.isEmpty) return null;

    int student = 0;
    int spoken = 0;
    for (final ClassroomSession s in inRange) {
      student += s.studentTurns;
      spoken += s.studentTurns + s.teacherTurns;
    }
    if (spoken == 0) return null;
    return ((student / spoken) * 100).round();
  }

  // --- The three learning areas -------------------------------------------

  List<LearningAreaInsight> _areas({
    required List<Lesson> lessons,
    required Map<String, int> percents,
    required List<QuizResult> quizzes,
    required List<ClassroomSession> sessions,
    required List<ProgressEvent> events,
    required DateRange range,
  }) =>
      <LearningAreaInsight>[
        _subjectArea(
          LearningArea.foundationalLiteracy,
          ClassroomSubject.foundationalLiteracy,
          lessons: lessons,
          percents: percents,
          quizzes: quizzes,
          events: events,
          range: range,
        ),
        _subjectArea(
          LearningArea.numeracy,
          ClassroomSubject.numeracy,
          lessons: lessons,
          percents: percents,
          quizzes: quizzes,
          events: events,
          range: range,
        ),
        _languageArea(sessions, range),
      ];

  /// A subject area: how far its lessons have got, blended with how the class
  /// scored on its assessments, in the same six-to-four proportion as the
  /// overall figure.
  LearningAreaInsight _subjectArea(
    LearningArea area,
    ClassroomSubject subject, {
    required List<Lesson> lessons,
    required Map<String, int> percents,
    required List<QuizResult> quizzes,
    required List<ProgressEvent> events,
    required DateRange range,
  }) {
    final List<Lesson> ours = <Lesson>[
      for (final Lesson l in lessons)
        if (l.subject == subject) l,
    ];
    const String basisSuffix =
        'lesson progress and assessment scores for this subject';

    if (ours.isEmpty) {
      return LearningAreaInsight.noData(
        area,
        basis: 'No ${subject.label} lessons for this class yet.',
      );
    }

    final Set<String> ids = <String>{for (final Lesson l in ours) l.id};
    int sum = 0;
    for (final Lesson l in ours) {
      sum += (percents[l.id] ?? 0).clamp(0, 100);
    }
    final double lessonMean = sum / ours.length;

    final List<QuizResult> theirs = <QuizResult>[
      for (final QuizResult r in quizzes)
        if (ids.contains(r.lessonId)) r,
    ];

    final double score = theirs.isEmpty
        ? lessonMean
        : (lessonMean * 0.6) +
            ((theirs
                        .map((QuizResult r) => r.percentage)
                        .reduce((int a, int b) => a + b) /
                    theirs.length) *
                0.4);

    final int completedInRange = _completionsIn(events, range, ours);

    return LearningAreaInsight(
      area: area,
      percentage: score.round(),
      // Percentage points of this subject's lessons finished in this period.
      improvement: InsightDelta(
        amount: ((completedInRange / ours.length) * 100).round(),
        unit: '%',
      ),
      basis: 'From ${ours.length} ${subject.label} lesson'
          '${ours.length == 1 ? '' : 's'} and ${theirs.length} assessment'
          '${theirs.length == 1 ? '' : 's'} — $basisSuffix.',
    );
  }

  /// Language Understanding: of everything said in a live session, how much
  /// reached the children in their own language without failing.
  LearningAreaInsight _languageArea(
    List<ClassroomSession> sessions,
    DateRange range,
  ) {
    int completed = 0;
    int turns = 0;
    for (final ClassroomSession s in sessions) {
      completed += s.interactionsCompleted;
      turns += s.totalTurns;
    }

    if (turns == 0) {
      return const LearningAreaInsight.noData(
        LearningArea.languageUnderstanding,
        basis: 'No live classroom session has been saved yet.',
      );
    }

    final int score = ((completed / turns) * 100).round();
    final int? before = _languageScore(_sessionsIn(sessions, range.previous));
    final int? current = _languageScore(_sessionsIn(sessions, range));

    return LearningAreaInsight(
      area: LearningArea.languageUnderstanding,
      percentage: score,
      improvement: current == null || before == null
          ? const InsightDelta.unknown()
          : InsightDelta(amount: current - before, unit: '%'),
      basis: 'From $turns conversation turn${turns == 1 ? '' : 's'} across '
          '${sessions.length} saved session${sessions.length == 1 ? '' : 's'} '
          '— the share that reached the class in their own language.',
    );
  }

  int? _languageScore(List<ClassroomSession> sessions) {
    int completed = 0;
    int turns = 0;
    for (final ClassroomSession s in sessions) {
      completed += s.interactionsCompleted;
      turns += s.totalTurns;
    }
    return turns == 0 ? null : ((completed / turns) * 100).round();
  }

  // --- Who needs help with what -------------------------------------------

  Future<List<AttentionGroup>> _attention({
    required List<Lesson> lessons,
    required List<QuizResult> quizzes,
    required List<StudentProgress> students,
    required int classLevel,
  }) async {
    // A concept is weak when a real assessment marked it so, or when the
    // pupil records say children are still practising it.
    final Map<String, int> weakFromAssessments = <String, int>{};
    final Map<String, String> conceptLesson = <String, String>{};

    for (final QuizResult r in quizzes) {
      for (final ConceptPerformance c in r.needsReinforcement) {
        weakFromAssessments[c.concept.label] =
            (weakFromAssessments[c.concept.label] ?? 0) + 1;
        conceptLesson[c.concept.label] ??= r.lessonId;
      }
    }

    final Map<String, int> weakFromStudents = <String, int>{};
    for (final StudentProgress s in students) {
      for (final String concept in s.conceptsNeedingPractice) {
        weakFromStudents[concept] = (weakFromStudents[concept] ?? 0) + 1;
      }
    }

    final Set<String> concepts = <String>{
      ...weakFromAssessments.keys,
      ...weakFromStudents.keys,
    };
    if (concepts.isEmpty) return const <AttentionGroup>[];

    final List<AttentionGroup> groups = <AttentionGroup>[];
    for (final String concept in concepts) {
      final List<StudentProgress> needing = <StudentProgress>[
        for (final StudentProgress s in students)
          if (s.needsPracticeWith(concept)) s,
      ]..sort(
          (StudentProgress a, StudentProgress b) =>
              a.engagementScore.compareTo(b.engagementScore),
        );

      groups.add(
        AttentionGroup(
          concept: concept,
          students: List<StudentProgress>.unmodifiable(needing),
          headline: needing.isEmpty
              // No roster, so the class is described rather than a count of
              // children the app cannot actually see.
              ? 'This class needs more practice with $concept.'
              : '${needing.length} learner${needing.length == 1 ? '' : 's'} '
                  'need more practice with $concept.',
          detail: _detailFor(concept, weakFromAssessments[concept] ?? 0),
          lessonId: conceptLesson[concept] ??
              _lessonTeaching(concept, lessons)?.id,
        ),
      );
    }

    // Worst first: most children, then most assessment questions missed.
    groups.sort((AttentionGroup a, AttentionGroup b) {
      final int byCount = b.count.compareTo(a.count);
      if (byCount != 0) return byCount;
      return (weakFromAssessments[b.concept] ?? 0)
          .compareTo(weakFromAssessments[a.concept] ?? 0);
    });

    return List<AttentionGroup>.unmodifiable(groups);
  }

  /// A plain sentence about what the concept means in a classroom.
  ///
  /// Written from the concept name and the number of assessment questions it
  /// was missed on. Nothing here is generated by a model.
  static String _detailFor(String concept, int missedQuestions) {
    final String lower = concept.toLowerCase();
    final String what = switch (lower) {
      final String c when c.contains('6–10') || c.contains('6-10') =>
        'They can count up to five but lose track beyond it.',
      final String c when c.contains('mixed') =>
        'They can count one kind of object but not a mixed group.',
      final String c when c.contains('one-to-one') =>
        'They count the objects but do not yet match one to each child.',
      final String c when c.contains('1–5') || c.contains('1-5') =>
        'The first five numbers are still being learned.',
      _ => 'This came up as unfinished in their recorded work.',
    };
    if (missedQuestions == 0) return what;
    return '$what Missed on $missedQuestions assessment '
        'question${missedQuestions == 1 ? '' : 's'}.';
  }

  /// The lesson whose own concept list names this concept.
  static Lesson? _lessonTeaching(String concept, List<Lesson> lessons) {
    final String needle = concept.toLowerCase();
    for (final Lesson l in lessons) {
      for (final String c in l.concepts) {
        if (c.toLowerCase() == needle) return l;
      }
    }
    // Failing an exact match, a lesson whose concept contains the same words.
    for (final Lesson l in lessons) {
      for (final String c in l.concepts) {
        if (needle.contains(c.toLowerCase()) ||
            c.toLowerCase().contains(needle)) {
          return l;
        }
      }
    }
    return null;
  }
}
