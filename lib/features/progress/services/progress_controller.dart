// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/utils/app_logger.dart';
import '../../../models/lesson.dart';
import '../../../models/student_progress.dart';
import '../../lessons/services/lesson_repository.dart';
import '../../setup/models/classroom_setup.dart';
import '../models/learning_insights.dart';
import 'learning_recommendation_service.dart';
import 'progress_analytics_service.dart';
import 'student_repository.dart';

/// Where the insights screen is in its own lifecycle.
enum InsightsState { loading, ready, error }

/// Drives the Learning Insights screen.
///
/// Holds the selected period, the calculated insights and the recommendation.
/// It knows nothing about how any figure is worked out — that is the analytics
/// service — and nothing about where records are stored.
class ProgressController extends ChangeNotifier {
  ProgressController({
    required ProgressAnalyticsService analytics,
    required LessonRepository lessons,
    StudentRepository? students,
    LearningRecommendationService? recommendations,
    DateTime Function()? clock,
  })  : _analytics = analytics,
        _lessons = lessons,
        _students = students ?? const DevelopmentStudentRepository(),
        _recommendations =
            recommendations ?? const LocalLearningRecommendationService(),
        _now = clock ?? DateTime.now {
    unawaited(load());
  }

  final ProgressAnalyticsService _analytics;
  final LessonRepository _lessons;
  final StudentRepository _students;
  final LearningRecommendationService _recommendations;
  final DateTime Function() _now;

  InsightsState _state = InsightsState.loading;
  InsightsState get state => _state;

  LearningInsights? _insights;
  LearningInsights? get insights => _insights;

  LearningAction? _action;

  /// What to do next. Null only while nothing has loaded.
  LearningAction? get action => _action;

  List<Lesson> _catalogue = const <Lesson>[];

  /// Every lesson for this class, used to name a reinforcement lesson.
  List<Lesson> get catalogue => _catalogue;

  InsightPeriod _period = InsightPeriod.thisWeek;
  InsightPeriod get period => _period;

  DateRange? _customRange;

  /// The range currently being reported on.
  DateRange get range =>
      _insights?.range ?? DateRange.weekOf(_now());

  ClassroomSetup? get classroom => _insights?.classroom;

  /// "Class 1 • 24 students", or an honest substitute when there is no roster.
  String get classSummary {
    final int level = classroom?.classLevel ?? 1;
    final int? roll = _insights?.studentCount;
    return roll == null
        ? 'Class $level  •  No pupil records'
        : 'Class $level  •  $roll students';
  }

  /// True while the pupil figures come from the sample class rather than a
  /// roster somebody entered. Every screen showing them must say so.
  bool get usesPrototypeStudents =>
      _insights?.usesPrototypeStudents ?? false;

  bool get hasActivityInRange => _insights?.hasActivityInRange ?? false;

  bool get hasAnyHistory => _insights?.hasAnyHistory ?? false;

  /// The concept most in need of work, or null when none is.
  AttentionGroup? get attention => _insights?.weakest;

  /// Every concept needing work, worst first.
  List<AttentionGroup> get allAttention =>
      _insights?.attention ?? const <AttentionGroup>[];

  /// The lesson the reinforcement button would open, or null when no lesson
  /// covers the weak concept and the library should be opened instead.
  Lesson? get reinforcementLesson {
    final String? id = _action?.lessonId;
    if (id == null) return null;
    for (final Lesson l in _catalogue) {
      if (l.id == id) return l;
    }
    return null;
  }

  String get reinforcementLabel => 'Start Reinforcement Lesson';

  // --- Loading -------------------------------------------------------------

  Future<void> load() async {
    _state = InsightsState.loading;
    notifyListeners();

    try {
      final LearningInsights insights = await _analytics.insights(
        period: _period,
        customRange: _customRange,
        now: _now(),
      );
      final int level = insights.classroom?.classLevel ?? 1;
      _catalogue = <Lesson>[
        for (final Lesson l in await _lessons.lessons())
          if (l.classNumber == level) l,
      ];

      _insights = insights;
      _action = _recommendations.recommend(
        insights: insights,
        lessons: _catalogue,
      );
      _state = InsightsState.ready;
    } on Object catch (error) {
      AppLogger.error('learning insights could not be built', error: error);
      _state = InsightsState.error;
    }
    notifyListeners();
  }

  /// Recalculates without dropping what is on screen.
  ///
  /// Used when returning to the screen, so completing an assessment and coming
  /// back shows the new figures without a restart and without a flash of
  /// skeleton.
  Future<void> refresh() async {
    if (_state != InsightsState.ready) return load();
    try {
      final LearningInsights insights = await _analytics.insights(
        period: _period,
        customRange: _customRange,
        now: _now(),
      );
      _insights = insights;
      _action = _recommendations.recommend(
        insights: insights,
        lessons: _catalogue,
      );
      notifyListeners();
    } on Object catch (error) {
      AppLogger.error('learning insights could not be refreshed', error: error);
    }
  }

  Future<void> selectPeriod(InsightPeriod period) async {
    if (period == _period && period != InsightPeriod.custom) return;
    _period = period;
    if (period != InsightPeriod.custom) _customRange = null;
    await load();
  }

  Future<void> selectCustomRange(DateRange range) async {
    _period = InsightPeriod.custom;
    _customRange = range;
    await load();
  }

  /// The children behind on [group], for the students screen.
  Future<List<StudentProgress>> studentsFor(AttentionGroup group) async {
    if (group.students.isNotEmpty) return group.students;
    return _students.needingPracticeWith(
      group.concept,
      classLevel: classroom?.classLevel ?? 1,
    );
  }
}
