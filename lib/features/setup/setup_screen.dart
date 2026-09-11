import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/constants/app_assets.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/app_logger.dart';
import '../../services/connectivity/connectivity_service.dart';
import '../../services/storage/secure_storage_service.dart';
import '../auth/services/auth_session_store.dart';
import '../auth/widgets/login_chrome.dart';
import 'data/classroom_setup_storage.dart';
import 'data/location_data_source.dart';
import 'models/classroom_setup.dart';
import 'models/location.dart';
import 'models/offline_resource_status.dart';
import 'services/classroom_setup_repository.dart';
import '../../services/audio/language_audio_service.dart';
import 'services/offline_resource_manager.dart';
import 'services/setup_controller.dart';
import 'widgets/classroom_summary_card.dart';
import 'widgets/setup_selectors.dart';
import 'widgets/setup_widgets.dart';

/// Classroom configuration, shown after sign-in when setup is not yet complete
/// and reachable later from classroom settings.
///
/// The screen renders a [SetupController] and routes on its outcome; it holds
/// no storage, validation or resource logic of its own. Services are injectable
/// so tests can drive every branch without a database or a bundle.
class SetupScreen extends StatefulWidget {
  const SetupScreen({
    this.repository,
    this.locations,
    this.resources,
    this.audio,
    this.connectivityService,
    this.teacherId,
    super.key,
  });

  final ClassroomSetupRepository? repository;
  final LocationDataSource? locations;
  final OfflineResourceManager? resources;
  final LanguageAudioService? audio;
  final ConnectivityService? connectivityService;

  /// Normally read from the signed-in session; injectable for tests.
  final String? teacherId;

  static const Key schoolNameFieldKey = Key('setup.field.schoolName');
  static const Key districtFieldKey = Key('setup.field.district');
  static const Key blockFieldKey = Key('setup.field.block');
  static const Key mediumFieldKey = Key('setup.field.medium');

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  /// How long to wait for the signed-in teacher's id before giving up.
  ///
  /// Without a bound, an unresponsive keystore leaves the screen on a spinner
  /// forever. The id cannot be guessed — saving under the wrong key would file
  /// the classroom against the wrong teacher — so a timeout surfaces an error
  /// the teacher can retry rather than a silent fallback.
  static const Duration _sessionLookupTimeout = Duration(seconds: 5);

  SetupController? _controller;
  ConnectivityService? _ownedConnectivity;
  bool _sessionUnavailable = false;

  final TextEditingController _schoolName = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final Map<SetupField, GlobalKey> _fieldAnchors = <SetupField, GlobalKey>{
    for (final SetupField f in SetupField.values) f: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    _create();
  }

  Future<void> _create() async {
    String? teacherId = widget.teacherId;

    if (teacherId == null) {
      // The teacher is already known from sign-in, so setup never asks again.
      // This reads the same secure store the auth feature wrote to.
      final AuthSessionStore store =
          AuthSessionStore(PlatformSecureStorageService());
      try {
        teacherId = (await store
                .account()
                .timeout(_sessionLookupTimeout))
            ?.id;
      } on Object catch (error) {
        AppLogger.error('could not read the signed-in teacher', error: error);
        teacherId = null;
      }
    }

    if (!mounted) return;

    if (teacherId == null) {
      setState(() => _sessionUnavailable = true);
      return;
    }

    final ConnectivityService connectivity = widget.connectivityService ??
        (_ownedConnectivity = PlatformConnectivityService());

    final SetupController controller = SetupController(
      repository: widget.repository ??
          LocalClassroomSetupRepository(defaultClassroomSetupStorage()),
      locations: widget.locations ?? AssetLocationDataSource(),
      resources: widget.resources ?? const BundledOfflineResourceManager(),
      audio: widget.audio ?? const BundledLanguageAudioService(),
      connectivity: connectivity,
      teacherId: teacherId,
    );
    controller.addListener(_syncSchoolNameField);

    setState(() => _controller = controller);
  }

  /// Keeps the text field in step when a saved setup is loaded into the form.
  void _syncSchoolNameField() {
    final SetupController? c = _controller;
    if (c == null) return;
    if (_schoolName.text != c.schoolName && !_schoolName.selection.isValid) {
      _schoolName.text = c.schoolName;
    } else if (_schoolName.text.isEmpty && c.schoolName.isNotEmpty) {
      _schoolName.text = c.schoolName;
    }
  }

  @override
  void dispose() {
    _controller?..removeListener(_syncSchoolNameField)..dispose();
    _ownedConnectivity?.dispose();
    _schoolName.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _retryBootstrap() {
    setState(() => _sessionUnavailable = false);
    _create();
  }

  Future<void> _handleBack() async {
    final SetupController? c = _controller;
    if (c != null && c.hasUnsavedChanges) {
      final bool discard = await _confirmDiscard() ?? false;
      if (!discard) return;
    }
    if (!mounted) return;
    final NavigatorState navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      AppRouter.replaceWithFade(context, AppRoutes.auth);
    }
  }

  Future<bool?> _confirmDiscard() {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Discard your changes?'),
        content: const Text(
          'The classroom details you have entered have not been saved yet.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep Editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }

  Future<void> _finish() async {
    final SetupController c = _controller!;
    FocusScope.of(context).unfocus();

    final SetupSaveOutcome outcome = await c.finishSetup();
    if (!mounted) return;

    switch (outcome) {
      case SetupSaveOutcome.invalid:
        _scrollToFirstError();
      case SetupSaveOutcome.saveFailed:
        await _showSaveFailed();
      case SetupSaveOutcome.savedAndReady:
      case SetupSaveOutcome.savedResourcesPending:
      case SetupSaveOutcome.savedResourcesFailed:
        await AuthSessionStore(PlatformSecureStorageService())
            .setClassroomSetupComplete(complete: true);
        if (!mounted) return;
        _goHome();
    }
  }

  void _scrollToFirstError() {
    final SetupField? field = _controller?.firstInvalidField;
    final BuildContext? anchor = _fieldAnchors[field]?.currentContext;
    if (anchor == null) return;
    Scrollable.ensureVisible(
      anchor,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.15,
    );
  }

  Future<void> _showSaveFailed() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Setup not saved'),
        content: Text(
          _controller?.saveError ??
              'Your classroom setup could not be saved. Please try again.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _finish();
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.authNavy),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  void _goHome() => AppRouter.replaceWithFade(context, AppRoutes.home);

  @override
  Widget build(BuildContext context) {
    final SetupController? controller = _controller;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: <Widget>[
            const Positioned.fill(child: LoginBackdrop()),
            SafeArea(
              child: _sessionUnavailable
                  ? _SessionUnavailable(onRetry: _retryBootstrap)
                  : controller == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListenableBuilder(
                      listenable: controller,
                      builder: (BuildContext context, Widget? _) =>
                          _body(context, controller),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, SetupController c) {
    final double width = MediaQuery.sizeOf(context).width;
    final double contentWidth = width.clamp(0.0, 620.0);
    final double sidePad = ((width - contentWidth) / 2) + 18;

    if (c.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(
          sidePad,
          6,
          sidePad,
          MediaQuery.viewInsetsOf(context).bottom + 28,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Header(onBack: _handleBack),
            const SizedBox(height: 18),
            _TitleBlock(status: c.offlineStatus, connection: c.connectionStatus),
            const SizedBox(height: 26),
            _schoolSection(c),
            const SizedBox(height: 26),
            _languageSection(c),
            const SizedBox(height: 24),
            _mediumSection(c),
            const SizedBox(height: 24),
            _classSection(c),
            const SizedBox(height: 24),
            _subjectSection(c),
            const SizedBox(height: 22),
            ClassroomSummaryCard(
              summaryLine: c.summaryLine,
              detailLine: c.summaryDetail,
            ),
            const SizedBox(height: 20),
            FinishSetupButton(
              label: c.isEditing ? 'Save Changes' : 'Finish Setup',
              busy: c.saving,
              onPressed: c.isComplete ? _finish : null,
            ),
            if (!c.isComplete) ...<Widget>[
              const SizedBox(height: 10),
              Center(
                child: Text(
                  'Fill in school, district, block and at least one subject to '
                  'finish.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.brandNavy.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            const _BottomNote(),
          ],
        ),
      ),
    );
  }

  Widget _schoolSection(SetupController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SetupSectionHeader(step: 1, title: 'School'),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.authFieldBorder),
          ),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // The reference lays these three across one row. That only works
              // above roughly 520dp of card width; below it the placeholders
              // truncate, so they stack instead.
              final bool inRow = constraints.maxWidth >= 520;
              final List<Widget> fields = <Widget>[
                _schoolNameField(c),
                _districtField(c),
                _blockField(c),
              ];

              if (!inRow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    fields[0],
                    const SizedBox(height: 14),
                    fields[1],
                    const SizedBox(height: 14),
                    fields[2],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: fields[0]),
                  const SizedBox(width: 12),
                  Expanded(child: fields[1]),
                  const SizedBox(width: 12),
                  Expanded(child: fields[2]),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _schoolNameField(SetupController c) {
    final String? error = c.errorFor(SetupField.schoolName);
    return Column(
      key: _fieldAnchors[SetupField.schoolName],
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const FieldLabel('School Name'),
        const SizedBox(height: 8),
        FieldShell(
          hasError: error != null,
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.account_balance_outlined,
                size: 19,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: SetupScreen.schoolNameFieldKey,
                  controller: _schoolName,
                  onChanged: c.setSchoolName,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandNavy,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    hintText: 'Enter school name',
                    hintStyle: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w400,
                      color: AppColors.authHint,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (error != null) FieldError(error),
      ],
    );
  }

  Widget _districtField(SetupController c) {
    final String? error = c.errorFor(SetupField.district);
    return Column(
      key: _fieldAnchors[SetupField.district],
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const FieldLabel('District'),
        const SizedBox(height: 8),
        SetupDropdown<District>(
          key: SetupScreen.districtFieldKey,
          icon: Icons.location_on_outlined,
          hint: 'Select district',
          value: c.district,
          items: c.districts,
          labelOf: (District d) => d.name,
          hasError: error != null,
          semanticLabel: 'District',
          onChanged: c.selectDistrict,
        ),
        if (error != null) FieldError(error),
      ],
    );
  }

  Widget _blockField(SetupController c) {
    final String? error = c.errorFor(SetupField.block);
    final bool enabled = c.district != null;
    return Column(
      key: _fieldAnchors[SetupField.block],
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const FieldLabel('Block'),
        const SizedBox(height: 8),
        SetupDropdown<Block>(
          key: SetupScreen.blockFieldKey,
          icon: Icons.apartment_outlined,
          hint: 'Select block',
          value: c.block,
          items: c.availableBlocks,
          labelOf: (Block b) => b.name,
          enabled: enabled,
          hasError: error != null,
          semanticLabel: 'Block',
          onChanged: c.selectBlock,
        ),
        if (!enabled)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Select district first.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.brandNavy.withValues(alpha: 0.6),
              ),
            ),
          ),
        if (error != null) FieldError(error),
      ],
    );
  }

  Widget _languageSection(SetupController c) {
    return Column(
      key: _fieldAnchors[SetupField.targetLanguage],
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SetupSectionHeader(
          step: 2,
          title: 'Teaching Language',
          subtitle: 'Choose the tribal mother tongue you teach in.',
          trailing: PreviewListenButton(
            state: c.targetPreview,
            onPressed: c.previewTargetLanguage,
          ),
        ),
        const SizedBox(height: 14),
        TeachingLanguageCards(
          selected: c.targetLanguage,
          onSelected: c.selectTargetLanguage,
        ),
        if (c.targetPreview == PreviewState.unavailable &&
            c.previewMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _Notice(message: c.previewMessage!),
          ),
      ],
    );
  }

  Widget _mediumSection(SetupController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SetupSectionHeader(
          step: 3,
          title: 'Teaching Medium',
          subtitle: 'Select the language you teach in (spoken in class).',
          trailing: PreviewListenButton(
            state: c.mediumPreview,
            onPressed: c.previewTeachingMedium,
          ),
        ),
        const SizedBox(height: 14),
        SetupDropdown<TeachingMedium>(
          key: SetupScreen.mediumFieldKey,
          icon: Icons.translate,
          hint: 'Select teaching medium',
          value: c.teachingMedium,
          items: TeachingMedium.values,
          labelOf: (TeachingMedium m) => m.label,
          semanticLabel: 'Teaching medium',
          onChanged: (TeachingMedium? m) {
            if (m != null) c.selectTeachingMedium(m);
          },
        ),
      ],
    );
  }

  Widget _classSection(SetupController c) {
    final String? error = c.errorFor(SetupField.classLevel);
    return Column(
      key: _fieldAnchors[SetupField.classLevel],
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SetupSectionHeader(
          step: 4,
          title: 'Class',
          subtitle: 'Select the class you currently teach.',
        ),
        const SizedBox(height: 14),
        ClassSelector(selected: c.classLevel, onSelected: c.selectClass),
        if (error != null) FieldError(error),
      ],
    );
  }

  Widget _subjectSection(SetupController c) {
    final String? error = c.errorFor(SetupField.subjects);
    return Column(
      key: _fieldAnchors[SetupField.subjects],
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SetupSectionHeader(
          step: 5,
          title: 'Subjects',
          subtitle: 'Choose the subjects you want to focus on.',
        ),
        const SizedBox(height: 14),
        SubjectCards(selected: c.subjects, onToggle: c.toggleSubject),
        if (error != null) FieldError(error),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    // A Row rather than a fixed-height Stack: the lock-up's height depends on
    // the text scale, and a hard height clips it at large scales.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Semantics(
          button: true,
          label: 'Back',
          child: ExcludeSemantics(
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(
                side: BorderSide(color: AppColors.authFieldBorder),
              ),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onBack,
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(
                    Icons.arrow_back,
                    size: 21,
                    color: AppColors.brandNavy,
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Image.asset(
                    AppAssets.loginBrandMark,
                    height: 42,
                    filterQuality: FilterQuality.medium,
                    excludeFromSemantics: true,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text.rich(
                        TextSpan(
                          children: const <InlineSpan>[
                            TextSpan(
                              text: 'GyanSetu',
                              style: TextStyle(color: AppColors.brandNavy),
                            ),
                            TextSpan(text: ' '),
                            TextSpan(
                              text: 'AI',
                              style: TextStyle(color: AppColors.brandOrange),
                            ),
                          ],
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Bridging Languages. Building Futures.',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandNavy.withValues(alpha: 0.72),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Balances the back button so the lock-up stays optically centred.
        const SizedBox(width: 48),
      ],
    );
  }
}

/// Shown when the signed-in teacher could not be read, so the classroom cannot
/// safely be filed against anyone.
class _SessionUnavailable extends StatelessWidget {
  const _SessionUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.lock_outline, size: 38, color: AppColors.warning),
            const SizedBox(height: 14),
            const Text(
              'We could not read your sign-in on this device.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.brandNavy,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your classroom has to be saved against your account, so setup '
              'cannot continue without it.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.brandNavy.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onRetry,
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

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.status, required this.connection});

  final OfflineResourceStatus status;
  final ConnectionStatus connection;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Set up your classroom',
                style: TextStyle(
                  fontSize: 27,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: AppColors.brandNavy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tell us about your school and teaching preferences.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: AppColors.brandNavy.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 168),
          child: _OfflineStatusCard(status: status, connection: connection),
        ),
      ],
    );
  }
}

/// Reports what the device can actually do offline.
///
/// It never says "Offline-ready" on the strength of the form alone: that claim
/// requires the resource check to have found everything present.
class _OfflineStatusCard extends StatelessWidget {
  const _OfflineStatusCard({required this.status, required this.connection});

  final OfflineResourceStatus status;
  final ConnectionStatus connection;

  @override
  Widget build(BuildContext context) {
    final ({IconData icon, String title, String detail, Color tint}) c =
        switch (status.readiness) {
      OfflineReadiness.ready => (
          icon: Icons.cloud_done_outlined,
          title: 'Offline-ready',
          detail: 'Works without\ninternet after setup',
          tint: AppColors.success,
        ),
      OfflineReadiness.preparing => (
          icon: Icons.sync,
          title: 'Preparing',
          detail: 'Getting offline\naccess ready',
          tint: AppColors.brandMuted,
        ),
      OfflineReadiness.needsSync when connection == ConnectionStatus.online => (
          icon: Icons.cloud_sync_outlined,
          title: 'Online',
          detail: 'Resources ready\nto sync',
          tint: AppColors.info,
        ),
      OfflineReadiness.needsSync => (
          icon: Icons.cloud_off,
          title: 'Needs sync',
          detail: 'Offline resources\nnot on device yet',
          tint: AppColors.warning,
        ),
      OfflineReadiness.failed => (
          icon: Icons.error_outline,
          title: 'Check failed',
          detail: 'Could not read\nlocal resources',
          tint: AppColors.error,
        ),
      OfflineReadiness.unknown => (
          icon: Icons.cloud_queue,
          title: 'Checking',
          detail: 'Looking for offline\nresources',
          tint: AppColors.brandMuted,
        ),
    };

    return Semantics(
      liveRegion: true,
      label: '${c.title}. ${c.detail.replaceAll('\n', ' ')}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
          decoration: BoxDecoration(
            color: AppColors.authChip,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(c.icon, size: 16, color: c.tint),
                  const SizedBox(width: 6),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        c.title,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandNavy,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                c.detail,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                  color: AppColors.brandNavy.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(11),
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
        ],
      ),
    );
  }
}

class _BottomNote extends StatelessWidget {
  const _BottomNote();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.verified_user_outlined,
            size: 15,
            color: AppColors.authNavy.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'You can change these settings anytime from classroom settings.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: AppColors.brandNavy.withValues(alpha: 0.68),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
