import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/constants/app_colors.dart';
import '../../models/flashcard.dart';
import '../../models/lesson.dart';
import '../../models/student_progress.dart';
import '../../services/storage/secure_storage_service.dart';
import '../assessment/services/quiz_repository.dart';
import '../auth/services/auth_session_store.dart';
import '../classroom/services/classroom_session_repository.dart';
import '../flashcards/flashcards_screen.dart' show FlashcardsArgs;
import '../lessons/lesson_navigation.dart';
import '../lessons/services/assessment_repository.dart';
import '../lessons/services/lesson_repository.dart';
import '../setup/data/classroom_setup_storage.dart';
import '../setup/services/classroom_setup_repository.dart';
import 'models/learning_insights.dart';
import 'services/learning_progress_repository.dart';
import 'services/learning_recommendation_service.dart';
import 'services/progress_analytics_service.dart';
import 'services/progress_controller.dart';
import 'services/student_repository.dart';
import 'student_progress_screen.dart';
import 'widgets/progress_widgets.dart';

/// Learning Insights.
///
/// Everything on this screen is counted or averaged from records already on
/// this phone — how far each lesson got, what assessments scored, what was said
/// in saved classroom sessions. There is no figure here that the app invented
/// to fill the layout: an area with nothing recorded says "No data yet", a week
/// with nothing in it says so, and the recommendation at the bottom names
/// itself as a rule rather than a model.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({
    this.controller,
    this.analytics,
    this.lessons,
    this.students,
    this.recommendations,
    super.key,
  });

  static const Key scrollKey = Key('insights-scroll');
  static const Key skeletonKey = Key('insights-skeleton');
  static const Key backKey = Key('insights-back');
  static const Key moreKey = Key('insights-more');
  static const Key statusKey = Key('insights-status');
  static const Key periodKey = Key('insights-period');
  static const Key classKey = Key('insights-class');
  static const Key howCalculatedKey = Key('insights-how-calculated');
  static const Key attentionKey = Key('insights-attention');
  static const Key viewStudentsKey = Key('insights-view-students');
  static const Key recommendationKey = Key('insights-recommendation');
  static const Key reinforcementKey = Key('insights-reinforcement');
  static const Key flashcardsKey = Key('insights-flashcards');
  static const Key retryKey = Key('insights-retry');
  static const Key emptyPeriodKey = Key('insights-empty-period');
  static const Key sampleDataKey = Key('insights-sample-data');

  static Key statKey(InsightStatKind kind) => Key('insights-stat-${kind.name}');

  static Key areaKey(LearningArea area) => Key('insights-area-${area.name}');

  /// Supplied whole by tests; built from the parts below otherwise.
  final ProgressController? controller;

  final ProgressAnalyticsService? analytics;
  final LessonRepository? lessons;
  final StudentRepository? students;
  final LearningRecommendationService? recommendations;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> with RouteAware {
  ProgressController? _controller;
  bool _built = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_built) return;
    _built = true;

    final ProgressController? given = widget.controller;
    if (given != null) {
      _controller = given;
      return;
    }
    unawaited(_build());
  }

  Future<void> _build() async {
    final SecureStorageService storage = PlatformSecureStorageService();
    final String teacherId =
        (await AuthSessionStore(storage).account())?.id ?? 'local-teacher';
    if (!mounted) return;

    final LessonRepository lessons = widget.lessons ??
        defaultLessonRepository(
          storage: storage,
          downloads: LocalLessonDownloadRepository(storage),
        );

    // Every source here already exists and is the same one the feature that
    // writes it uses. Nothing is duplicated for the sake of analytics.
    final ProgressAnalyticsService analytics = widget.analytics ??
        LocalProgressAnalyticsService(
          lessons: lessons,
          lessonProgress: LocalLessonProgressRepository(storage),
          quizzes: LocalQuizRepository(storage: storage),
          quickChecks: LocalAssessmentRepository(storage),
          sessions: LocalClassroomSessionRepository(storage),
          events: LocalLearningProgressRepository(storage),
          classrooms:
              LocalClassroomSetupRepository(defaultClassroomSetupStorage()),
          teacherId: teacherId,
          students: widget.students,
        );

    final ProgressController controller = ProgressController(
      analytics: analytics,
      lessons: lessons,
      students: widget.students,
      recommendations: widget.recommendations,
    );

    setState(() => _controller = controller);
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller?.dispose();
    super.dispose();
  }

  // --- Actions -------------------------------------------------------------

  /// Recalculates when the teacher comes back from a lesson or an assessment,
  /// so the figures are current without an app restart.
  Future<void> _openAndRefresh(Future<void> Function() open) async {
    await open();
    if (!mounted) return;
    await _controller?.refresh();
  }

  Future<void> _pickPeriod(ProgressController c) async {
    final InsightPeriod? chosen = await showModalBottomSheet<InsightPeriod>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const _SheetGrip(),
            for (final InsightPeriod p in <InsightPeriod>[
              InsightPeriod.thisWeek,
              InsightPeriod.lastWeek,
            ])
              ListTile(
                leading: Icon(
                  p == c.period
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: p == c.period
                      ? AppColors.setupNumeracy
                      : AppColors.brandMuted,
                ),
                title: Text(p.label),
                subtitle: Text(_rangeFor(p, c).label),
                onTap: () => Navigator.of(sheetContext).pop(p),
              ),
            ListTile(
              leading: const Icon(Icons.date_range_outlined),
              title: const Text('Custom range'),
              subtitle: const Text('Pick any two dates'),
              onTap: () => Navigator.of(sheetContext).pop(InsightPeriod.custom),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;

    if (chosen != InsightPeriod.custom) {
      await c.selectPeriod(chosen);
      return;
    }

    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(
        start: c.range.start,
        end: c.range.end,
      ),
    );
    if (picked == null || !mounted) return;
    await c.selectCustomRange(
      DateRange(start: picked.start, end: picked.end),
    );
  }

  DateRange _rangeFor(InsightPeriod period, ProgressController c) {
    final DateTime now = DateTime.now();
    return switch (period) {
      InsightPeriod.thisWeek => DateRange.weekOf(now),
      InsightPeriod.lastWeek =>
        DateRange.weekOf(now.subtract(const Duration(days: 7))),
      InsightPeriod.custom => c.range,
    };
  }

  Future<void> _pickClass(ProgressController c) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _SheetGrip(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text(
                c.classSummary,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                c.classroom?.summaryLine ??
                    'Classroom setup has not been completed on this device.',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.brandBody,
                ),
              ),
            ),
            if (c.usesPrototypeStudents)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  'The pupil count comes from a sample class. No roster has '
                  'been entered on this device.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    fontStyle: FontStyle.italic,
                    color: AppColors.brandMuted,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Change the class in Classroom Setup'),
              subtitle: const Text(
                'Insights follow the class saved there',
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(
                  _openAndRefresh(
                    () => Navigator.of(context).pushNamed(AppRoutes.setup),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _showHowCalculated(ProgressController c) {
    final LearningInsights? insights = c.insights;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (BuildContext sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        builder: (BuildContext context, ScrollController scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          children: <Widget>[
            const Center(child: _SheetGrip()),
            const SizedBox(height: 4),
            const Text(
              'How these figures are worked out',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.brandNavy,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'All of it is arithmetic on this phone, over what you have '
              'recorded. None of it is a prediction, and none of it was '
              'written by a model.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: AppColors.brandBody,
              ),
            ),
            const SizedBox(height: 18),
            const _Explanation(
              title: 'Learning Progress',
              body: 'How far the lessons for your class have got, counted six '
                  'parts out of ten, and how those lessons scored when they '
                  'were assessed, counted four parts out of ten. With no '
                  'assessment recorded yet it is simply how far the lessons '
                  'have got.',
            ),
            const _Explanation(
              title: 'Lessons Completed',
              body: 'Lessons at 100%. A lesson only reaches 100% when its '
                  'quick assessment has been recorded — opening a lesson '
                  'earns nothing.',
            ),
            const _Explanation(
              title: 'Assessments',
              body: 'Finished assessments: the multiple-choice ones the app '
                  'marks, plus the quick checks you mark yourself. An '
                  'assessment that was left unfinished is not counted.',
            ),
            const _Explanation(
              title: 'Engagement',
              body: 'Of everything said in your saved live classroom sessions '
                  'this period, the share that was the children rather than '
                  'you. With no session held there is nothing to measure, and '
                  'it shows a dash rather than a zero.',
            ),
            const _Explanation(
              title: 'Foundational Literacy and Numeracy',
              body: 'The same six-to-four mix as Learning Progress, but over '
                  'only that subject’s lessons and assessments. The chip '
                  'underneath is the share of that subject’s lessons finished '
                  'in the period you are looking at.',
            ),
            const _Explanation(
              title: 'Language Understanding',
              body: 'Of everything said in your saved classroom sessions, the '
                  'share that reached the class in their own language without '
                  'the translation or the audio failing.',
            ),
            const _Explanation(
              title: 'Needs Attention',
              body: 'Concepts that a recorded assessment marked as needing '
                  'reinforcement, and concepts the pupil records list as still '
                  'being practised. A concept counts as understood only when '
                  'every question testing it was answered correctly.',
            ),
            const _Explanation(
              title: 'Recommended Action',
              body: 'A rule picks the concept with the most children behind on '
                  'it and points at the lesson or the flashcard deck that '
                  'covers it. It has not read any child’s work.',
            ),
            if (insights != null) ...<Widget>[
              const SizedBox(height: 6),
              const Divider(color: AppColors.authFieldBorder),
              const SizedBox(height: 10),
              const Text(
                'What this screen read',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                ),
              ),
              const SizedBox(height: 8),
              for (final LearningAreaInsight a in insights.areas)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '• ${a.basis}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppColors.brandMuted,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 14),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openStudents(ProgressController c) async {
    final AttentionGroup? group = c.attention;
    if (group == null) return;

    // Resolved before navigating, so the screen is handed a list rather than a
    // future it would have to show a spinner for.
    final List<StudentProgress> students = await c.studentsFor(group);
    if (!mounted) return;

    await _openAndRefresh(
      () => Navigator.of(context).pushNamed(
        AppRoutes.students,
        arguments: StudentProgressArgs(
          group: group,
          students: students,
          usesPrototypeData: c.usesPrototypeStudents,
          classLabel: c.classSummary,
        ),
      ),
    );
  }

  /// Opens the lesson the recommendation names, or the library when no lesson
  /// in this class covers the concept.
  Future<void> _startReinforcement(ProgressController c) async {
    final Lesson? lesson = c.reinforcementLesson;

    await _openAndRefresh(() async {
      if (lesson != null) {
        await Navigator.of(context).pushNamed(
          AppRoutes.lessonDetail,
          arguments: LessonDetailArgs(lesson.id),
        );
        return;
      }
      await Navigator.of(context).pushNamed(AppRoutes.lessons);
    });
  }

  Future<void> _practiseFlashcards(ProgressController c) async {
    final LearningAction? action = c.action;
    await _openAndRefresh(
      () => Navigator.of(context).pushNamed(
        AppRoutes.flashcards,
        arguments: FlashcardsArgs(
          lessonId: action?.lessonId,
          category: action?.flashcardCategory ?? FlashcardCategory.numbers,
        ),
      ),
    );
  }

  Future<void> _openMenu(ProgressController c) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const _SheetGrip(),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Recalculate now'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(c.load());
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('How these figures are worked out'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showHowCalculated(c);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ProgressController? c = _controller;
    if (c == null) return const _Shell(child: _Skeleton());

    return AnimatedBuilder(
      animation: c,
      builder: (BuildContext context, _) {
        switch (c.state) {
          case InsightsState.loading:
            return const _Shell(child: _Skeleton());
          case InsightsState.error:
            return _Shell(
              child: _Message(
                icon: Icons.error_outline,
                title: 'Unable to load learning insights.',
                body: 'These figures are worked out from records on this '
                    'phone, so this is usually worth another try.',
                actionKey: ProgressScreen.retryKey,
                actionLabel: 'Retry',
                onAction: c.load,
                secondaryLabel: 'Back',
                onSecondary: () => Navigator.of(context).maybePop(),
              ),
            );
          case InsightsState.ready:
            return _ready(context, c, c.insights!);
        }
      },
    );
  }

  Widget _ready(
    BuildContext context,
    ProgressController c,
    LearningInsights insights,
  ) {
    return Scaffold(
      backgroundColor: AppColors.homePage,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            InsightsHeader(
              backKey: ProgressScreen.backKey,
              moreKey: ProgressScreen.moreKey,
              statusKey: ProgressScreen.statusKey,
              // Back, not "go Home": this screen is reached from Home, from a
              // finished assessment and from the lesson flow.
              onBack: () => Navigator.of(context).maybePop(),
              onMore: () => _openMenu(c),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: c.load,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double width = constraints.maxWidth;
                    final double contentWidth = width.clamp(0.0, 760.0);
                    final double side = ((width - contentWidth) / 2) + 16;

                    return ListView(
                      key: ProgressScreen.scrollKey,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(side, 2, side, 26),
                      children: <Widget>[
                        _title(c, width),
                        const SizedBox(height: 14),
                        _classSelector(c),
                        if (c.usesPrototypeStudents) ...<Widget>[
                          const SizedBox(height: 12),
                          const InsightNotice(
                            key: ProgressScreen.sampleDataKey,
                            message: 'Pupil names and counts on this screen '
                                'come from a sample class. No roster has been '
                                'entered on this device yet, so no real child '
                                'is described here.',
                          ),
                        ],
                        const SizedBox(height: 16),
                        _stats(c, insights, width),
                        if (!insights.hasActivityInRange) ...<Widget>[
                          const SizedBox(height: 14),
                          InsightNotice(
                            key: ProgressScreen.emptyPeriodKey,
                            icon: Icons.event_busy_outlined,
                            tint: AppColors.setupNumeracy,
                            background: AppColors.setupNumeracyTint,
                            border: AppColors.authFieldBorder,
                            message: insights.hasAnyHistory
                                ? 'No learning activity was recorded for '
                                    '${insights.range.label}. The totals above '
                                    'are everything recorded so far.'
                                : 'Start your first lesson to see classroom '
                                    'insights here.',
                          ),
                        ],
                        const SizedBox(height: 22),
                        _areasHeader(c, width),
                        const SizedBox(height: 12),
                        _areas(insights, width),
                        const SizedBox(height: 22),
                        _attention(c, insights, width),
                        const SizedBox(height: 18),
                        const InsightsFooter(),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _title(ProgressController c, double width) {
    final Widget heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'Learning Insights',
            maxLines: 1,
            style: TextStyle(
              fontSize: 30,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.9,
              color: AppColors.brandNavy,
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Understand your classroom’s progress at a glance.',
          style: TextStyle(
            fontSize: 14.5,
            height: 1.4,
            color: AppColors.brandMuted,
          ),
        ),
      ],
    );

    final Widget selector = Column(
      crossAxisAlignment:
          width >= 520 ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SelectorPill(
          key: ProgressScreen.periodKey,
          compact: true,
          icon: Icons.calendar_today_outlined,
          label: c.period.label,
          semanticLabel: 'Period: ${c.period.label}, ${c.range.label}. '
              'Change the period',
          onTap: () => _pickPeriod(c),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 6, right: 6, top: 2),
          child: Text(
            c.range.label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.brandMuted,
            ),
          ),
        ),
      ],
    );

    // Below this the title and the selector cannot share a line without the
    // title shrinking to nothing.
    if (width < 520) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          heading,
          const SizedBox(height: 8),
          selector,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: heading),
        const SizedBox(width: 12),
        selector,
      ],
    );
  }

  Widget _classSelector(ProgressController c) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SelectorPill(
        key: ProgressScreen.classKey,
        icon: Icons.groups_outlined,
        label: c.classSummary,
        semanticLabel: '${c.classSummary}. Class details',
        onTap: () => _pickClass(c),
      ),
    );
  }

  Widget _stats(
    ProgressController c,
    LearningInsights insights,
    double width,
  ) {
    final String periodWord =
        c.period == InsightPeriod.custom ? 'period' : 'week';

    final List<Widget> cards = <Widget>[
      StatCard(
        key: ProgressScreen.statKey(InsightStatKind.learningProgress),
        stat: insights.statFor(InsightStatKind.learningProgress),
        icon: Icons.auto_stories_outlined,
        tint: AppColors.setupLiteracy,
        background: AppColors.setupLiteracyTint,
        periodWord: periodWord,
      ),
      StatCard(
        key: ProgressScreen.statKey(InsightStatKind.lessonsCompleted),
        stat: insights.statFor(InsightStatKind.lessonsCompleted),
        icon: Icons.menu_book_outlined,
        tint: AppColors.liveGlowViolet,
        background: const Color(0xFFF4F1FD),
        periodWord: periodWord,
      ),
      StatCard(
        key: ProgressScreen.statKey(InsightStatKind.assessments),
        stat: insights.statFor(InsightStatKind.assessments),
        icon: Icons.assignment_turned_in_outlined,
        tint: AppColors.brandOrange,
        background: AppColors.homeBannerTint,
        periodWord: periodWord,
      ),
      StatCard(
        key: ProgressScreen.statKey(InsightStatKind.engagement),
        stat: insights.statFor(InsightStatKind.engagement),
        icon: Icons.groups_outlined,
        tint: AppColors.setupNumeracy,
        background: AppColors.setupNumeracyTint,
        periodWord: periodWord,
      ),
    ];

    // Four across only where each card keeps about 150dp; two across on a
    // phone, which is where this screen actually lives.
    final int columns = width >= 700 ? 4 : 2;
    const double gap = 12;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double tile =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final Widget card in cards)
              SizedBox(width: tile, child: card),
          ],
        );
      },
    );
  }

  Widget _areasHeader(ProgressController c, double width) {
    final Widget title = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(
          Icons.insights_outlined,
          size: 22,
          color: AppColors.setupNumeracy,
        ),
        const SizedBox(width: 9),
        Flexible(
          child: Text(
            'Learning Areas Overview',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.brandNavy,
            ),
          ),
        ),
      ],
    );

    final Widget how = Semantics(
      button: true,
      label: 'How is this calculated?',
      child: ExcludeSemantics(
        child: TextButton.icon(
          key: ProgressScreen.howCalculatedKey,
          onPressed: () => _showHowCalculated(c),
          icon: const Icon(Icons.info_outline, size: 17),
          label: const Text('How is this calculated?'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.brandMuted,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            textStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );

    if (width < 480) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          title,
          Align(alignment: Alignment.centerLeft, child: how),
        ],
      );
    }
    return Row(
      children: <Widget>[
        Expanded(child: title),
        const SizedBox(width: 8),
        how,
      ],
    );
  }

  Widget _areas(LearningInsights insights, double width) {
    final List<Widget> cards = <Widget>[
      for (final LearningAreaInsight a in insights.areas)
        LearningAreaCard(
          key: ProgressScreen.areaKey(a.area),
          insight: a,
          icon: switch (a.area) {
            LearningArea.foundationalLiteracy => Icons.menu_book_outlined,
            LearningArea.numeracy => Icons.calculate_outlined,
            LearningArea.languageUnderstanding => Icons.forum_outlined,
          },
          colour: switch (a.area) {
            LearningArea.foundationalLiteracy => AppColors.setupLiteracy,
            LearningArea.numeracy => AppColors.liveGlowViolet,
            LearningArea.languageUnderstanding => AppColors.setupNumeracy,
          },
          tint: switch (a.area) {
            LearningArea.foundationalLiteracy => AppColors.setupLiteracyTint,
            LearningArea.numeracy => const Color(0xFFF4F1FD),
            LearningArea.languageUnderstanding => AppColors.setupNumeracyTint,
          },
          periodWord: 'week',
          ringSize: width >= 700 ? 128 : 140,
        ),
    ];

    if (width < 700) {
      return Column(
        children: <Widget>[
          for (int i = 0; i < cards.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: 12),
            cards[i],
          ],
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < cards.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: cards[i]),
          ],
        ],
      ),
    );
  }

  // --- Needs attention -----------------------------------------------------

  Widget _attention(
    ProgressController c,
    LearningInsights insights,
    double width,
  ) {
    final AttentionGroup? group = insights.weakest;
    final LearningAction? action = c.action;

    return Container(
      key: ProgressScreen.attentionKey,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF7F5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF6DFD8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.warning_amber_rounded,
                size: 22,
                color: AppColors.error,
              ),
              const SizedBox(width: 9),
              const Flexible(
                child: Text(
                  'Needs Attention',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          const Padding(
            padding: EdgeInsets.only(left: 31),
            child: Text(
              'Identify learners who need extra support.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.brandMuted,
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (group == null)
            const InsightNotice(
              icon: Icons.check_circle_outline,
              tint: AppColors.setupLiteracy,
              background: AppColors.setupLiteracyTint,
              border: AppColors.authFieldBorder,
              message: 'No concept in the recorded work is marked as needing '
                  'more practice. Record an assessment and anything that needs '
                  'reinforcement will be named here.',
            )
          else
            _attentionCard(c, group, width),
          if (action != null) ...<Widget>[
            const SizedBox(height: 12),
            _recommendation(c, action),
          ],
          const SizedBox(height: 14),
          _reinforcementButton(c),
          if (action?.flashcardCategory != null) ...<Widget>[
            const SizedBox(height: 10),
            _flashcardsButton(c, action!.flashcardCategory!),
          ],
        ],
      ),
    );
  }

  Widget _attentionCard(
    ProgressController c,
    AttentionGroup group,
    double width,
  ) {
    final Widget description = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.error.withValues(alpha: 0.1),
          ),
          child: const Icon(
            Icons.groups_outlined,
            size: 21,
            color: AppColors.error,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                group.headline,
                style: const TextStyle(
                  fontSize: 15.5,
                  height: 1.3,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                group.detail,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.brandBody,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final Widget roster = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text(
          'Students',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.brandBody,
          ),
        ),
        const SizedBox(height: 10),
        StudentAvatarRow(students: group.students),
        const SizedBox(height: 10),
        Semantics(
          button: true,
          label: 'View all ${group.count} students',
          child: ExcludeSemantics(
            child: InkWell(
              key: ProgressScreen.viewStudentsKey,
              onTap: () => _openStudents(c),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        'View all ${group.count} students',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.setupNumeracy,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Icon(
                      Icons.arrow_forward,
                      size: 16,
                      color: AppColors.setupNumeracy,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 14, 13, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: group.students.isEmpty
          ? description
          : (width >= 620
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(flex: 3, child: description),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: roster),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    description,
                    const SizedBox(height: 16),
                    roster,
                  ],
                )),
    );
  }

  Widget _recommendation(ProgressController c, LearningAction action) {
    return Container(
      key: ProgressScreen.recommendationKey,
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 13),
      decoration: BoxDecoration(
        color: AppColors.homeBannerTint,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.secondaryContainer),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.brandGold.withValues(alpha: 0.22),
                ),
                child: const Icon(
                  Icons.lightbulb_outline,
                  size: 20,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Recommended Action',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      action.headline,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandNavy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      action.body,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: AppColors.brandBody,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          // Named for what it is. This is a rule over counts, and calling it
          // an AI recommendation would be a claim the app cannot make.
          Text(
            action.sourceNote,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.4,
              fontStyle: FontStyle.italic,
              color: AppColors.brandMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _reinforcementButton(ProgressController c) {
    final Lesson? lesson = c.reinforcementLesson;
    final String label = lesson == null
        ? 'Find a lesson in the library'
        : c.reinforcementLabel;

    return Semantics(
      button: true,
      label: lesson == null
          ? 'Find a reinforcement lesson in the library'
          : 'Start reinforcement lesson: ${lesson.title}',
      child: ExcludeSemantics(
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: ProgressScreen.reinforcementKey,
            onPressed: () => _startReinforcement(c),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.setupLiteracy,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 58),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.school_outlined, size: 22),
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const Icon(Icons.arrow_forward, size: 21),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _flashcardsButton(ProgressController c, FlashcardCategory category) {
    return Semantics(
      button: true,
      label: 'Practise ${category.label} flashcards',
      child: ExcludeSemantics(
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            key: ProgressScreen.flashcardsKey,
            onPressed: () => _practiseFlashcards(c),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.brandNavy,
              minimumSize: const Size(0, 52),
              side: const BorderSide(color: AppColors.authFieldBorder),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            // A Row rather than OutlinedButton.icon: the built-in one does not
            // let the label give way, so a long deck name would overflow.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.style_outlined, size: 19),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    'Practice with ${category.label} Flashcards',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The grab handle at the top of every sheet on this screen.
class _SheetGrip extends StatelessWidget {
  const _SheetGrip();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 8),
        child: Center(
          child: Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.outline,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      );
}

class _Explanation extends StatelessWidget {
  const _Explanation({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.brandNavy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.brandBody,
              ),
            ),
          ],
        ),
      );
}

/// The plain scaffold used by the loading and error states.
class _Shell extends StatelessWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.homePage,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            InsightsHeader(
              backKey: ProgressScreen.backKey,
              statusKey: ProgressScreen.statusKey,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    Widget block(double height, double widthFactor) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: widthFactor,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: AppColors.authIconCircle,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );

    return Padding(
      key: ProgressScreen.skeletonKey,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          block(30, 0.66),
          const SizedBox(height: 10),
          block(15, 0.82),
          const SizedBox(height: 18),
          block(44, 0.58),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(child: block(128, 1)),
              const SizedBox(width: 12),
              Expanded(child: block(128, 1)),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(child: block(double.infinity, 1)),
        ],
      ),
    );
  }
}

/// A full-screen explanation with up to two actions.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.actionKey,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String body;
  final Key? actionKey;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 42, color: AppColors.brandMuted),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.brandNavy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                color: AppColors.brandMuted,
              ),
            ),
            if (onAction != null) ...<Widget>[
              const SizedBox(height: 18),
              FilledButton(
                key: actionKey,
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.authNavy,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 13,
                  ),
                ),
                child: Text(actionLabel ?? 'Retry'),
              ),
            ],
            if (onSecondary != null) ...<Widget>[
              const SizedBox(height: 6),
              TextButton(
                onPressed: onSecondary,
                child: Text(secondaryLabel ?? 'Back'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
