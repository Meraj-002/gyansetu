import 'package:flutter/material.dart';

import '../core/widgets/route_not_found_screen.dart';
import '../features/assessment/assessment_result_screen.dart';
import '../features/assessment/assessment_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/classroom/classroom_screen.dart';
import '../features/classroom/conversation_result_screen.dart';
import '../features/classroom/live_classroom_screen.dart';
import '../features/classroom/session_report_screen.dart';
import '../features/flashcards/flashcards_screen.dart';
import '../features/home/home_screen.dart';
import '../features/lessons/lesson_activity_screen.dart';
import '../features/lessons/lesson_assessment_screen.dart';
import '../features/lessons/lesson_detail_screen.dart';
import '../features/lessons/lesson_library_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/offline/offline_center_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/progress/progress_screen.dart';
import '../features/progress/student_progress_screen.dart';
import '../features/resources/resources_screen.dart';
import '../features/setup/setup_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/sync/sync_center_screen.dart';
import '../features/translate/translate_screen.dart';
import '../features/worksheet/worksheet_generator_screen.dart';
import '../features/worksheet/worksheet_preview_screen.dart';
import '../services/service_registry.dart';

/// Every route name in the app.
///
/// Navigate with these constants — never with a raw string literal — so that a
/// renamed route is a compile error instead of a runtime "page not found".
abstract final class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String auth = '/auth';
  static const String setup = '/setup';
  static const String home = '/home';
  static const String lessons = '/lessons';
  static const String classroom = '/classroom';
  /// The worksheet generator, opened from a lesson with its id.
  static const String worksheet = '/worksheet';

  /// The generated worksheet, opened with its id.
  static const String worksheetPreview = '/worksheet/preview';
  static const String flashcards = '/flashcards';
  /// The multiple-choice assessment, opened from a lesson with its id.
  ///
  /// Distinct from [lessonAssessment], which is the teacher-marked quick
  /// check on the lesson's own plan.
  static const String assessment = '/assessment';

  /// The question-by-question breakdown of a finished assessment.
  static const String assessmentResult = '/assessment/result';
  /// Learning Insights: what this classroom's records add up to.
  static const String progress = '/progress';

  /// The children behind on one concept, opened from Learning Insights.
  static const String students = '/progress/students';
  static const String offline = '/offline';
  static const String sync = '/sync';
  static const String profile = '/profile';

  /// Destinations Home links out to. Placeholder screens for now; the
  /// routes exist so Home never hard-codes navigation of its own.
  static const String notifications = '/notifications';
  static const String lessonDetail = '/lessons/detail';

  /// Opened from lesson detail with typed arguments; see `lesson_navigation`.
  static const String lessonActivity = '/lessons/activity';
  static const String lessonAssessment = '/lessons/assessment';

  /// The live teaching session. Distinct from [classroom], which is the app's
  /// classroom section rather than a running session.
  static const String liveClassroom = '/classroom/live';

  /// Where a finished live session lands. Reached with `pushReplacement`, so a
  /// closed session cannot be navigated back into.
  static const String conversationResult = '/classroom/result';

  /// The full turn-by-turn report for one session.
  static const String sessionReport = '/classroom/report';
  static const String translate = '/translate';
  static const String resources = '/resources';
}

/// Centralised route table.
///
/// `MaterialApp.onGenerateRoute` delegates here, so navigation stays declared in
/// one file. Screens never construct each other's routes directly.
abstract final class AppRouter {
  /// Route name to screen builder. Adding a screen means adding one line here
  /// plus one constant in [AppRoutes].
  static const Map<String, WidgetBuilder> _builders = <String, WidgetBuilder>{
    AppRoutes.splash: _splash,
    AppRoutes.onboarding: _onboarding,
    AppRoutes.auth: _auth,
    AppRoutes.setup: _setup,
    AppRoutes.home: _home,
    AppRoutes.lessons: _lessons,
    AppRoutes.classroom: _classroom,
    AppRoutes.worksheet: _worksheet,
    AppRoutes.worksheetPreview: _worksheetPreview,
    AppRoutes.flashcards: _flashcards,
    AppRoutes.assessment: _assessment,
    AppRoutes.assessmentResult: _assessmentResult,
    AppRoutes.progress: _progress,
    AppRoutes.students: _students,
    AppRoutes.offline: _offline,
    AppRoutes.sync: _sync,
    AppRoutes.profile: _profile,
    AppRoutes.notifications: _notifications,
    AppRoutes.lessonDetail: _lessonDetail,
    AppRoutes.lessonActivity: _lessonActivity,
    AppRoutes.lessonAssessment: _lessonAssessment,
    AppRoutes.liveClassroom: _liveClassroom,
    AppRoutes.conversationResult: _conversationResult,
    AppRoutes.sessionReport: _sessionReport,
    AppRoutes.translate: _translate,
    AppRoutes.resources: _resources,
  };

  /// Route names that currently have a registered screen.
  static Iterable<String> get registeredRoutes => _builders.keys;

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: _builderFor(settings),
    );
  }

  /// Replaces the current screen with [routeName], cross-fading between them.
  ///
  /// Uses `pushReplacement`, so the screen being left is dropped from the
  /// stack and Android's back gesture cannot return to it. This is how the
  /// splash becomes unreachable once onboarding is showing.
  static Future<T?> replaceWithFade<T extends Object?>(
    BuildContext context,
    String routeName,
  ) {
    return Navigator.of(context).pushReplacement<T, void>(
      fadeRoute<T>(RouteSettings(name: routeName)),
    );
  }

  /// A route that cross-fades instead of using the platform's push animation.
  static PageRoute<T> fadeRoute<T extends Object?>(RouteSettings settings) {
    final WidgetBuilder builder = _builderFor(settings);

    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: fadeTransitionDuration,
      reverseTransitionDuration: fadeTransitionDuration,
      pageBuilder: (BuildContext context, _, _) => builder(context),
      transitionsBuilder: (_, Animation<double> animation, _, Widget child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  static const Duration fadeTransitionDuration = Duration(milliseconds: 450);

  /// Resolves a route name to its screen, falling back to [RouteNotFoundScreen]
  /// so that both [onGenerateRoute] and [fadeRoute] handle typos identically.
  static WidgetBuilder _builderFor(RouteSettings settings) {
    final WidgetBuilder? builder = _builders[settings.name];
    if (builder != null) return builder;

    return (BuildContext _) => RouteNotFoundScreen(routeName: settings.name);
  }

  // Tear-offs kept as top-level functions so that [_builders] stays `const`.
  static Widget _splash(BuildContext _) => const SplashScreen();
  static Widget _onboarding(BuildContext _) => const OnboardingScreen();
  static Widget _auth(BuildContext _) => const LoginScreen();
  static Widget _setup(BuildContext _) => const SetupScreen();
  static Widget _home(BuildContext _) => const HomeScreen();
  static Widget _lessons(BuildContext _) => const LessonLibraryScreen();
  static Widget _classroom(BuildContext _) => const ClassroomScreen();
  static Widget _worksheet(BuildContext _) =>
      const WorksheetGeneratorScreen();
  static Widget _worksheetPreview(BuildContext _) =>
      const WorksheetPreviewScreen();
  static Widget _flashcards(BuildContext _) => const FlashcardsScreen();
  static Widget _assessment(BuildContext _) => const AssessmentScreen();
  static Widget _assessmentResult(BuildContext _) =>
      const AssessmentResultScreen();
  static Widget _progress(BuildContext _) => const ProgressScreen();
  static Widget _students(BuildContext _) => const StudentProgressScreen();
  static Widget _offline(BuildContext context) => OfflineCenterScreen(
        downloadManager: ServiceRegistry.instance.downloadManager,
        resourceCatalogue: ServiceRegistry.instance.resourceCatalogue,
      );
  static Widget _sync(BuildContext _) => const SyncCenterScreen();
  static Widget _profile(BuildContext _) => ProfileScreen(
        identity: ServiceRegistry.instance.identity,
        authentication: ServiceRegistry.instance.authentication,
        offline: ServiceRegistry.instance.offline,
      );
  static Widget _notifications(BuildContext _) => const NotificationsScreen();
  static Widget _lessonDetail(BuildContext _) => const LessonDetailScreen();
  static Widget _lessonActivity(BuildContext _) => const LessonActivityScreen();
  static Widget _lessonAssessment(BuildContext _) =>
      const LessonAssessmentScreen();
  static Widget _liveClassroom(BuildContext _) => const LiveClassroomScreen();
  static Widget _conversationResult(BuildContext _) =>
      const ConversationResultScreen();
  static Widget _sessionReport(BuildContext _) => const SessionReportScreen();
  static Widget _translate(BuildContext _) => const TranslateScreen();
  static Widget _resources(BuildContext _) => const ResourcesScreen();
}
