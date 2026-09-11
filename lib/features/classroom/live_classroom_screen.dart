import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/routes.dart';
import '../../core/constants/app_assets.dart';
import '../../core/constants/app_colors.dart';
import '../../services/ai/ai_runtime_status_service.dart';
import '../../services/audio/audio_resource_store.dart';
import '../../services/audio/audio_recorder.dart';
import '../../services/audio/clip_player.dart';
import '../../services/audio/lesson_audio_service.dart';
import '../../services/audio/text_to_speech_service.dart';
import '../../services/connectivity/connectivity_service.dart';
import '../../services/service_registry.dart';
import '../../services/speech/fallback_speech_recognition_service.dart';
import '../../services/speech/speech_recognition_service.dart';
import '../../services/storage/secure_storage_service.dart';
import '../../services/translation/text_translation_service.dart';
import '../../services/translation/voice_translation_service.dart';
import '../auth/services/auth_session_store.dart';
import '../lessons/lesson_navigation.dart';
import 'conversation_result_screen.dart' show ConversationResultArgs;
import 'models/classroom_session.dart';
import 'models/classroom_state.dart';
import 'models/conversation_turn.dart';
import 'models/voice_pipeline_metrics.dart';
import 'services/classroom_session_repository.dart';
import 'services/live_classroom_controller.dart';
import 'services/voice_conversation_service.dart';
import 'widgets/live_classroom_widgets.dart';

/// The live teaching session.
///
/// The teacher speaks, the class hears their own language, a child answers and
/// the teacher hears the answer back. This screen owns none of that: it starts
/// a [VoiceConversationService] and renders what the state machine reports.
///
/// Nothing heavy loads when this screen opens. The recogniser initialises on
/// the first tap of the microphone and the speech engine on the first sentence,
/// because a teacher who opens the screen and changes their mind should not
/// have paid for a model load on a 2 GB phone.
class LiveClassroomScreen extends StatefulWidget {
  const LiveClassroomScreen({
    this.args,
    this.controller,
    this.speech,
    this.translator,
    this.audio,
    this.voice,
    this.recorder,
    this.player,
    this.sessions,
    this.runtime,
    this.connectivity,
    this.teacherId,
    super.key,
  });

  static const Key contextKey = Key('live-classroom-context');
  static const Key latencyKey = Key('live-latency');
  static const Key statusKey = Key('live-status');
  static const Key muteKey = Key('live-mute');
  static const Key repeatKey = Key('live-repeat');
  static const Key endKey = Key('live-end');
  static const Key playToStudentsKey = Key('live-play-to-students');
  static const Key studentTurnKey = Key('live-student-turn');
  static const Key clearTimelineKey = Key('live-clear-timeline');
  static const Key moreKey = Key('live-more');
  static const Key backKey = Key('live-back');
  static const Key retryKey = Key('live-retry');

  final LiveClassroomArgs? args;

  /// Supplied whole by tests; built from the parts below otherwise.
  final LiveClassroomController? controller;

  final SpeechRecognitionService? speech;
  final TextTranslationService? translator;
  final LessonAudioService? audio;
  final VoiceTranslationService? voice;
  final AudioRecorder? recorder;
  final ClipPlayer? player;
  final ClassroomSessionRepository? sessions;
  final AiRuntimeStatusService? runtime;
  final ConnectivityService? connectivity;
  final String? teacherId;

  @override
  State<LiveClassroomScreen> createState() => _LiveClassroomScreenState();
}

class _LiveClassroomScreenState extends State<LiveClassroomScreen>
    with WidgetsBindingObserver {
  LiveClassroomController? _controller;

  /// Only what this screen created is disposed by it.
  VoiceConversationService? _ownedConversation;
  ConnectivityService? _ownedConnectivity;
  LessonAudioService? _ownedAudio;
  SpeechRecognitionService? _ownedSpeech;

  bool _built = false;
  bool _ending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_built) return;
    _built = true;

    final LiveClassroomController? given = widget.controller;
    if (given != null) {
      _controller = given;
      return;
    }

    final Object? routeArgs = ModalRoute.of(context)?.settings.arguments;
    final LiveClassroomArgs? args =
        widget.args ?? (routeArgs is LiveClassroomArgs ? routeArgs : null);
    if (args != null) unawaited(_build(args));
  }

  Future<void> _build(LiveClassroomArgs args) async {
    final SecureStorageService storage = PlatformSecureStorageService();
    final String? teacherId = widget.teacherId ??
        (await AuthSessionStore(storage).account())?.id;
    if (!mounted) return;

    final ConnectivityService connectivity = widget.connectivity ??
        (_ownedConnectivity = PlatformConnectivityService());

    // The device recogniser is the real one. Where it cannot serve the
    // classroom's languages, the development adapter takes over and every
    // measurement it produces is labelled as a demo, all the way to the badge.
    // The choice is made on the first tap, not here: initialising a recogniser
    // now would cost a low-end phone time and would prompt for the microphone
    // before anyone had asked to speak.
    final SpeechRecognitionService speech =
        widget.speech ?? (_ownedSpeech = FallbackSpeechRecognitionService());

    final LessonAudioService audio = widget.audio ??
        (_ownedAudio = TtsLessonAudioService(
          tts: PlatformTextToSpeechService(),
          store: LocalAudioResourceStore(storage),
          connectivity: connectivity,
        ));

    // The canonical offline-first decision graph from the registry: cache →
    // phrasebook → offline model → online backend. What each answer reports as
    // its source — phrasebook / offline / online / cached — is exactly what
    // happened, and no network call is made while the device is offline.
    final ServiceRegistry registry = ServiceRegistry.instance;
    final TextTranslationService translator = widget.translator ??
        registry.translation;

    // The speech-to-speech path. Live Classroom records one Hindi clip, uploads
    // it to Adi Vaani via the backend and plays the returned Santalí WAV back,
    // instead of dictating, text-translating and synthesising locally. These
    // come from the registry, which owns them; each falls back to a
    // widget-injected test double when one is provided.
    final VoiceTranslationService voice = widget.voice ?? registry.voice;
    final AudioRecorder recorder = widget.recorder ?? registry.recorder;
    final ClipPlayer player = widget.player ?? registry.player;

    final ClassroomSessionRepository sessions =
        widget.sessions ?? LocalClassroomSessionRepository(storage);

    final ConversationContext conversationContext = ConversationContext(
      lessonId: args.lessonId,
      lessonTitle: args.lessonTitle,
      learningOutcome: args.learningOutcome,
      classLevel: args.classLevel,
      subject: args.subject,
      teachingMedium: args.teachingMedium,
      targetLanguage: args.targetLanguage,
    );

    final DateTime startedAt = DateTime.now();
    final ClassroomSession session = ClassroomSession(
      // The documented CLS-ddMMyy-HHmm form, generated once here and never
      // regenerated: the result screen must show the same id as the session.
      sessionId: ClassroomSession.idFor(startedAt),
      lessonId: args.lessonId,
      lessonTitle: args.lessonTitle,
      teacherId: teacherId,
      classNumber: args.classLevel,
      subject: args.subject,
      teachingLanguage: args.teachingMedium.localeId,
      targetLanguage: args.targetLanguage.localeId,
      startedAt: startedAt,
    );

    final VoiceConversationService conversation =
        _ownedConversation = LiveVoiceConversationService(
      speech: speech,
      translator: translator,
      audio: audio,
      voice: voice,
      recorder: recorder,
      player: player,
      sessions: sessions,
      context: conversationContext,
      initialSession: session,
      connectivity: connectivity,
    );

    setState(() {
      _controller = LiveClassroomController(
        conversation: conversation,
        runtime: widget.runtime ??
            LocalAiRuntimeService(
              speech: speech,
              translator: translator,
              audio: audio,
              connectivity: connectivity,
            ),
        connectivity: connectivity,
        context: conversationContext,
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A microphone left open behind a lock screen is a privacy problem, not an
    // inconvenience, so it is closed the moment the app leaves the foreground.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_controller?.onPaused());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) _controller?.dispose();
    unawaited(_ownedConversation?.dispose());
    unawaited(_ownedSpeech?.dispose());
    unawaited(_ownedAudio?.dispose());
    unawaited(_ownedConnectivity?.dispose());
    super.dispose();
  }

  // --- Actions -------------------------------------------------------------

  Future<void> _confirmEnd(LiveClassroomController c) async {
    final bool? end = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: AppColors.liveCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text(
          'End classroom session?',
          style: TextStyle(color: AppColors.liveTextPrimary),
        ),
        content: const Text(
          'The conversation so far is saved and you will see a summary.',
          style: TextStyle(color: AppColors.liveTextMuted),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Continue Session'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.liveDanger,
            ),
            child: const Text('End Session'),
          ),
        ],
      ),
    );
    if (end != true || !mounted) return;

    setState(() => _ending = true);
    final ClassroomSession closed = await c.endSession();
    if (!mounted) return;

    // Only the id travels. The result screen reads the session back from the
    // repository, so there is one copy of the session and no chance of the two
    // screens disagreeing about it.
    await Navigator.of(context).pushReplacementNamed(
      AppRoutes.conversationResult,
      arguments: ConversationResultArgs(closed.sessionId),
    );
  }

  Future<void> _confirmClear(LiveClassroomController c) async {
    final bool? clear = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: AppColors.liveCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text(
          'Clear conversation history?',
          style: TextStyle(color: AppColors.liveTextPrimary),
        ),
        content: const Text(
          'This clears what is on screen for this session. Sessions you '
          'finished earlier are not touched.',
          style: TextStyle(color: AppColors.liveTextMuted),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (clear == true) await c.clearTimeline();
  }

  Future<void> _openMenu(LiveClassroomController c) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.liveCard,
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
                color: AppColors.liveBorder,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            // Only actions this build can perform. Nothing here is a dead item.
            ListTile(
              leading: const Icon(
                Icons.info_outline,
                color: AppColors.liveTextPrimary,
              ),
              title: const Text(
                'Session information',
                style: TextStyle(color: AppColors.liveTextPrimary),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showSessionInfo(c);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.language,
                color: AppColors.liveTextPrimary,
              ),
              title: const Text(
                'Language and AI status',
                style: TextStyle(color: AppColors.liveTextPrimary),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showRuntimeInfo(c);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: AppColors.liveTextPrimary,
              ),
              title: const Text(
                'Clear conversation',
                style: TextStyle(color: AppColors.liveTextPrimary),
              ),
              enabled: c.turns.isNotEmpty,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmClear(c);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.cloud_download_outlined,
                color: AppColors.liveTextPrimary,
              ),
              title: const Text(
                'Offline resources',
                style: TextStyle(color: AppColors.liveTextPrimary),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).pushNamed(AppRoutes.offline);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _showSessionInfo(LiveClassroomController c) {
    final ClassroomSession session = c.session;
    _showInfoDialog(
      'Session information',
      <String, String>{
        'Lesson': session.lessonTitle.isEmpty ? '—' : session.lessonTitle,
        'Class': 'Class ${session.classNumber}',
        'Languages': c.context.languagePair,
        'Turns': '${session.totalTurns}',
        'Average latency':
            SessionSummary.format(session.averageLatency),
        'Started': TimeOfDay.fromDateTime(session.startedAt).format(context),
      },
    );
  }

  void _showRuntimeInfo(LiveClassroomController c) {
    final AiRuntimeStatus status = c.runtimeStatus;
    _showInfoDialog(
      'Language and AI status',
      <String, String>{
        for (final AiComponentStatus component in status.components)
          component.component.label: component.available
              ? (component.isRealModel
                  ? 'Available'
                  : 'Available — development adapter')
              : (component.detail ?? 'Unavailable'),
        'Pipeline': status.usesDevelopmentAdapters
            ? 'Demo pipeline — not a trained model'
            : 'Live services',
      },
    );
  }

  void _showInfoDialog(String title, Map<String, String> rows) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: AppColors.liveCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Text(
          title,
          style: const TextStyle(color: AppColors.liveTextPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final MapEntry<String, String> row in rows.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 128,
                      child: Text(
                        row.key,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.liveTextMuted,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        row.value,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: AppColors.liveTextPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
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
    final LiveClassroomController? c = _controller;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.liveBar,
      ),
      child: Scaffold(
        backgroundColor: AppColors.liveBackground,
        body: SafeArea(
          bottom: false,
          child: c == null ? const _NoContext() : _session(context, c),
        ),
      ),
    );
  }

  Widget _session(BuildContext context, LiveClassroomController c) {
    return AnimatedBuilder(
      animation: c,
      builder: (BuildContext context, _) => Column(
        children: <Widget>[
          _Header(
            controller: c,
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
                  key: LiveClassroomScreen.contextKey,
                  padding: EdgeInsets.fromLTRB(side, 4, side, 20),
                  children: <Widget>[
                    _Title(controller: c),
                    const SizedBox(height: 6),
                    _MicrophoneRow(controller: c),
                    const SizedBox(height: 14),
                    if (c.failure != null) ...<Widget>[
                      _FailureBanner(controller: c),
                      const SizedBox(height: 14),
                    ],
                    _TeacherCard(controller: c),
                    const SizedBox(height: 12),
                    _AiCard(controller: c),
                    const SizedBox(height: 12),
                    _StudentCard(controller: c),
                    const SizedBox(height: 16),
                    _Timeline(
                      controller: c,
                      onClear: () => _confirmClear(c),
                    ),
                  ],
                );
              },
            ),
          ),
          _ControlBar(
            controller: c,
            ending: _ending,
            onEnd: () => _confirmEnd(c),
          ),
        ],
      ),
    );
  }
}

/// Back, branding, AI status and the measured latency.
class _Header extends StatelessWidget {
  const _Header({
    required this.controller,
    required this.onBack,
    required this.onMore,
  });

  final LiveClassroomController controller;
  final VoidCallback onBack;
  final VoidCallback onMore;

  Color get _statusTint => switch (controller.runtimeStatus.state) {
        AiRuntimeState.offlineAiActive ||
        AiRuntimeState.onlineAiActive =>
          AppColors.liveStudent,
        AiRuntimeState.limited => AppColors.liveTeacher,
        AiRuntimeState.unavailable => AppColors.liveDanger,
        AiRuntimeState.connecting => AppColors.liveTextMuted,
      };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // The wordmark is the first thing to go on a narrow phone: the mark
        // still identifies the app, while the status and the latency beside it
        // are information the teacher is using.
        final bool showWordmark = constraints.maxWidth >= 380;

        return Padding(
          padding: const EdgeInsets.fromLTRB(2, 4, 4, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              IconButton(
                key: LiveClassroomScreen.backKey,
                onPressed: onBack,
                tooltip: 'Back',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_back, size: 23),
                color: AppColors.liveTextPrimary,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Image.asset(
                  AppAssets.loginBrandMark,
                  height: 30,
                  filterQuality: FilterQuality.medium,
                  excludeFromSemantics: true,
                ),
              ),
              if (showWordmark) ...<Widget>[
                const SizedBox(width: 8),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Semantics(
                      label: 'GyanSetu AI',
                      child: ExcludeSemantics(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text.rich(
                            TextSpan(
                              children: const <InlineSpan>[
                                TextSpan(
                                  text: 'GyanSetu',
                                  style: TextStyle(
                                    color: AppColors.liveTextPrimary,
                                  ),
                                ),
                                TextSpan(text: ' '),
                                TextSpan(
                                  text: 'AI',
                                  style: TextStyle(color: AppColors.brandGold),
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
                      ),
                    ),
                  ),
                ),
              ] else
                // Keeps the name reachable to a screen reader even when the
                // wordmark itself has no room.
                Semantics(
                  label: 'GyanSetu AI',
                  child: const SizedBox.shrink(),
                ),
              const Spacer(),
              const SizedBox(width: 6),
              Flexible(
                flex: 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    _StatusPill(
                      key: LiveClassroomScreen.statusKey,
                      label: controller.runtimeStatus.label,
                      tint: _statusTint,
                      maxLabelWidth: showWordmark ? 132 : 108,
                      leading: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _statusTint,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _LatencyPill(
                      controller: controller,
                      maxLabelWidth: showWordmark ? 132 : 108,
                    ),
                  ],
                ),
              ),
              IconButton(
                key: LiveClassroomScreen.moreKey,
                onPressed: onMore,
                tooltip: 'Session options',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.more_vert, size: 21),
                color: AppColors.liveTextPrimary,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.tint,
    this.leading,
    this.maxLabelWidth = 132,
    super.key,
  });

  final String label;
  final Color tint;
  final Widget? leading;

  /// Narrows on a small phone so the header cannot overflow.
  final double maxLabelWidth;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.liveCardRaised,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.liveBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (leading != null) ...<Widget>[
                leading!,
                const SizedBox(width: 7),
              ],
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxLabelWidth),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: tint,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The measured pipeline latency, or an honest placeholder.
class _LatencyPill extends StatelessWidget {
  const _LatencyPill({required this.controller, this.maxLabelWidth = 132});

  final LiveClassroomController controller;
  final double maxLabelWidth;

  @override
  Widget build(BuildContext context) {
    final VoicePipelineMetrics? metrics = controller.latestMetrics;
    final bool working = controller.state.isBusy;

    // Never a number that was not measured: before the first completed turn
    // this reads as dashes, and while a turn is in flight it says so.
    final String label = switch (true) {
      _ when working => 'Latency: Processing…',
      _ when metrics == null => 'Latency: --',
      _ => 'Latency: ${metrics.totalLabel}',
    };

    final Color tint = switch (true) {
      _ when metrics == null || working => AppColors.liveTextMuted,
      _ when metrics.withinTarget => AppColors.liveStudent,
      _ => AppColors.liveTeacher,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        _StatusPill(
          key: LiveClassroomScreen.latencyKey,
          label: label,
          tint: tint,
          maxLabelWidth: maxLabelWidth,
          leading: Icon(Icons.schedule, size: 14, color: tint),
        ),
        if (metrics != null && !metrics.withinTarget && !working)
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 2),
            child: Text(
              'Slower than the 3 second target',
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.liveTeacher.withValues(alpha: 0.9),
              ),
            ),
          ),
        if (controller.isDemoPipeline)
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 2),
            child: Text(
              'Demo pipeline',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppColors.liveGlowViolet.withValues(alpha: 0.95),
              ),
            ),
          ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.controller});

  final LiveClassroomController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Live Classroom',
          style: TextStyle(
            fontSize: 28,
            height: 1.1,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            color: AppColors.liveTextPrimary,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            // Class and both languages come from the saved classroom, so a
            // classroom switched to Mundari reads Mundari here with no change
            // to this file.
            controller.context.headline,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.liveGlowCyan,
            ),
          ),
        ),
      ],
    );
  }
}

/// The microphone flanked by the two waveforms.
class _MicrophoneRow extends StatelessWidget {
  const _MicrophoneRow({required this.controller});

  final LiveClassroomController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // The orb is sized from the available width so a 320dp phone gets a
        // smaller one rather than a clipped one.
        final double orb = (constraints.maxWidth * 0.46).clamp(140.0, 200.0);
        final bool listening =
            controller.state == ClassroomState.listening;

        return SizedBox(
          height: orb + 34,
          child: Row(
            children: <Widget>[
              Expanded(
                child: LiveWaveform(
                  amplitude: controller.amplitude,
                  tint: AppColors.liveGlowCyan,
                  mirrored: true,
                  active: listening,
                ),
              ),
              MicrophoneOrb(
                state: controller.state,
                enabled: !controller.muted &&
                    controller.runtimeStatus.state !=
                        AiRuntimeState.unavailable,
                size: orb,
                onTap: controller.tapMicrophone,
              ),
              Expanded(
                child: LiveWaveform(
                  amplitude: controller.amplitude,
                  tint: AppColors.liveGlowViolet,
                  active: listening,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TeacherCard extends StatelessWidget {
  const _TeacherCard({required this.controller});

  final LiveClassroomController controller;

  @override
  Widget build(BuildContext context) {
    final ConversationTurn? turn = controller.latestTeacherTurn;
    final bool live = controller.direction ==
            ConversationDirection.teacherToStudent &&
        (controller.state.isCapturing || controller.state.isBusy);

    final String status = switch (true) {
      _ when controller.state == ClassroomState.listening && live =>
        'Speaking…',
      _ when controller.state == ClassroomState.recognisingSpeech && live =>
        'Processing',
      _ when turn == null => 'Tap the microphone to begin',
      _ => 'Recognised',
    };

    return SpeakerCard(
      tint: AppColors.liveTeacher,
      icon: Icons.person_outline,
      title: 'Teacher — ${controller.context.teachingMedium.label}',
      status: status,
      trailing: live
          ? const _LiveBadge()
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: 34,
            child: LiveWaveform(
              amplitude: controller.amplitude,
              tint: AppColors.liveTeacher,
              barCount: 60,
              active: live,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Recognized Speech',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: AppColors.liveTextMuted,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Text(
                  // Whatever the recogniser actually heard. Nothing here is a
                  // fixed example sentence.
                  turn == null || turn.sourceText.isEmpty
                      ? 'Nothing yet.'
                      : turn.sourceText,
                  style: TextStyle(
                    fontSize: turn == null ? 15 : 21,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: turn == null
                        ? AppColors.liveTextMuted
                        : AppColors.liveTextPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              LiveSpeakButton(
                label: 'Play the recognised speech',
                tint: AppColors.liveTeacher,
                onPressed: turn == null || turn.sourceText.isEmpty
                    ? null
                    : () => controller.playTurn(turn.id),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.liveDanger),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.liveDanger,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'Live',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.liveDanger,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiCard extends StatelessWidget {
  const _AiCard({required this.controller});

  final LiveClassroomController controller;

  int get _stage => switch (controller.state) {
        ClassroomState.recognisingSpeech || ClassroomState.speechCaptured => 1,
        ClassroomState.translating => 2,
        ClassroomState.generatingAudio => 3,
        ClassroomState.audioReady || ClassroomState.playing => 4,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    final ConversationTurn? turn = controller.latestTeacherTurn;
    final String? translated = turn?.translatedText;
    final String targetLabel = controller.context.targetLanguage.label;

    final String status = switch (controller.state) {
      ClassroomState.translating => 'AI Processing',
      ClassroomState.generatingAudio => 'Preparing audio',
      ClassroomState.playing => 'Playing to the class',
      _ when translated == null => 'Waiting for speech',
      _ => 'Ready',
    };

    final bool playing = controller.state == ClassroomState.playing;

    return SpeakerCard(
      tint: AppColors.liveAi,
      icon: Icons.smart_toy_outlined,
      title: 'Translated to $targetLabel',
      status: status,
      statusIcon: Icons.auto_awesome,
      trailing: ProcessingDots(stage: _stage),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  translated ??
                      'The translation appears here once the teacher speaks.',
                  style: TextStyle(
                    fontSize: translated == null ? 14 : 21,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: translated == null
                        ? AppColors.liveTextMuted
                        : AppColors.liveAi,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              LiveSpeakButton(
                label: 'Play the $targetLabel translation',
                playing: playing,
                onPressed: translated == null
                    ? null
                    : controller.playToStudents,
              ),
            ],
          ),
          if (turn != null && turn.isLowConfidence) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.help_outline,
                  size: 15,
                  color: AppColors.liveTeacher,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Please verify — this translation has not been checked by '
                    'a $targetLabel speaker.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: AppColors.liveTeacher.withValues(alpha: 0.95),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: Semantics(
                  button: true,
                  enabled: translated != null,
                  label: 'Play the translation to the students',
                  child: ExcludeSemantics(
                    child: FilledButton.icon(
                      key: LiveClassroomScreen.playToStudentsKey,
                      onPressed: translated == null
                          ? null
                          : controller.playToStudents,
                      icon: Icon(
                        playing ? Icons.pause : Icons.play_arrow,
                        size: 22,
                      ),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          playing ? 'Playing…' : 'Play to Students',
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.liveAi,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.liveBorder,
                        disabledForegroundColor: AppColors.liveTextMuted,
                        minimumSize: const Size(0, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({required this.controller});

  final LiveClassroomController controller;

  @override
  Widget build(BuildContext context) {
    final ConversationTurn? turn = controller.latestStudentTurn;
    final bool live = controller.direction ==
            ConversationDirection.studentToTeacher &&
        (controller.state.isCapturing || controller.state.isBusy);

    final String status = switch (true) {
      _ when live && controller.state == ClassroomState.listening =>
        'Listening…',
      _ when live => 'Processing…',
      _ when turn?.translatedText != null => 'Translated',
      _ => 'Tap to let a child answer',
    };

    return SpeakerCard(
      tint: AppColors.liveStudent,
      icon: Icons.person_outline,
      title: 'Student Response',
      status: status,
      statusIcon: Icons.mic_none,
      trailing: SizedBox(
        width: 96,
        height: 34,
        child: LiveWaveform(
          amplitude: controller.amplitude,
          tint: AppColors.liveStudent,
          barCount: 30,
          active: live,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (turn != null) ...<Widget>[
            Text(
              turn.sourceText.isEmpty ? '…' : turn.sourceText,
              style: const TextStyle(
                fontSize: 16,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: AppColors.liveTextPrimary,
              ),
            ),
            if (turn.translatedText != null) ...<Widget>[
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      turn.translatedText!,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        color: AppColors.liveStudent,
                      ),
                    ),
                  ),
                  LiveSpeakButton(
                    label: 'Play the answer in '
                        '${controller.context.teachingMedium.label}',
                    tint: AppColors.liveStudent,
                    onPressed: () => controller.playTurn(turn.id),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
          ],
          Semantics(
            button: true,
            label: 'Let a student answer in '
                '${controller.context.targetLanguage.label}',
            child: ExcludeSemantics(
              child: OutlinedButton.icon(
                key: LiveClassroomScreen.studentTurnKey,
                onPressed: controller.muted ? null : controller.startStudentTurn,
                icon: const Icon(Icons.mic_none, size: 19),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    live
                        ? 'Stop listening'
                        : 'Student speaks '
                            '${controller.context.targetLanguage.label}',
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.liveStudent,
                  disabledForegroundColor: AppColors.liveTextMuted,
                  minimumSize: const Size(0, 46),
                  side: BorderSide(
                    color: AppColors.liveStudent.withValues(alpha: 0.5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.controller, required this.onClear});

  final LiveClassroomController controller;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final List<ConversationTurn> turns = controller.turns;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.liveCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.liveBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.history,
                size: 18,
                color: AppColors.liveTextMuted,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Live Conversation Timeline',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.liveTextPrimary,
                  ),
                ),
              ),
              Semantics(
                button: true,
                enabled: turns.isNotEmpty,
                label: 'Clear the conversation timeline',
                child: ExcludeSemantics(
                  child: TextButton.icon(
                    key: LiveClassroomScreen.clearTimelineKey,
                    onPressed: turns.isEmpty ? null : onClear,
                    icon: const Text(
                      'Clear',
                      style: TextStyle(fontSize: 13.5),
                    ),
                    label: const Icon(Icons.delete_outline, size: 18),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.liveTextMuted,
                      minimumSize: const Size(48, 40),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (turns.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'Nothing said yet. Tap the microphone to start the '
                'conversation.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: AppColors.liveTextMuted,
                ),
              ),
            )
          else
            for (final ConversationTurn turn in turns)
              _TimelineEntry(
                turn: turn,
                controller: controller,
              ),
        ],
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({required this.turn, required this.controller});

  final ConversationTurn turn;
  final LiveClassroomController controller;

  Color get _tint => switch (turn.speaker) {
        TurnSpeaker.teacher => AppColors.liveTeacher,
        TurnSpeaker.ai => AppColors.liveAi,
        TurnSpeaker.student => AppColors.liveStudent,
      };

  String get _languageLabel => turn.speaker == TurnSpeaker.teacher
      ? controller.context.teachingMedium.label
      : controller.context.targetLanguage.label;

  @override
  Widget build(BuildContext context) {
    final String time = TimeOfDay.fromDateTime(turn.timestamp).format(context);
    final bool hasTranslation = (turn.translatedText ?? '').isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: turn.status == TurnStatus.failed
                    ? AppColors.liveDanger
                    : _tint,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 11, 10, 12),
              decoration: BoxDecoration(
                color: AppColors.liveCardRaised,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _tint.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${turn.speaker.label} ($_languageLabel)',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: _tint,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        time,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.liveTextMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          turn.status == TurnStatus.failed
                              ? (turn.failureMessage ?? 'This turn failed.')
                              : (hasTranslation
                                  ? '${turn.sourceText}\n${turn.translatedText}'
                                  : (turn.sourceText.isEmpty
                                      ? 'Listening…'
                                      : turn.sourceText)),
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.35,
                            color: turn.status == TurnStatus.failed
                                ? AppColors.liveDanger
                                : AppColors.liveTextPrimary,
                          ),
                        ),
                      ),
                      if (hasTranslation) ...<Widget>[
                        const SizedBox(width: 8),
                        Semantics(
                          button: true,
                          label: 'Play this line',
                          child: ExcludeSemantics(
                            child: Material(
                              color: _tint,
                              shape: const CircleBorder(),
                              child: InkWell(
                                onTap: () => controller.playTurn(turn.id),
                                customBorder: const CircleBorder(),
                                child: const SizedBox(
                                  width: 34,
                                  height: 34,
                                  child: Icon(
                                    Icons.play_arrow,
                                    size: 19,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (turn.metrics != null) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      'Measured ${turn.metrics!.totalLabel}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.liveTextMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The failure banner, with a retry that resumes the stage that failed.
class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.controller});

  final LiveClassroomController controller;

  @override
  Widget build(BuildContext context) {
    final ConversationFailure failure = controller.failure!;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.liveDanger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.liveDanger.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.error_outline,
            size: 20,
            color: AppColors.liveDanger,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  failure.message,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: AppColors.liveTextPrimary,
                  ),
                ),
                Row(
                  children: <Widget>[
                    if (failure.retryable)
                      TextButton(
                        key: LiveClassroomScreen.retryKey,
                        onPressed: controller.retry,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.liveGlowCyan,
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
                    if (failure.permanentlyDenied)
                      TextButton(
                        onPressed: () => Navigator.of(context)
                            .pushNamed(AppRoutes.profile),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.liveGlowCyan,
                          minimumSize: const Size(48, 40),
                        ),
                        child: const Text('Open Settings'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: controller.dismissFailure,
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close, size: 18),
            color: AppColors.liveTextMuted,
          ),
        ],
      ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.controller,
    required this.ending,
    required this.onEnd,
  });

  final LiveClassroomController controller;
  final bool ending;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.liveBar,
        border: Border(
          top: BorderSide(color: AppColors.liveBorder),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: LiveControlButton(
                  key: LiveClassroomScreen.muteKey,
                  icon: controller.muted ? Icons.mic_off : Icons.mic_none,
                  label: controller.muted ? 'Muted' : 'Mute',
                  semanticLabel: controller.muted
                      ? 'Muted. Tap to unmute the microphone'
                      : 'Mute the microphone',
                  active: controller.muted,
                  tint: controller.muted ? AppColors.liveTeacher : null,
                  onPressed: controller.toggleMute,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: LiveControlButton(
                  key: LiveClassroomScreen.repeatKey,
                  icon: Icons.refresh,
                  label: 'Repeat Last',
                  semanticLabel: 'Repeat the last translation',
                  // Disabled rather than pretending: there is nothing to repeat
                  // until something has been said.
                  onPressed:
                      controller.hasPreviousAudio ? controller.repeatLast : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 4,
                child: LiveControlButton(
                  key: LiveClassroomScreen.endKey,
                  icon: Icons.call_end,
                  label: ending ? 'Ending…' : 'End Session',
                  semanticLabel: 'End the classroom session',
                  background: AppColors.liveDanger,
                  tint: Colors.white,
                  onPressed: ending ? null : onEnd,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when the route is opened with no lesson — a deep link, or a caller
/// that lost its arguments.
class _NoContext extends StatelessWidget {
  const _NoContext();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.groups_outlined,
              size: 38,
              color: AppColors.liveTextMuted,
            ),
            const SizedBox(height: 14),
            const Text(
              'No lesson was handed to this session.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.liveTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Start a live classroom from a lesson so it knows what to teach '
              'and in which language.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: AppColors.liveTextMuted,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.liveAi,
                minimumSize: const Size(0, 48),
              ),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}
