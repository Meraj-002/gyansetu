import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/constants/app_assets.dart';
import '../../core/constants/app_colors.dart';
import '../../models/lesson.dart';
import '../../models/lesson_plan.dart';
import '../../models/lesson_translation.dart';
import '../../services/audio/audio_resource_store.dart';
import '../../services/audio/lesson_audio_service.dart';
import '../../services/audio/text_to_speech_service.dart';
import '../../services/connectivity/connectivity_service.dart';
import '../../services/storage/secure_storage_service.dart';
import '../auth/services/auth_session_store.dart';
import '../flashcards/flashcards_screen.dart' show FlashcardsArgs;
import '../progress/services/learning_progress_repository.dart';
import '../setup/data/classroom_setup_storage.dart';
import '../setup/models/classroom_setup.dart';
import '../setup/services/classroom_setup_repository.dart';
import '../setup/services/offline_resource_manager.dart';
import '../worksheet/worksheet_generator_screen.dart'
    show WorksheetGeneratorArgs;
import 'lesson_navigation.dart';
import 'services/ai_content_service.dart';
import 'services/assessment_repository.dart';
import 'services/lesson_content_repository.dart';
import 'services/lesson_detail_controller.dart';
import 'services/lesson_library_controller.dart' show LibraryOfflineState;
import 'services/lesson_repository.dart';
import 'services/translation_service.dart';
import 'widgets/lesson_detail_widgets.dart';

/// The AI Teacher Copilot view of a single lesson.
///
/// It is handed a lesson id and resolves it through [LessonRepository] — the
/// same repository the dashboard and the library use — so the three screens can
/// never describe the same lesson differently.
///
/// Every language on this screen comes from the saved classroom: the script is
/// in the teaching medium, the translation and the audio are in the mother
/// tongue. Changing the classroom from Santali to Mundari changes every label
/// here without a line of this file changing.
class LessonDetailScreen extends StatefulWidget {
  const LessonDetailScreen({
    this.lessonId,
    this.controller,
    this.lessons,
    this.content,
    this.translations,
    this.audio,
    this.progress,
    this.assessments,
    this.classrooms,
    this.resources,
    this.connectivity,
    this.teacherId,
    super.key,
  });

  static const Key scrollKey = Key('lesson-detail-scroll');
  static const Key playButtonKey = Key('lesson-detail-play');
  static const Key translateButtonKey = Key('lesson-detail-translate');
  static const Key slowButtonKey = Key('lesson-detail-slow');
  static const Key repeatButtonKey = Key('lesson-detail-repeat');
  static const Key saveAudioButtonKey = Key('lesson-detail-save-audio');
  static const Key liveClassroomKey = Key('lesson-detail-live-classroom');
  static const Key flashcardsKey = Key('lesson-detail-flashcards');
  static const Key moreMenuKey = Key('lesson-detail-more');
  static const Key backButtonKey = Key('lesson-detail-back');
  static const Key scriptSpeakKey = Key('lesson-detail-speak-script');
  static const Key targetSpeakKey = Key('lesson-detail-speak-target');

  /// Falls back to the route argument when not passed directly.
  final String? lessonId;

  /// Supplied whole by tests; built from the injected parts otherwise.
  final LessonDetailController? controller;

  final LessonRepository? lessons;
  final LessonContentRepository? content;
  final TranslationService? translations;
  final LessonAudioService? audio;
  final LessonProgressRepository? progress;
  final AssessmentRepository? assessments;
  final ClassroomSetupRepository? classrooms;
  final OfflineResourceManager? resources;
  final ConnectivityService? connectivity;
  final String? teacherId;

  @override
  State<LessonDetailScreen> createState() => _LessonDetailScreenState();
}

class _LessonDetailScreenState extends State<LessonDetailScreen> {
  LessonDetailController? _controller;

  /// Owned only when this screen created them, so a test's services are never
  /// disposed underneath it.
  ConnectivityService? _ownedConnectivity;
  LessonAudioService? _ownedAudio;

  bool _built = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_built) return;
    _built = true;

    final LessonDetailController? given = widget.controller;
    if (given != null) {
      _controller = given;
      return;
    }
    final Object? routeArguments = ModalRoute.of(context)?.settings.arguments;
    final String? lessonId =
        widget.lessonId ?? LessonDetailArgs.lessonIdFrom(routeArguments);

    // Nothing to resolve without an id; build renders the missing-lesson state.
    if (lessonId != null) unawaited(_buildController(lessonId));
  }

  Future<void> _buildController(String lessonId) async {
    final SecureStorageService storage = PlatformSecureStorageService();

    // The same resolution the library uses, so both screens read one teacher's
    // progress rather than two different ones.
    final String teacherId = widget.teacherId ??
        (await AuthSessionStore(storage).account())?.id ??
        'local-teacher';
    if (!mounted) return;

    final ConnectivityService connectivity = widget.connectivity ??
        (_ownedConnectivity = PlatformConnectivityService());

    final LessonDownloadRepository downloads =
        LocalLessonDownloadRepository(storage);
    final AiContentService ai = DevelopmentAiContentService();

    final LessonAudioService audio = widget.audio ??
        (_ownedAudio = TtsLessonAudioService(
          tts: PlatformTextToSpeechService(),
          store: LocalAudioResourceStore(storage),
          connectivity: connectivity,
        ));

    setState(() {
      _controller = LessonDetailController(
        lessonId: lessonId,
        lessons:
            widget.lessons ??
                defaultLessonRepository(storage: storage, downloads: downloads),
        content: widget.content ??
            LocalLessonContentRepository(ai: ai, storage: storage),
        translations: widget.translations ??
            AiTranslationService(
              ai: ai,
              storage: storage,
              connectivity: connectivity,
            ),
        audio: audio,
        progress:
            widget.progress ?? LocalLessonProgressRepository(storage),
        assessments: widget.assessments ?? LocalAssessmentRepository(storage),
        classrooms: widget.classrooms ??
            LocalClassroomSetupRepository(defaultClassroomSetupStorage()),
        resources: widget.resources ?? const BundledOfflineResourceManager(),
        connectivity: connectivity,
        teacherId: teacherId,
        // So Learning Insights can say when a lesson was finished, not only
        // that it was.
        recorder: ProgressRecorder(
          LocalLearningProgressRepository(storage),
        ),
      );
    });
  }

  @override
  void dispose() {
    // Only what this screen made is torn down here.
    if (widget.controller == null) _controller?.dispose();
    _ownedAudio?.dispose();
    _ownedConnectivity?.dispose();
    super.dispose();
  }

  // --- Actions -------------------------------------------------------------

  Future<void> _openActivity(LessonDetailController c) async {
    final LessonPlan? plan = c.plan;
    final Lesson? lesson = c.lesson;
    if (plan == null || lesson == null) return;

    final Object? result = await Navigator.of(context).pushNamed(
      AppRoutes.lessonActivity,
      arguments: LessonActivityArgs(
        lessonId: lesson.id,
        lessonTitle: lesson.title,
        activity: plan.activity,
      ),
    );
    // Progress is recorded because the teacher opened it, not because the
    // screen was pushed: the route only resolves once they come back.
    await c.activityOpened();
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Activity marked as done.')),
      );
    }
  }

  Future<void> _openAssessment(LessonDetailController c) async {
    final LessonPlan? plan = c.plan;
    final Lesson? lesson = c.lesson;
    if (plan == null || lesson == null) return;

    final Object? result = await Navigator.of(context).pushNamed(
      AppRoutes.lessonAssessment,
      arguments: LessonAssessmentArgs(
        lessonId: lesson.id,
        lessonTitle: lesson.title,
        assessment: plan.assessment,
        previous: c.assessmentResult,
      ),
    );
    if (result is AssessmentResult) await c.recordAssessment(result);
  }

  /// Opens the flashcards for this lesson.
  ///
  /// Available before the lesson as much as after it: a teacher preparing to
  /// teach counting wants the number cards in their hand first, not as a
  /// reward for finishing. Nothing is required to have happened.
  Future<void> _openFlashcards(LessonDetailController c) async {
    final Lesson? lesson = c.lesson;
    if (lesson == null) return;

    await c.stopAudio();
    if (!mounted) return;

    // Only the lesson id travels. The flashcards screen reads the class, the
    // subject and the mother tongue from the same saved classroom this screen
    // does, and picks the deck from the lesson — so the two cannot disagree.
    await Navigator.of(context).pushNamed(
      AppRoutes.flashcards,
      arguments: FlashcardsArgs(lessonId: lesson.id),
    );
  }

  Future<void> _startLiveClassroom(LessonDetailController c) async {
    final Lesson? lesson = c.lesson;
    final ClassroomSetup? classroom = c.classroom;
    if (lesson == null || classroom == null) return;

    await c.stopAudio();
    if (!mounted) return;

    // Python lesson uses English as its target language instead of Santali.
    final TargetLanguage targetLang = lesson.id == 'python-intro'
        ? TargetLanguage.english
        : classroom.targetLanguage;

    await Navigator.of(context).pushNamed(
      AppRoutes.liveClassroom,
      arguments: LiveClassroomArgs(
        lessonId: lesson.id,
        lessonTitle: lesson.title,
        learningOutcome: lesson.learningOutcome,
        classLevel: classroom.classLevel,
        subject: lesson.subject,
        teachingMedium: classroom.teachingMedium,
        targetLanguage: targetLang,
        teacherScript: c.plan?.teacherScript,
        translatedScript: c.translation?.text,
      ),
    );
  }

  Future<void> _openMoreMenu(LessonDetailController c) async {
    final Lesson? lesson = c.lesson;
    if (lesson == null) return;

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
            const SizedBox(height: 8),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outline,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 10),
            // Only actions this build can really perform are offered. Sharing
            // and reporting need a backend that does not exist, so they are not
            // listed at all rather than listed and inert.
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Lesson information'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showLessonInfo(c);
              },
            ),
            ListTile(
              key: const Key('lesson-detail-flashcards'),
              leading: const Icon(Icons.style_outlined),
              title: const Text('Flashcards'),
              subtitle: const Text('Picture cards for this lesson'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).pushNamed(
                  AppRoutes.flashcards,
                  arguments: FlashcardsArgs(lessonId: lesson.id),
                );
              },
            ),
            ListTile(
              key: const Key('lesson-detail-create-worksheet'),
              leading: const Icon(Icons.description_outlined),
              title: const Text('Create worksheet'),
              subtitle: const Text('Build a printable sheet for this lesson'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).pushNamed(
                  AppRoutes.worksheet,
                  arguments: WorksheetGeneratorArgs(lesson.id),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Manage offline downloads'),
              subtitle: const Text('Opens the offline centre'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).pushNamed(AppRoutes.offline);
              },
            ),
            ListTile(
              leading: const Icon(Icons.volume_down_outlined),
              title: Text('Save ${c.targetLanguage.label} audio'),
              enabled: c.targetPassage != null && !c.audioSaved,
              onTap: () {
                Navigator.of(sheetContext).pop();
                c.saveAudio();
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _showLessonInfo(LessonDetailController c) {
    final Lesson? lesson = c.lesson;
    if (lesson == null) return;
    final LessonPlan? plan = c.plan;

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Text(lesson.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _InfoLine(label: 'Class', value: 'Class ${lesson.classNumber}'),
            _InfoLine(label: 'Subject', value: lesson.subject.label),
            _InfoLine(
              label: 'Duration',
              value: '${lesson.durationMinutes} min',
            ),
            _InfoLine(
              label: 'Content',
              value: plan?.provenance.label ?? 'Not on this device',
            ),
            _InfoLine(
              label: 'Progress',
              value: '${c.completionPercentage}%',
            ),
          ],
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
    final LessonDetailController? c = _controller;

    if (c == null) {
      return const _DetailShell(
        child: _CentredMessage(
          icon: Icons.menu_book_outlined,
          title: 'No lesson was chosen.',
          body: 'Open a lesson from the library so this screen knows which one '
              'to show.',
        ),
      );
    }

    return AnimatedBuilder(
      animation: c,
      builder: (BuildContext context, _) {
        final Widget body;
        if (c.loading && !c.hasContent) {
          body = const _DetailSkeleton();
        } else if (c.notFound || c.lesson == null) {
          body = _CentredMessage(
            icon: Icons.search_off,
            title: "Couldn't find this lesson.",
            body: 'It may have been removed from the library.',
            actionLabel: 'Back to lessons',
            onAction: () => Navigator.of(context).pop(),
          );
        } else {
          body = _content(context, c);
        }

        return Scaffold(
          backgroundColor: AppColors.homePage,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                _Header(
                  state: c.offlineState,
                  onBack: () => Navigator.of(context).maybePop(),
                  onMore: c.lesson == null ? null : () => _openMoreMenu(c),
                ),
                Expanded(child: body),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _content(BuildContext context, LessonDetailController c) {
    final Lesson lesson = c.lesson!;

    return RefreshIndicator(
      onRefresh: c.load,
      color: AppColors.authNavy,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = constraints.maxWidth;
          final double contentWidth = width.clamp(0.0, 720.0);
          final double side = ((width - contentWidth) / 2) + 16;

          return ListView(
            key: LessonDetailScreen.scrollKey,
            // Always scrollable so pull-to-refresh works even on a large
            // screen where the content already fits.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(side, 6, side, 28),
            children: <Widget>[
              _LessonHeading(controller: c, lesson: lesson),
              const SizedBox(height: 18),
              if (c.message != null) ...<Widget>[
                _Notice(message: c.message!, onDismiss: c.dismissMessage),
                const SizedBox(height: 14),
              ],
              LearningOutcomeCard(
                outcome: lesson.learningOutcome,
                competency: c.plan?.flnCompetency,
              ),
              const SizedBox(height: 22),
              if (!c.hasContent)
                _MissingContent(
                  message: c.planMessage ??
                      "Lesson content isn't available for this lesson yet.",
                  onRetry: c.load,
                )
              else ...<Widget>[
                _scriptSection(c),
                const SizedBox(height: 16),
                _translationSection(c),
                const SizedBox(height: 16),
                _playerSection(c),
                const SizedBox(height: 12),
                _controlsRow(c),
                const SizedBox(height: 22),
                _activityAndAssessment(c),
                if (c.plan?.tip != null) ...<Widget>[
                  const SizedBox(height: 14),
                  TeachingTipCard(
                    text: c.plan!.tip!.text,
                    fromAi: c.plan!.tip!.provenance.involvesAi,
                  ),
                ],
                const SizedBox(height: 18),
                _liveClassroomCta(c),
              ],
            ],
          );
        },
      ),
    );
  }

  // --- Sections ------------------------------------------------------------

  Widget _scriptSection(LessonDetailController c) {
    final LessonPlan plan = c.plan!;
    final bool playing =
        c.activePassage == LessonDetailController.scriptPassageId &&
            c.playback == PlaybackState.playing;
    final bool loading =
        c.activePassage == LessonDetailController.scriptPassageId &&
            c.playback == PlaybackState.loading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(
              Icons.menu_book_outlined,
              size: 22,
              color: AppColors.brandNavy,
            ),
            const SizedBox(width: 9),
            const Text(
              'Teacher Script',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.brandNavy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        PassageCard(
          languageLabel: plan.scriptMedium.label,
          roleLabel: '(Teaching Language)',
          text: plan.teacherScript,
          tint: AppColors.setupNumeracy,
          background: AppColors.setupNumeracyTint,
          speak: SpeakButton(
            key: LessonDetailScreen.scriptSpeakKey,
            label: 'Play the ${plan.scriptMedium.label} script',
            playing: playing,
            loading: loading,
            tint: AppColors.setupNumeracy,
            onPressed: c.playScript,
          ),
        ),
      ],
    );
  }

  Widget _translationSection(LessonDetailController c) {
    final LessonTranslation? translation = c.translation;
    final String language = c.targetLanguage.label;

    final bool playing =
        c.activePassage == LessonDetailController.targetPassageId &&
            c.playback == PlaybackState.playing;
    final bool loading =
        c.activePassage == LessonDetailController.targetPassageId &&
            c.playback == PlaybackState.loading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Center(
          child: Icon(
            Icons.expand_more,
            size: 24,
            color: AppColors.brandNavy.withValues(alpha: 0.35),
          ),
        ),
        const SizedBox(height: 4),
        _TranslateControl(controller: c),
        if (c.translationMessage != null &&
            c.translationState != TranslationUiState.ready) ...<Widget>[
          const SizedBox(height: 10),
          _TranslationProblem(controller: c),
        ],
        if (translation != null) ...<Widget>[
          const SizedBox(height: 10),
          PassageCard(
            text: translation.text,
            tint: AppColors.setupLiteracy,
            background: AppColors.homeOfflineTint,
            // Said plainly: an unreviewed translation is a draft, and a teacher
            // standing in front of a class deserves to know that.
            footnote: translation.reviewedBySpeaker
                ? null
                : 'Prototype translation — not yet checked by a $language '
                    'speaker.',
            speak: SpeakButton(
              key: LessonDetailScreen.targetSpeakKey,
              label: 'Play the $language translation',
              playing: playing,
              loading: loading,
              tint: AppColors.setupLiteracy,
              onPressed: c.playTarget,
            ),
          ),
        ] else if (c.translationState == TranslationUiState.idle) ...<Widget>[
          const SizedBox(height: 10),
          _EmptyHint(
            text: 'Translate this lesson to the classroom’s mother '
                'tongue.',
          ),
        ],
      ],
    );
  }

  Widget _playerSection(LessonDetailController c) {
    final String language = c.targetLanguage.label;
    final bool hasTranslation = c.targetPassage != null;
    final AudioAvailability? availability = c.targetAudio;
    final bool canPlay = hasTranslation && (availability?.canPlay ?? false);

    final bool active =
        c.activePassage == LessonDetailController.targetPassageId;
    final bool playing = active && c.playback == PlaybackState.playing;
    final bool loading = active && c.playback == PlaybackState.loading;

    final String label = switch (true) {
      _ when loading => 'Preparing $language',
      _ when playing => 'Playing $language',
      _ when active && c.playback == PlaybackState.paused =>
        'Resume $language',
      _ => 'Play $language',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          button: true,
          enabled: canPlay,
          label: playing ? 'Pause $language audio' : '$label audio',
          child: ExcludeSemantics(
            child: Material(
              color: canPlay
                  ? AppColors.authNavy
                  : AppColors.authNavy.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                key: LessonDetailScreen.playButtonKey,
                onTap: canPlay ? c.playTarget : null,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 20,
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: loading
                            ? const Padding(
                                padding: EdgeInsets.all(17),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: AppColors.authNavy,
                                ),
                              )
                            : Icon(
                                playing
                                    ? Icons.pause
                                    : Icons.play_arrow_rounded,
                                size: 34,
                                color: AppColors.authNavy,
                              ),
                      ),
                      const SizedBox(width: 16),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            label,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: AudioWaveform(
                            progress: c.audioProgress,
                            active: playing || loading,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!hasTranslation) ...<Widget>[
          const SizedBox(height: 8),
          _PlayerNote(
            icon: Icons.info_outline,
            text: 'Audio will be prepared when you translate this lesson.',
          ),
        ] else if (availability != null && !availability.canPlay) ...<Widget>[
          const SizedBox(height: 8),
          _PlayerNote(
            icon: Icons.volume_off_outlined,
            text: availability.blockedReason ??
                'Audio in $language is not available on this device yet.',
          ),
        ] else if (availability?.note != null) ...<Widget>[
          const SizedBox(height: 8),
          _PlayerNote(icon: Icons.record_voice_over_outlined,
              text: availability!.note!),
        ],
      ],
    );
  }

  Widget _controlsRow(LessonDetailController c) {
    final bool hasAudio = c.targetPassage != null &&
        (c.targetAudio?.canPlay ?? false);
    final bool slow = c.speed == AudioSpeed.slow;

    return Row(
      children: <Widget>[
        Expanded(
          child: PlayerControl(
            key: LessonDetailScreen.slowButtonKey,
            icon: slow ? Icons.speed : Icons.slow_motion_video,
            label: slow ? AudioSpeed.slow.label : 'Slow',
            semanticLabel: slow
                ? 'Playback speed 0.75 times. Tap for normal speed'
                : 'Slow playback, 0.75 times',
            active: slow,
            onPressed: hasAudio ? c.toggleSpeed : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: PlayerControl(
            key: LessonDetailScreen.repeatButtonKey,
            icon: Icons.refresh,
            label: 'Repeat',
            semanticLabel: 'Repeat from the beginning',
            onPressed: hasAudio ? c.repeat : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: PlayerControl(
            key: LessonDetailScreen.saveAudioButtonKey,
            icon: c.audioSaved
                ? Icons.download_done
                : Icons.download_outlined,
            label: c.audioSaved ? 'Saved' : 'Save Audio',
            semanticLabel: c.audioSaved
                ? 'Audio saved on this device'
                : 'Save audio for offline use',
            busy: c.savingAudio,
            active: c.audioSaved,
            onPressed: hasAudio && !c.audioSaved ? c.saveAudio : null,
          ),
        ),
      ],
    );
  }

  Widget _activityAndAssessment(LessonDetailController c) {
    final LessonPlan plan = c.plan!;
    final AssessmentResult? result = c.assessmentResult;

    return Column(
      children: <Widget>[
        SectionCard(
          icon: Icons.groups,
          title: 'Classroom Activity',
          subtitle: plan.activity.summary,
          tint: AppColors.setupNumeracy,
          background: AppColors.setupNumeracyTint,
          onTap: () => _openActivity(c),
        ),
        const SizedBox(height: 12),
        SectionCard(
          icon: Icons.assignment_turned_in_outlined,
          title: 'Quick Assessment',
          subtitle: plan.assessment.summary,
          tint: AppColors.setupLiteracy,
          background: AppColors.homeOfflineTint,
          footnote: result == null
              ? null
              : 'Last recorded: ${result.achievedCount} of ${result.total} '
                  'can do',
          onTap: () => _openAssessment(c),
        ),
        const SizedBox(height: 12),
        SectionCard(
          key: LessonDetailScreen.flashcardsKey,
          icon: Icons.style_outlined,
          title: 'Practice with Flashcards',
          subtitle: 'Picture cards for this lesson, in Hindi and the mother '
              'tongue. Use them before the lesson or after it.',
          tint: AppColors.brandOrange,
          background: AppColors.homeBannerTint,
          onTap: () => _openFlashcards(c),
        ),
      ],
    );
  }

  Widget _liveClassroomCta(LessonDetailController c) {
    final bool ready = c.classroom != null;

    return Semantics(
      button: true,
      enabled: ready,
      label: 'Start live classroom for this lesson',
      child: ExcludeSemantics(
        child: FilledButton(
          key: LessonDetailScreen.liveClassroomKey,
          onPressed: ready ? () => _startLiveClassroom(c) : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.authNavy,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.brandMuted.withValues(
              alpha: 0.3,
            ),
            minimumSize: const Size(0, 62),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.groups, size: 26),
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Start Live Classroom',
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Header: back, brand, offline pill, more.
class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.onBack,
    required this.onMore,
  });

  final LibraryOfflineState state;
  final VoidCallback onBack;
  final VoidCallback? onMore;

  ({Color tint, IconData icon}) get _style => switch (state) {
        LibraryOfflineState.online =>
          (tint: AppColors.info, icon: Icons.cloud_done_outlined),
        LibraryOfflineState.offlineReady =>
          (tint: AppColors.setupLiteracy, icon: Icons.cloud_done_outlined),
        LibraryOfflineState.syncRequired =>
          (tint: AppColors.warning, icon: Icons.cloud_sync_outlined),
        LibraryOfflineState.resourcesMissing =>
          (tint: AppColors.warning, icon: Icons.cloud_off),
        LibraryOfflineState.unknown =>
          (tint: AppColors.brandMuted, icon: Icons.cloud_queue),
      };

  @override
  Widget build(BuildContext context) {
    final ({Color tint, IconData icon}) s = _style;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // The tagline is the first thing to go on a narrow phone: it is brand
        // decoration, and the status pill beside it is information.
        final bool showTagline = constraints.maxWidth >= 380;

        return Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 8, 4),
          child: Row(
            children: <Widget>[
              IconButton(
                key: LessonDetailScreen.backButtonKey,
                onPressed: onBack,
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back, size: 24),
                color: AppColors.brandNavy,
              ),
              Image.asset(
                AppAssets.loginBrandMark,
                height: 34,
                filterQuality: FilterQuality.medium,
                excludeFromSemantics: true,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Semantics(
                  label: 'GyanSetu AI',
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text.rich(
                            TextSpan(
                              children: const <InlineSpan>[
                                TextSpan(
                                  text: 'GyanSetu',
                                  style:
                                      TextStyle(color: AppColors.brandNavy),
                                ),
                                TextSpan(text: ' '),
                                TextSpan(
                                  text: 'AI',
                                  style:
                                      TextStyle(color: AppColors.brandOrange),
                                ),
                              ],
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                        ),
                        if (showTagline)
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Bridging Languages. Building Futures.',
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.brandNavy
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Semantics(
                liveRegion: true,
                label: state.label,
                child: ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.authChip,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(s.icon, size: 16, color: s.tint),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 108),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              state.label,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: s.tint,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                key: LessonDetailScreen.moreMenuKey,
                onPressed: onMore,
                tooltip: 'More options',
                icon: const Icon(Icons.more_vert, size: 22),
                color: AppColors.brandNavy,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Portrait, title, class, subject and the provenance badge.
class _LessonHeading extends StatelessWidget {
  const _LessonHeading({required this.controller, required this.lesson});

  final LessonDetailController controller;
  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    final LessonPlan? plan = controller.plan;

    final Widget text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          lesson.title,
          style: const TextStyle(
            fontSize: 30,
            height: 1.08,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: AppColors.brandNavy,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: <Widget>[
            DetailChip(label: 'Class ${lesson.classNumber}'),
            DetailChip(
              label: lesson.subject.label,
              icon: lesson.subject == ClassroomSubject.numeracy
                  ? Icons.pin_outlined
                  : Icons.abc,
            ),
          ],
        ),
        if (plan != null) ...<Widget>[
          const SizedBox(height: 9),
          ProvenanceBadge(
            // Only content the AI layer actually produced carries the label.
            aiLabel: plan.provenance.involvesAi ? plan.provenance.label : null,
            curriculumAligned: plan.curriculumAligned,
          ),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Measured against the card's own width. Below this the portrait and a
        // 30pt title cannot share a line without the title breaking badly.
        final bool sideBySide = constraints.maxWidth >= 330;
        final double avatar = constraints.maxWidth >= 400 ? 116.0 : 96.0;

        if (!sideBySide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              LessonAvatar(lesson: lesson, size: avatar),
              const SizedBox(height: 14),
              text,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            LessonAvatar(lesson: lesson, size: avatar),
            const SizedBox(width: 16),
            Expanded(child: text),
          ],
        );
      },
    );
  }
}

/// The translate control, in whichever of its five states applies.
class _TranslateControl extends StatelessWidget {
  const _TranslateControl({required this.controller});

  final LessonDetailController controller;

  @override
  Widget build(BuildContext context) {
    final String language = controller.targetLanguage.label;
    final bool translating = controller.isTranslating;
    final bool done = controller.translationState == TranslationUiState.ready &&
        controller.translation != null;

    final String label = switch (true) {
      _ when translating => 'Translating…',
      _ when done => 'Translated to $language',
      _ => 'Translate to $language',
    };

    return Semantics(
      button: !translating,
      label: label,
      child: ExcludeSemantics(
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: LessonDetailScreen.translateButtonKey,
            // Retranslating what is already on screen would only re-read the
            // cache, so the control settles into a status once it is done.
            onPressed: translating || done ? null : controller.translate,
            icon: translating
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.setupLiteracy,
                    ),
                  )
                : Icon(
                    done ? Icons.check_circle_outline : Icons.g_translate,
                    size: 19,
                  ),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '(Mother Tongue)',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.brandNavy.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.setupLiteracy,
              disabledForegroundColor: done
                  ? AppColors.setupLiteracy
                  : AppColors.setupLiteracy.withValues(alpha: 0.7),
              minimumSize: const Size(48, 46),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ),
      ),
    );
  }
}

/// What went wrong with a translation, and what the teacher can do next.
class _TranslationProblem extends StatelessWidget {
  const _TranslationProblem({required this.controller});

  final LessonDetailController controller;

  @override
  Widget build(BuildContext context) {
    final TranslationUiState state = controller.translationState;
    final bool retryable = state == TranslationUiState.error ||
        state == TranslationUiState.offlineUnavailable;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
      decoration: BoxDecoration(
        color: AppColors.homeBannerTint,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.brandGold.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            state == TranslationUiState.offlineUnavailable
                ? Icons.cloud_off
                : Icons.info_outline,
            size: 20,
            color: AppColors.secondaryDark,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  controller.translationMessage!,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: AppColors.brandNavy.withValues(alpha: 0.85),
                  ),
                ),
                if (retryable) ...<Widget>[
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: controller.translate,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.authNavy,
                      minimumSize: const Size(48, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    child: const Text(
                      'Try Again',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerNote extends StatelessWidget {
  const _PlayerNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: AppColors.brandMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.brandNavy.withValues(alpha: 0.65),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13.5,
          height: 1.4,
          color: AppColors.brandNavy.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

/// Shown when the lesson exists but its content does not.
class _MissingContent extends StatelessWidget {
  const _MissingContent({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.description_outlined,
            size: 30,
            color: AppColors.brandMuted,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(
              fontSize: 15.5,
              height: 1.4,
              fontWeight: FontWeight.w700,
              color: AppColors.brandNavy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'The script, activity and assessment for this lesson have not been '
            'written yet.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: AppColors.brandNavy.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.brandNavy,
              minimumSize: const Size(0, 46),
              side: const BorderSide(color: AppColors.authFieldBorder),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Check again',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: AppColors.homeBannerTint,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.brandGold.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.info_outline,
            size: 19,
            color: AppColors.secondaryDark,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: AppColors.brandNavy.withValues(alpha: 0.85),
              ),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close, size: 18),
            color: AppColors.brandNavy.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.brandNavy.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.brandNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// First-paint placeholder while the lesson and its plan are read.
class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  static const Key skeletonKey = Key('lesson-detail-skeleton');

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
        );

    return ListView(
      key: skeletonKey,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 104,
              height: 104,
              decoration: const BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  bar(double.infinity, 30),
                  bar(140, 34),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        bar(double.infinity, 92),
        const SizedBox(height: 10),
        bar(double.infinity, 110),
        const SizedBox(height: 10),
        bar(double.infinity, 96),
      ],
    );
  }
}

/// The header plus a centred message, for the states with no lesson at all.
class _DetailShell extends StatelessWidget {
  const _DetailShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.homePage,
      appBar: AppBar(
        backgroundColor: AppColors.homePage,
        foregroundColor: AppColors.brandNavy,
        elevation: 0,
        title: const Text('Lesson'),
      ),
      body: SafeArea(child: child),
    );
  }
}

class _CentredMessage extends StatelessWidget {
  const _CentredMessage({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 38, color: AppColors.brandMuted),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.brandNavy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: AppColors.brandNavy.withValues(alpha: 0.7),
              ),
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.authNavy,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
