import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/constants/app_colors.dart';
import '../../models/assessment_question.dart';
import '../../models/assessment_result.dart';
import '../../services/audio/audio_resource_store.dart';
import '../../services/audio/lesson_audio_service.dart';
import '../../services/audio/text_to_speech_service.dart';
import '../../services/connectivity/connectivity_service.dart';
import '../../services/storage/secure_storage_service.dart';
import '../auth/services/auth_session_store.dart';
import '../lessons/lesson_navigation.dart';
import '../lessons/services/lesson_repository.dart';
import '../progress/services/learning_progress_repository.dart';
import '../setup/data/classroom_setup_storage.dart';
import '../setup/services/classroom_setup_repository.dart';
import 'assessment_result_screen.dart';
import 'services/assessment_controller.dart';
import 'services/assessment_recommendation_service.dart';
import 'services/quiz_repository.dart';
import 'widgets/assessment_widgets.dart';

/// What the assessment screen is opened with.
///
/// A typed argument rather than a loose map, so a caller that forgets the
/// lesson id fails to compile. A bare `String` id is still accepted.
class AssessmentArgs {
  const AssessmentArgs(this.lessonId);

  final String lessonId;

  static String? lessonIdFrom(Object? arguments) => switch (arguments) {
        AssessmentArgs(:final String lessonId) => lessonId,
        final String id when id.isNotEmpty => id,
        _ => null,
      };
}

/// A short multiple-choice check on what a class has learned.
///
/// Distinct from the lesson's *quick assessment*, which the teacher marks by
/// watching a child. This one is answered on screen and marked by the app.
///
/// Everything shown here is counted from answers that were actually given. The
/// summary at the bottom does not exist until the last question has been
/// answered, the score is the number of correct answers rather than a figure
/// chosen to look encouraging, and the practice suggestion is a rule comparing
/// counts — the screen says so, and never calls it AI.
class AssessmentScreen extends StatefulWidget {
  const AssessmentScreen({
    this.lessonId,
    this.controller,
    this.quizzes,
    this.classrooms,
    this.audio,
    this.connectivity,
    this.lessons,
    this.recommendations,
    this.teacherId,
    super.key,
  });

  static const Key scrollKey = Key('assessment-scroll');
  static const Key skeletonKey = Key('assessment-skeleton');
  static const Key backKey = Key('assessment-back');
  static const Key moreKey = Key('assessment-more');
  static const Key statusKey = Key('assessment-status');
  static const Key progressKey = Key('assessment-progress');
  static const Key questionKey = Key('assessment-question');
  static const Key listenKey = Key('assessment-listen');
  static const Key nextKey = Key('assessment-next');
  static const Key previousKey = Key('assessment-previous');
  static const Key retryKey = Key('assessment-retry');
  static const Key restartKey = Key('assessment-restart');
  static const Key completionKey = Key('assessment-completion');
  static const Key viewDetailsKey = Key('assessment-view-details');
  static const Key continueLearningKey = Key('assessment-continue-learning');
  static const Key browseLessonsKey = Key('assessment-browse-lessons');

  static Key optionKey(String optionId) => Key('assessment-option-$optionId');

  final String? lessonId;

  /// Supplied whole by tests; built from the parts below otherwise.
  final AssessmentController? controller;

  final QuizRepository? quizzes;
  final ClassroomSetupRepository? classrooms;
  final LessonAudioService? audio;
  final ConnectivityService? connectivity;
  final LessonRepository? lessons;
  final AssessmentRecommendationService? recommendations;
  final String? teacherId;

  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen> {
  AssessmentController? _controller;
  ConnectivityService? _ownedConnectivity;
  LessonAudioService? _ownedAudio;

  /// Null when the screen was opened without a lesson, which is a state of its
  /// own rather than an error.
  String? _lessonId;

  final ScrollController _scroll = ScrollController();

  bool _built = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_built) return;
    _built = true;

    final AssessmentController? given = widget.controller;
    if (given != null) {
      _controller = given;
      _lessonId = given.lessonId;
      return;
    }

    final Object? routeArgs = ModalRoute.of(context)?.settings.arguments;
    final String? lessonId =
        widget.lessonId ?? AssessmentArgs.lessonIdFrom(routeArgs);
    if (lessonId == null) return;

    _lessonId = lessonId;
    unawaited(_build(lessonId));
  }

  Future<void> _build(String lessonId) async {
    final SecureStorageService storage = PlatformSecureStorageService();
    final String teacherId = widget.teacherId ??
        (await AuthSessionStore(storage).account())?.id ??
        'local-teacher';
    if (!mounted) return;

    final ConnectivityService connectivity = widget.connectivity ??
        (_ownedConnectivity = PlatformConnectivityService());

    // The same audio layer the lesson, the classroom and the flashcards use,
    // so a language with no voice is reported the same way everywhere.
    final LessonAudioService audio = widget.audio ??
        (_ownedAudio = TtsLessonAudioService(
          tts: PlatformTextToSpeechService(),
          store: LocalAudioResourceStore(storage),
          connectivity: connectivity,
        ));

    final AssessmentController controller = AssessmentController(
      quizzes: widget.quizzes ?? LocalQuizRepository(storage: storage),
      classrooms: widget.classrooms ??
          LocalClassroomSetupRepository(defaultClassroomSetupStorage()),
      audio: audio,
      connectivity: connectivity,
      teacherId: teacherId,
      lessonId: lessonId,
      lessons: widget.lessons ??
          defaultLessonRepository(
            storage: storage,
            downloads: LocalLessonDownloadRepository(storage),
          ),
      recommendations: widget.recommendations,
      recorder: ProgressRecorder(LocalLearningProgressRepository(storage)),
    );

    setState(() => _controller = controller);
  }

  @override
  void dispose() {
    _scroll.dispose();
    if (widget.controller == null) _controller?.dispose();
    unawaited(_ownedAudio?.dispose());
    unawaited(_ownedConnectivity?.dispose());
    super.dispose();
  }

  // --- Actions -------------------------------------------------------------

  Future<void> _openDetails(AssessmentController c) async {
    final QuizResult? result = c.result;
    if (result == null) return;
    await c.stopAudio();
    if (!mounted) return;

    await Navigator.of(context).pushNamed(
      AppRoutes.assessmentResult,
      arguments: AssessmentResultArgs(
        result: result,
        questions: c.questions,
        suggestion: c.suggestion,
        lessonTitle: c.lesson?.title,
      ),
    );
  }

  Future<void> _continueLearning(AssessmentController c) async {
    await c.stopAudio();
    if (!mounted) return;

    // Replaces this screen rather than pushing over it: a finished assessment
    // is not somewhere the back gesture should return to.
    await Navigator.of(context).pushReplacementNamed(
      AppRoutes.lessonDetail,
      arguments: LessonDetailArgs(c.lessonId),
    );
  }

  Future<void> _openMenu(AssessmentController c) async {
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
            ListTile(
              key: AssessmentScreen.restartKey,
              leading: const Icon(Icons.restart_alt),
              title: const Text('Start this assessment again'),
              subtitle: const Text('Clears every answer given so far'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmRestart(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('How this is marked'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showMarkingInfo(c);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRestart(AssessmentController c) async {
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Start again?'),
        content: const Text(
          'Every answer given so far is cleared and the assessment starts at '
          'the first question.',
          style: TextStyle(height: 1.45),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.authNavy),
            child: const Text('Start again'),
          ),
        ],
      ),
    );
    if (go == true) await c.restart();
  }

  void _showMarkingInfo(AssessmentController c) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('How this is marked'),
        content: Text(
          'The questions, the pictures and the marking are all on this phone. '
          'Nothing is sent anywhere and nothing is fetched, so the assessment '
          'runs with no connection.\n\n'
          'The score is the number of answers that matched the correct option. '
          'A concept counts as understood only when every question testing it '
          'was answered correctly.\n\n'
          'The practice suggestion at the end is chosen by a rule comparing '
          'those counts. It is not written by a model and it has not seen the '
          "child's work.\n\n"
          'Reading a question aloud uses the phone’s own speech engine. No '
          '${c.targetLanguage.label} wording of these questions has been '
          'written and checked yet, so they are read in '
          '${c.teachingMedium.label}.',
          style: const TextStyle(fontSize: 14, height: 1.45),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_lessonId == null) return _noLesson(context);

    final AssessmentController? c = _controller;
    if (c == null) return const _Shell(child: _Skeleton());

    return AnimatedBuilder(
      animation: c,
      builder: (BuildContext context, _) {
        switch (c.stage) {
          case AssessmentStage.loading:
            return const _Shell(child: _Skeleton());
          case AssessmentStage.error:
            return _Shell(
              child: _Message(
                icon: Icons.error_outline,
                title: "Couldn't load this assessment.",
                body: 'The questions are stored on this phone, so this is '
                    'usually worth another try.',
                actionKey: AssessmentScreen.retryKey,
                actionLabel: 'Retry',
                onAction: c.load,
                secondaryLabel: 'Back',
                onSecondary: () => Navigator.of(context).maybePop(),
              ),
            );
          case AssessmentStage.noQuestions:
            return _Shell(
              child: _Message(
                icon: Icons.assignment_outlined,
                title: 'No assessment for this lesson yet.',
                body: 'Questions have only been written for some lessons. '
                    'Nothing is generated here, so this lesson simply has '
                    'none.',
                secondaryLabel: 'Back',
                onSecondary: () => Navigator.of(context).maybePop(),
              ),
            );
          case AssessmentStage.inProgress:
          case AssessmentStage.completed:
            return _ready(context, c);
        }
      },
    );
  }

  Widget _noLesson(BuildContext context) {
    return _Shell(
      child: _Message(
        icon: Icons.menu_book_outlined,
        title: 'Open an assessment from a lesson.',
        body: 'An assessment belongs to a lesson, so it is started from a '
            'lesson or from a finished classroom session.',
        actionKey: AssessmentScreen.browseLessonsKey,
        actionLabel: 'Browse lessons',
        onAction: () => Navigator.of(context).pushNamed(AppRoutes.lessons),
        secondaryLabel: 'Back',
        onSecondary: () => Navigator.of(context).maybePop(),
      ),
    );
  }

  Widget _ready(BuildContext context, AssessmentController c) {
    return Scaffold(
      backgroundColor: AppColors.homePage,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            AssessmentHeader(
              status: 'Offline Assessment',
              statusKey: AssessmentScreen.statusKey,
              backKey: AssessmentScreen.backKey,
              moreKey: AssessmentScreen.moreKey,
              onBack: () => Navigator.of(context).maybePop(),
              onMore: () => _openMenu(c),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double width = constraints.maxWidth;
                  final double contentWidth = width.clamp(0.0, 720.0);
                  final double side = ((width - contentWidth) / 2) + 16;

                  return ListView(
                    key: AssessmentScreen.scrollKey,
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(side, 2, side, 26),
                    children: <Widget>[
                      _title(c),
                      const SizedBox(height: 14),
                      QuizProgressBar(
                        key: AssessmentScreen.progressKey,
                        label: c.progressLabel,
                        progress: c.progress,
                        percent: c.percentComplete,
                      ),
                      const SizedBox(height: 16),
                      _questionCard(c, width),
                      if (c.message != null) ...<Widget>[
                        const SizedBox(height: 14),
                        AssessmentNotice(
                          message: c.message!,
                          onDismiss: c.dismissMessage,
                        ),
                      ],
                      // The summary does not exist until every question has
                      // been answered. There is no partial score to show.
                      if (c.stage == AssessmentStage.completed &&
                          c.result != null) ...<Widget>[
                        const SizedBox(height: 20),
                        _completion(c, c.result!, width),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _title(AssessmentController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'Quick Assessment',
            maxLines: 1,
            style: TextStyle(
              fontSize: 30,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              color: AppColors.brandNavy,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          c.subtitle,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.setupNumeracy,
          ),
        ),
      ],
    );
  }

  // --- The question --------------------------------------------------------

  Widget _questionCard(AssessmentController c, double width) {
    final QuizQuestion? question = c.current;
    if (question == null) return const SizedBox.shrink();

    // Below this the listen button cannot sit beside the prompt without the
    // prompt wrapping to one word a line.
    final bool listenBeside = width >= 520;

    final Widget listen = _listenButton(c);

    return Container(
      key: AssessmentScreen.questionKey,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 18),
      decoration: BoxDecoration(
        color: AppColors.setupNumeracyTint,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.setupNumeracy,
                ),
                child: Text(
                  '${c.index + 1}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      question.prompt,
                      style: const TextStyle(
                        fontSize: 18,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandNavy,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      question.promptHindi,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: AppColors.brandBody,
                      ),
                    ),
                  ],
                ),
              ),
              if (listenBeside) ...<Widget>[
                const SizedBox(width: 12),
                listen,
              ],
            ],
          ),
          if (!listenBeside) ...<Widget>[
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: listen),
          ],
          if (c.listenNote != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              c.listenNote!,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.brandMuted,
              ),
            ),
          ],
          if (question.visual != null) ...<Widget>[
            const SizedBox(height: 14),
            QuestionVisual(visual: question.visual!),
          ],
          const SizedBox(height: 14),
          _options(c, question, width),
          const SizedBox(height: 16),
          _navigation(c),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.lightbulb_outline,
                size: 16,
                color: AppColors.brandMuted,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Take your time. You can hear the question again at any '
                  'point, and go back to change an answer.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.brandMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _listenButton(AssessmentController c) {
    final bool speaking = c.speech == QuestionSpeech.speaking;

    return OutlinedButton.icon(
      key: AssessmentScreen.listenKey,
      onPressed: c.listen,
      icon: Icon(speaking ? Icons.stop : Icons.volume_up_outlined, size: 19),
      label: Text(
        speaking ? 'Stop' : c.listenLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.brandNavy,
        // The theme's buttons are full-width by default, which demands an
        // infinite width from any row this sits in.
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        side: const BorderSide(color: AppColors.authFieldBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _options(
    AssessmentController c,
    QuizQuestion question,
    double width,
  ) {
    // Four across needs about 90dp each before the numerals start shrinking.
    final int columns = width >= 480 ? question.options.length : 2;
    final double gap = 10;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double tile =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (int i = 0; i < question.options.length; i++)
              SizedBox(
                width: tile,
                child: OptionTile(
                  key: AssessmentScreen.optionKey(question.options[i].id),
                  letter: QuizQuestion.letterFor(i),
                  label: question.options[i].label,
                  selected:
                      c.selectedOptionId == question.options[i].id,
                  onTap: () => c.select(question.options[i].id),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Brings the summary into view once it exists.
  void _scrollToSummary() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _navigation(AssessmentController c) {
    // On the last question the button stops being "next" and becomes the way
    // to the summary, which only exists once every question is answered.
    final bool toSummary = !c.hasNext;

    final Widget next = FilledButton.icon(
      key: AssessmentScreen.nextKey,
      // Disabled rather than silently doing nothing, so it is obvious that an
      // answer is needed first.
      onPressed: !c.isAnswered
          ? null
          : (toSummary ? _scrollToSummary : c.next),
      icon: Icon(
        toSummary ? Icons.expand_more : Icons.arrow_forward,
        size: 19,
      ),
      iconAlignment: IconAlignment.end,
      label: Text(toSummary ? 'See Results' : 'Next Question'),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.authNavy,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.authIconCircle,
        disabledForegroundColor: AppColors.textDisabled,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );

    if (!c.hasPrevious) {
      return SizedBox(width: double.infinity, child: next);
    }

    return Row(
      children: <Widget>[
        OutlinedButton.icon(
          key: AssessmentScreen.previousKey,
          onPressed: c.previous,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back'),
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppColors.brandNavy,
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            side: const BorderSide(color: AppColors.authFieldBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: next),
      ],
    );
  }

  // --- The summary ---------------------------------------------------------

  Widget _completion(
    AssessmentController c,
    QuizResult result,
    double width,
  ) {
    final PracticeSuggestion? suggestion = c.suggestion;
    // Three panels need roughly 210dp each before the concept names wrap to
    // one word a line.
    final bool inRow = width >= 700;

    final Widget score = _scorePanel(result);
    final Widget understood = ConceptList(
      title: 'Concepts Understood',
      icon: Icons.check_circle_outline,
      colour: AppColors.setupLiteracy,
      concepts: result.understood,
      emptyLabel: 'No concept was answered correctly all the way through yet.',
    );
    final Widget reinforce = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ConceptList(
          title: 'Needs Reinforcement',
          icon: Icons.adjust,
          colour: AppColors.brandOrange,
          concepts: result.needsReinforcement,
          emptyLabel: 'Every concept in this assessment was answered '
              'correctly.',
        ),
        if (suggestion != null) ...<Widget>[
          const SizedBox(height: 12),
          _suggestionCard(suggestion),
        ],
      ],
    );

    return Container(
      key: AssessmentScreen.completionKey,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 18),
      decoration: BoxDecoration(
        color: AppColors.setupLiteracyTint,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Assessment Completed',
                      style: TextStyle(
                        fontSize: 21,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: AppColors.setupLiteracy,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'All ${result.total} questions answered in '
                      '${result.durationLabel}.',
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: AppColors.brandBody,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                key: AssessmentScreen.viewDetailsKey,
                onPressed: () => _openDetails(c),
                icon: const Icon(Icons.bar_chart, size: 18),
                label: const Text('Details'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.brandNavy,
                  minimumSize: const Size(0, 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                  side: const BorderSide(color: AppColors.authFieldBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (inRow)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: score),
                  const SizedBox(width: 12),
                  Expanded(child: understood),
                  const SizedBox(width: 12),
                  Expanded(child: reinforce),
                ],
              ),
            )
          else ...<Widget>[
            score,
            const SizedBox(height: 12),
            understood,
            const SizedBox(height: 12),
            reinforce,
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: AssessmentScreen.continueLearningKey,
              onPressed: () => _continueLearning(c),
              icon: const Icon(Icons.menu_book_outlined, size: 19),
              label: const Text('Continue Learning'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.setupLiteracy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scorePanel(QuizResult result) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Column(
        children: <Widget>[
          const Text(
            'Your Score',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.brandBody,
            ),
          ),
          const SizedBox(height: 12),
          ScoreRing(
            score: result.score,
            total: result.total,
            percentage: result.percentage,
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.star, size: 17, color: AppColors.brandGold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.encouragement,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandBody,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _suggestionCard(PracticeSuggestion suggestion) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
      decoration: BoxDecoration(
        color: AppColors.homeBannerTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondaryContainer),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.lightbulb_outline,
                size: 17,
                color: AppColors.warning,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  suggestion.headline,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            suggestion.body,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.brandBody,
            ),
          ),
          const SizedBox(height: 8),
          // Named for what it is. This is arithmetic on the counts above, and
          // calling it an AI suggestion would be a claim the app cannot make.
          Text(
            suggestion.sourceNote,
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
}

/// The plain scaffold used by the loading, error and empty states.
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
            AssessmentHeader(
              status: 'Offline Assessment',
              statusKey: AssessmentScreen.statusKey,
              backKey: AssessmentScreen.backKey,
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
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );

    return Padding(
      key: AssessmentScreen.skeletonKey,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          block(30, 0.62),
          const SizedBox(height: 10),
          block(16, 0.45),
          const SizedBox(height: 18),
          block(8, 1),
          const SizedBox(height: 20),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
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
