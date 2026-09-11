import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/constants/app_assets.dart';
import '../../core/constants/app_colors.dart';
import '../../services/audio/audio_resource_store.dart';
import '../../services/audio/lesson_audio_service.dart';
import '../../services/audio/text_to_speech_service.dart';
import '../../services/connectivity/connectivity_service.dart';
import '../../services/storage/secure_storage_service.dart';
import '../assessment/assessment_screen.dart' show AssessmentArgs;
import '../flashcards/flashcards_screen.dart' show FlashcardsArgs;
import '../lessons/lesson_navigation.dart';
import '../worksheet/worksheet_generator_screen.dart'
    show WorksheetGeneratorArgs;
import '../lessons/services/ai_content_service.dart';
import '../lessons/services/assessment_repository.dart';
import '../lessons/services/lesson_content_repository.dart';
import '../lessons/services/lesson_repository.dart';
import '../progress/services/learning_progress_repository.dart';
import 'models/classroom_session.dart';
import 'services/classroom_insight_service.dart';
import 'services/classroom_session_repository.dart';
import 'services/conversation_result_controller.dart';
import 'widgets/conversation_result_widgets.dart';

/// What the result screen is opened with.
///
/// Only the id travels. The session itself is read back from the repository, so
/// there is one copy of it and the live classroom and this screen cannot end up
/// describing the same lesson differently.
class ConversationResultArgs {
  const ConversationResultArgs(this.sessionId);

  final String sessionId;

  static String? sessionIdFrom(Object? arguments) => switch (arguments) {
        ConversationResultArgs(:final String sessionId) => sessionId,
        final String id when id.isNotEmpty => id,
        _ => null,
      };
}

/// What a live classroom session came to.
///
/// Every figure here is read from the saved [ClassroomSession] or counted from
/// its turns. Nothing is generated for the sake of the layout: a session with
/// no measured latency shows a dash, a session with no assessment says nobody
/// has checked yet, and a session where no child spoke says engagement is
/// unknown rather than guessing at it.
class ConversationResultScreen extends StatefulWidget {
  const ConversationResultScreen({
    this.sessionId,
    this.controller,
    this.sessions,
    this.insights,
    this.lessons,
    this.content,
    this.progress,
    this.assessments,
    this.audio,
    this.connectivity,
    super.key,
  });

  static const Key scrollKey = Key('result-scroll');
  static const Key skeletonKey = Key('result-skeleton');
  static const Key backKey = Key('result-back');
  static const Key moreKey = Key('result-more');
  static const Key statusKey = Key('result-status');
  static const Key continueLessonKey = Key('result-continue-lesson');
  static const Key startAssessmentKey = Key('result-start-assessment');
  static const Key createWorksheetKey = Key('result-create-worksheet');
  static const Key practiceFlashcardsKey =
      Key('result-practice-flashcards');
  static const Key saveSessionKey = Key('result-save-session');
  static const Key detailedReportKey = Key('result-detailed-report');

  static Key playKey(int index) => Key('result-play-$index');

  final String? sessionId;

  /// Supplied whole by tests; built from the parts below otherwise.
  final ConversationResultController? controller;

  final ClassroomSessionRepository? sessions;
  final ClassroomInsightService? insights;
  final LessonRepository? lessons;
  final LessonContentRepository? content;
  final LessonProgressRepository? progress;
  final AssessmentRepository? assessments;
  final LessonAudioService? audio;
  final ConnectivityService? connectivity;

  @override
  State<ConversationResultScreen> createState() =>
      _ConversationResultScreenState();
}

class _ConversationResultScreenState extends State<ConversationResultScreen> {
  ConversationResultController? _controller;

  /// Only what this screen created is disposed by it.
  ConnectivityService? _ownedConnectivity;
  LessonAudioService? _ownedAudio;

  bool _built = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_built) return;
    _built = true;

    final ConversationResultController? given = widget.controller;
    if (given != null) {
      _controller = given;
      return;
    }

    final Object? routeArgs = ModalRoute.of(context)?.settings.arguments;
    final String? sessionId = widget.sessionId ??
        ConversationResultArgs.sessionIdFrom(routeArgs);
    if (sessionId != null) _build(sessionId);
  }

  void _build(String sessionId) {
    final SecureStorageService storage = PlatformSecureStorageService();
    final ConnectivityService connectivity = widget.connectivity ??
        (_ownedConnectivity = PlatformConnectivityService());

    final LessonAudioService audio = widget.audio ??
        (_ownedAudio = TtsLessonAudioService(
          tts: PlatformTextToSpeechService(),
          store: LocalAudioResourceStore(storage),
          connectivity: connectivity,
        ));

    setState(() {
      _controller = ConversationResultController(
        sessionId: sessionId,
        sessions:
            widget.sessions ?? LocalClassroomSessionRepository(storage),
        insights: widget.insights ?? LocalRuleBasedInsightService(storage),
        lessons: widget.lessons ??
            defaultLessonRepository(
              storage: storage,
              downloads: LocalLessonDownloadRepository(storage),
            ),
        content: widget.content ??
            LocalLessonContentRepository(
              ai: DevelopmentAiContentService(),
              storage: storage,
            ),
        progress: widget.progress ?? LocalLessonProgressRepository(storage),
        assessments: widget.assessments ?? LocalAssessmentRepository(storage),
        audio: audio,
        connectivity: connectivity,
        recorder: ProgressRecorder(LocalLearningProgressRepository(storage)),
      );
    });
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller?.dispose();
    unawaited(_ownedAudio?.dispose());
    unawaited(_ownedConnectivity?.dispose());
    super.dispose();
  }

  // --- Actions -------------------------------------------------------------

  Future<void> _continueLesson(ConversationResultController c) async {
    final ClassroomSession? session = c.session;
    if (session == null) return;
    await c.stopAudio();
    if (!mounted) return;

    // Lesson detail resolves the lesson and reads its saved progress, so the
    // teacher lands where they left off rather than at the start.
    await Navigator.of(context).pushNamed(
      AppRoutes.lessonDetail,
      arguments: LessonDetailArgs(session.lessonId),
    );
  }

  /// Opens the multiple-choice assessment for the lesson this session taught.
  ///
  /// Three different things in this app are called an assessment, and they lead
  /// to three different screens:
  ///
  /// * this button opens the on-screen assessment the app marks;
  /// * Create Worksheet, below, prints practice to do on paper;
  /// * the lesson's own Quick Assessment card is the check a teacher marks by
  ///   watching a child, and its result still feeds the insights above.
  Future<void> _startAssessment(ConversationResultController c) async {
    final ClassroomSession? session = c.session;
    if (session == null) return;

    await c.stopAudio();
    if (!mounted) return;

    await Navigator.of(context).pushNamed(
      AppRoutes.assessment,
      arguments: AssessmentArgs(session.lessonId),
    );
  }

  /// Opens the flashcards for the lesson this session taught.
  ///
  /// The cards are reinforcement here, but the same screen is reachable from
  /// the lesson before it is taught: nothing about flashcards is gated on
  /// having finished anything.
  Future<void> _practiseFlashcards(ConversationResultController c) async {
    final ClassroomSession? session = c.session;
    if (session == null) return;

    await c.stopAudio();
    if (!mounted) return;

    await Navigator.of(context).pushNamed(
      AppRoutes.flashcards,
      arguments: FlashcardsArgs(lessonId: session.lessonId),
    );
  }

  /// Opens the worksheet generator for the lesson this session taught.
  Future<void> _createWorksheet(ConversationResultController c) async {
    final ClassroomSession? session = c.session;
    if (session == null) return;

    await c.stopAudio();
    if (!mounted) return;

    await Navigator.of(context).pushNamed(
      AppRoutes.worksheet,
      arguments: WorksheetGeneratorArgs(session.lessonId),
    );
  }

  Future<void> _openReport(ConversationResultController c) async {
    final ClassroomSession? session = c.session;
    if (session == null) return;
    await Navigator.of(context).pushNamed(
      AppRoutes.sessionReport,
      arguments: ConversationResultArgs(session.sessionId),
    );
  }

  Future<void> _openMenu(ConversationResultController c) async {
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
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outline,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            // Only what this build can really do.
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('View detailed report'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openReport(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(
                c.saveState == SaveState.saved
                    ? 'Session saved on this device'
                    : 'Save session',
              ),
              enabled: c.saveState != SaveState.saved,
              onTap: () {
                Navigator.of(sheetContext).pop();
                c.saveSession();
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Reload session'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                c.load();
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
    final ConversationResultController? c = _controller;

    if (c == null) {
      return const _ResultShell(
        child: ResultMessage(
          icon: Icons.summarize_outlined,
          title: 'No session to summarise.',
          body: 'Open this from a classroom session so it knows which one to '
              'show.',
        ),
      );
    }

    return AnimatedBuilder(
      animation: c,
      builder: (BuildContext context, _) {
        switch (c.loadState) {
          case ResultLoadState.loading:
            return const _ResultShell(child: ResultSkeleton());
          case ResultLoadState.error:
            return _ResultShell(
              child: ResultMessage(
                icon: Icons.error_outline,
                title: "Couldn't load this classroom session.",
                body: 'It may have been removed from this device.',
                actionLabel: 'Try again',
                onAction: c.load,
              ),
            );
          case ResultLoadState.loaded:
            return _loaded(context, c);
        }
      },
    );
  }

  Widget _loaded(BuildContext context, ConversationResultController c) {
    final ClassroomSession session = c.session!;

    return Scaffold(
      backgroundColor: AppColors.homePage,
      body: Column(
        children: <Widget>[
          ResultHeader(
            session: session,
            offline: c.isOffline,
            onBack: () => Navigator.of(context).maybePop(),
            onMore: () => _openMenu(c),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double width = constraints.maxWidth;
                final double contentWidth = width.clamp(0.0, 760.0);
                final double side = ((width - contentWidth) / 2) + 16;

                return ListView(
                  key: ConversationResultScreen.scrollKey,
                  padding: EdgeInsets.fromLTRB(side, 0, side, 20),
                  children: <Widget>[
                    // Laid out normally rather than translated up over the
                    // header: a Transform does not change layout, so the card's
                    // top was being clipped by the scroll view's own edge.
                    const SizedBox(height: 14),
                    SessionMetricsCard(session: session),
                    const SizedBox(height: 18),
                    _conversation(c),
                    const SizedBox(height: 18),
                    InsightsCard(
                      insights: c.insights,
                      onReport: () => _openReport(c),
                    ),
                    const SizedBox(height: 18),
                    // The note sits with the buttons rather than at the top of
                    // the page: a confirmation for something the teacher just
                    // tapped belongs where they are looking, and putting it
                    // above would push the buttons off the screen.
                    if (c.message != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ResultNotice(
                          message: c.message!,
                          onDismiss: c.dismissMessage,
                        ),
                      ),
                    _actions(c),
                  ],
                );
              },
            ),
          ),
          const ResultFooter(),
        ],
      ),
    );
  }

  Widget _conversation(ConversationResultController c) {
    final ClassroomSession session = c.session!;
    final List<ResultTimelineEntry> entries = c.timeline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
            children: <Widget>[
              const Icon(
                Icons.forum_outlined,
                size: 22,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Conversation Summary',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                ),
              ),
              // Counted from the session's own turns.
              Text(
                '${session.totalTurns} '
                '${session.totalTurns == 1 ? 'interaction' : 'interactions'}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.setupNumeracy,
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          const EmptyConversation()
        else
          for (int i = 0; i < entries.length; i++)
            TimelineRow(
              entry: entries[i],
              playKey: ConversationResultScreen.playKey(i),
              isLast: i == entries.length - 1,
              onPlay: () => c.playEntry(entries[i]),
            ),
      ],
    );
  }

  Widget _actions(ConversationResultController c) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Two across on a normal phone; stacked below, where two buttons with
        // icons cannot share a line without their labels shrinking to nothing.
        final bool inGrid = constraints.maxWidth >= 380;

        final Widget continueLesson = ResultAction(
          key: ConversationResultScreen.continueLessonKey,
          icon: Icons.play_arrow,
          label: 'Continue Lesson',
          background: AppColors.authNavy,
          foreground: Colors.white,
          onPressed: () => _continueLesson(c),
        );

        final Widget assessment = ResultAction(
          key: ConversationResultScreen.startAssessmentKey,
          icon: Icons.assignment_turned_in_outlined,
          label: 'Start Assessment',
          background: AppColors.setupLiteracy,
          foreground: Colors.white,
          onPressed: () => _startAssessment(c),
        );

        final Widget flashcards = ResultAction(
          key: ConversationResultScreen.practiceFlashcardsKey,
          icon: Icons.style_outlined,
          label: 'Practice Flashcards',
          background: Colors.white,
          foreground: AppColors.brandNavy,
          outlined: true,
          onPressed: () => _practiseFlashcards(c),
        );

        final Widget worksheet = ResultAction(
          key: ConversationResultScreen.createWorksheetKey,
          icon: Icons.description_outlined,
          label: 'Create Worksheet',
          background: Colors.white,
          foreground: AppColors.brandNavy,
          outlined: true,
          onPressed: () => _createWorksheet(c),
        );

        final Widget save = ResultAction(
          key: ConversationResultScreen.saveSessionKey,
          icon: switch (c.saveState) {
            SaveState.saved => Icons.download_done,
            SaveState.failed => Icons.error_outline,
            _ => Icons.download_outlined,
          },
          label: switch (c.saveState) {
            SaveState.saving => 'Saving…',
            SaveState.saved => 'Session Saved',
            SaveState.failed => 'Try Again',
            SaveState.notSaved => 'Save Session',
          },
          background: Colors.white,
          foreground: AppColors.brandNavy,
          outlined: true,
          busy: c.saveState == SaveState.saving,
          // A saved session is not saved twice.
          onPressed: c.saveState == SaveState.saved ||
                  c.saveState == SaveState.saving
              ? null
              : c.saveSession,
        );

        if (!inGrid) {
          return Column(
            children: <Widget>[
              continueLesson,
              const SizedBox(height: 10),
              assessment,
              const SizedBox(height: 10),
              worksheet,
              const SizedBox(height: 10),
              flashcards,
              const SizedBox(height: 10),
              save,
            ],
          );
        }

        return Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: continueLesson),
                const SizedBox(width: 10),
                Expanded(child: assessment),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(child: worksheet),
                const SizedBox(width: 10),
                Expanded(child: flashcards),
              ],
            ),
            const SizedBox(height: 10),
            save,
          ],
        );
      },
    );
  }
}

/// The plain scaffold used by the loading, error and no-session states.
class _ResultShell extends StatelessWidget {
  const _ResultShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.homePage,
      appBar: AppBar(
        backgroundColor: AppColors.authNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: <Widget>[
            Image.asset(
              AppAssets.loginBrandMark,
              height: 28,
              excludeFromSemantics: true,
            ),
            const SizedBox(width: 8),
            Semantics(
              label: 'GyanSetu AI',
              child: const ExcludeSemantics(
                child: Text(
                  'GyanSetu AI',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(child: child),
    );
  }
}
