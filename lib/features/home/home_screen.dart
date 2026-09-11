import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_bottom_navigation.dart';
import '../../data/mock_lessons.dart';
import '../../models/lesson.dart';
import '../../services/audio/language_audio_service.dart';
import '../../services/connectivity/connectivity_service.dart';
import '../../services/storage/secure_storage_service.dart';
import '../auth/services/auth_session_store.dart';
import '../flashcards/flashcards_screen.dart' show FlashcardsArgs;
import '../lessons/lesson_navigation.dart'
    show LessonAssessmentArgs, LessonDetailArgs;
import '../../models/lesson_plan.dart'
    show AssessmentQuestion, QuickAssessment;
import '../worksheet/worksheet_generator_screen.dart'
    show WorksheetGeneratorArgs;
import '../lessons/services/lesson_repository.dart';
import '../setup/data/classroom_setup_storage.dart';
import '../setup/models/classroom_setup.dart';
import '../setup/services/classroom_setup_repository.dart';
import '../setup/services/offline_resource_manager.dart';
import 'models/home_dashboard.dart';
import 'services/home_controller.dart';
import 'services/home_repositories.dart';
import 'services/home_repository.dart';
import 'widgets/home_cards.dart';
import 'widgets/home_panels.dart';

/// The teacher's dashboard.
///
/// Renders a [HomeController] and routes on taps; it holds no data access,
/// no mock values and no offline logic of its own. Every dynamic figure —
/// greeting, classroom, lesson, progress, offline state, unread count — is
/// assembled by [HomeRepository] and simply displayed here.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    this.repository,
    this.lessons,
    this.audio,
    this.connectivityService,
    this.clock,
    super.key,
  });

  final HomeRepository? repository;
  final LessonRepository? lessons;
  final LanguageAudioService? audio;
  final ConnectivityService? connectivityService;

  /// Injectable so the time-based greeting can be tested.
  final DateTime Function()? clock;

  /// Marks the first-load placeholders.
  static const Key skeletonKey = Key('home.skeleton');

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeController _controller;
  ConnectivityService? _ownedConnectivity;

  @override
  void initState() {
    super.initState();

    final ConnectivityService connectivity = widget.connectivityService ??
        (_ownedConnectivity = PlatformConnectivityService());
    // The catalogue is shared with the lesson library, so today's lesson and
    // the library's copy of it are the same record.
    final LessonRepository lessons = widget.lessons ??
        defaultLessonRepository(
          storage: PlatformSecureStorageService(),
          downloads: LocalLessonDownloadRepository(
            PlatformSecureStorageService(),
            seed: MockLessons.seedDownloaded(),
          ),
        );

    _controller = HomeController(
      repository: widget.repository ?? _defaultRepository(connectivity, lessons),
      lessons: lessons,
      audio: widget.audio ?? const BundledLanguageAudioService(),
      connectivity: connectivity,
      clock: widget.clock,
    );
  }

  /// Wires the local repository from the services the app already has.
  ///
  /// FUTURE: a `RemoteHomeRepository` reading the FastAPI dashboard endpoint
  /// slots in here, or in front of this one as a cache-then-network pair.
  HomeRepository _defaultRepository(
    ConnectivityService connectivity,
    LessonRepository lessons,
  ) {
    final AuthSessionStore session =
        AuthSessionStore(PlatformSecureStorageService());
    return LocalHomeRepository(
      session: session,
      classrooms: LocalClassroomSetupRepository(defaultClassroomSetupStorage()),
      lessons: lessons,
      progress: const DevelopmentProgressRepository(),
      notifications: const DevelopmentNotificationRepository(),
      resources: const BundledOfflineResourceManager(),
      connectivity: connectivity,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _ownedConnectivity?.dispose();
    super.dispose();
  }

  void _go(String route) => Navigator.of(context).pushNamed(route);

  /// Opens the flashcards with today's lesson, when there is one.
  ///
  /// The lesson is optional here: flashcards work on their own, and simply
  /// cannot add a card to a lesson without one.
  void _openFlashcards() {
    Navigator.of(context).pushNamed(
      AppRoutes.flashcards,
      arguments: FlashcardsArgs(
        lessonId: _controller.dashboard?.todayLesson?.id,
      ),
    );
  }

  /// Opens the worksheet generator for today's lesson.
  ///
  /// The lesson travels with the route: a generator opened with no lesson has
  /// nothing to align a worksheet to, and would only be able to say so.
  void _createWorksheet() {
    final Lesson? lesson = _controller.dashboard?.todayLesson;
    if (lesson == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a lesson first to make a worksheet for it.'),
        ),
      );
      return;
    }
    Navigator.of(context).pushNamed(
      AppRoutes.worksheet,
      arguments: WorksheetGeneratorArgs(lesson.id),
    );
  }

  /// Opens the offline assessment for today's lesson (Counting 1-10).
  void _openAssessment() {
    final Lesson? lesson = _controller.dashboard?.todayLesson;
    if (lesson == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a lesson first to open assessment for it.'),
        ),
      );
      return;
    }
    // Navigate to the lesson assessment screen for Counting 1-10
    Navigator.of(context).pushNamed(
      AppRoutes.lessonAssessment,
      arguments: LessonAssessmentArgs(
        lessonId: lesson.id,
        lessonTitle: lesson.title,
        assessment: const QuickAssessment(
          id: 'qa-c1-count-10',
          title: 'Quick Assessment',
          summary: 'Ask the child to show 3 objects.',
          questions: <AssessmentQuestion>[
            AssessmentQuestion(
              id: 'q1',
              prompt: 'Ask the child to show 3 objects.',
              successCriteria: 'Picks up exactly three, without recounting.',
              concept: 'Counting 1–10',
            ),
            AssessmentQuestion(
              id: 'q2',
              prompt: 'Ask the child to count these 7 stones aloud.',
              successCriteria: 'Says one number for each stone, up to seven.',
              concept: 'Number Sequence',
            ),
            AssessmentQuestion(
              id: 'q3',
              prompt: 'Ask the child how many there are, without recounting.',
              successCriteria: 'Answers with the last number counted.',
              concept: 'After, Before, Between',
            ),
          ],
        ),
        previous: null,
      ),
    );
  }

  Future<void> _startLesson() async {
    final Lesson? lesson = _controller.dashboard?.todayLesson;
    if (lesson != null && await _controller.canOpenLesson()) {
      if (!mounted) return;
      // The id travels with the route: lesson detail must resolve the same
      // lesson the dashboard is showing, not pick one of its own.
      Navigator.of(context).pushNamed(
        AppRoutes.lessonDetail,
        arguments: LessonDetailArgs(lesson.id),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(HomeController.lessonUnavailableMessage)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.homePage,
      // Home is the authenticated root: back must not walk back through
      // splash, onboarding or sign-in.
      body: PopScope(
        canPop: false,
        child: SafeArea(
          bottom: false,
          child: ListenableBuilder(
            listenable: _controller,
            builder: (BuildContext context, Widget? _) => _body(context),
          ),
        ),
      ),
      bottomNavigationBar:
          const AppBottomNavigation(current: AppDestination.home),
    );
  }

  Widget _body(BuildContext context) {
    final HomeDashboard? dashboard = _controller.dashboard;

    if (_controller.failed) return _errorState();
    if (dashboard == null) return const _DashboardSkeleton();

    return RefreshIndicator(
      onRefresh: _controller.refresh,
      color: AppColors.authNavy,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = constraints.maxWidth;
          final double contentWidth = width.clamp(0.0, 720.0);
          final double sidePad = ((width - contentWidth) / 2) + 16;

          return ListView(
            // Always scrollable so pull-to-refresh still works on a large
            // screen where the dashboard happens to fit without scrolling.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(sidePad, 10, sidePad, 26),
            children: <Widget>[
              HomeHeader(
                unreadCount: dashboard.unreadNotifications,
                onNotifications: () => _go(AppRoutes.notifications),
                onProfile: () => _go(AppRoutes.profile),
              ),
              const SizedBox(height: 20),
              Text(
                '${_controller.greeting} 👋',
                style: const TextStyle(
                  fontSize: 25,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: AppColors.brandNavy,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Let's make today's lesson easier.",
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.brandNavy.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 18),
              if (dashboard.needsClassroomSetup)
                _SetupRequired(onSetUp: () => _go(AppRoutes.setup))
              else
                ..._classroomSections(context, dashboard),
              const SizedBox(height: 18),
              const AiBanner(),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _classroomSections(BuildContext context, HomeDashboard d) {
    final ClassroomSetup classroom = d.classroom!;

    return <Widget>[
      ClassroomStatusCard(
        classroom: classroom,
        offlineState: d.offlineState,
      ),
      const SizedBox(height: 16),
      TodayLessonCard(
        lesson: d.todayLesson,
        targetLanguage: classroom.targetLanguage,
        listenState: _controller.listenState,
        onStart: _startLesson,
        onListen: _controller.toggleListen,
        onChooseLesson: () => _go(AppRoutes.lessons),
      ),
      if (_controller.message != null) ...<Widget>[
        const SizedBox(height: 10),
        _Notice(
          message: _controller.message!,
          onDismiss: _controller.dismissMessage,
        ),
      ],
      const SizedBox(height: 22),
      Row(
        children: <Widget>[
          const Expanded(
            child: Text(
              'Quick Actions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.brandNavy,
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'View all flashcards',
            child: ExcludeSemantics(
              child: TextButton(
                onPressed: () => _go(AppRoutes.flashcards),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brandNavy,
                  minimumSize: const Size(48, 44),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'View all',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 3),
                    Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      QuickActionsGrid(actions: _quickActions(classroom)),
      const SizedBox(height: 20),
      LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget progress = ProgressPanel(
            progress: d.progress,
            onViewReport: () => _go(AppRoutes.progress),
          );
          final Widget offline = OfflinePanel(
            state: d.offlineState,
            onManage: () => _go(AppRoutes.offline),
          );

          // Side by side only where both stay readable.
          if (constraints.maxWidth < 560) {
            return Column(
              children: <Widget>[
                progress,
                const SizedBox(height: 16),
                offline,
              ],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: progress),
                const SizedBox(width: 16),
                Expanded(child: offline),
              ],
            ),
          );
        },
      ),
    ];
  }

  /// The four shortcuts. The Translate subtitle names the classroom's own
  /// language pair rather than a fixed one.
  List<QuickAction> _quickActions(ClassroomSetup classroom) {
    return <QuickAction>[
      QuickAction(
        title: 'Assessment',
        subtitle: 'Quick assessment for today\'s lesson',
        icon: Icons.assignment_turned_in_outlined,
        tint: AppColors.setupLiteracy,
        onTap: _openAssessment,
      ),
      QuickAction(
        title: 'Translate',
        subtitle: '${classroom.teachingMedium.label} ↔ '
            '${classroom.targetLanguage.label}',
        icon: Icons.translate,
        tint: AppColors.setupLiteracy,
        onTap: () => _go(AppRoutes.translate),
      ),
      QuickAction(
        title: 'Create Worksheet',
        subtitle: 'Generate practice sheets',
        icon: Icons.description_outlined,
        tint: AppColors.primary,
        onTap: _createWorksheet,
      ),
      QuickAction(
        title: 'Flashcards',
        subtitle: 'Learn & reinforce',
        icon: Icons.style_outlined,
        tint: AppColors.brandOrange,
        onTap: _openFlashcards,
      ),
    ];
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.cloud_off,
              size: 38,
              color: AppColors.brandMuted,
            ),
            const SizedBox(height: 14),
            const Text(
              "Some dashboard information couldn't be loaded.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.brandNavy,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _controller.load,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.authNavy,
                minimumSize: const Size(160, 48),
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when Home is reached before the classroom has been configured.
class _SetupRequired extends StatelessWidget {
  const _SetupRequired({required this.onSetUp});

  final VoidCallback onSetUp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.school_outlined, size: 32, color: AppColors.warning),
          const SizedBox(height: 12),
          const Text(
            'Complete your classroom setup',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.brandNavy,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Tell us your school, class and teaching languages, and your '
            'dashboard will fill in.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.brandNavy.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: onSetUp,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.authNavy,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            child: const Text(
              'Set Up Classroom',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lightweight placeholders while the first read completes.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget block(double height) => Container(
          height: height,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.authFieldBorder.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
          ),
        );

    return Semantics(
      label: 'Loading your dashboard',
      child: ListView(
        key: HomeScreen.skeletonKey,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 26),
        children: <Widget>[
          block(52),
          block(34),
          block(58),
          block(190),
          block(120),
          block(160),
        ],
      ),
    );
  }
}

/// Transient note under the hero card.
class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 11, 6, 11),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.info_outline, size: 17, color: AppColors.warning),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: AppColors.brandNavy.withValues(alpha: 0.85),
                ),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 17),
              tooltip: 'Dismiss',
              color: AppColors.brandNavy.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}
