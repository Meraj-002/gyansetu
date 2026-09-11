import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_settings.dart';
import '../../app/routes.dart';
import '../../core/constants/app_assets.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/app_logger.dart';
import '../../core/widgets/app_bottom_navigation.dart';
import '../../features/auth/models/teacher_account.dart';
import '../../features/auth/services/auth_session_store.dart';
import '../../features/auth/services/authentication_service.dart';
import '../../features/auth/services/fastapi_authentication_service.dart';
import '../../features/auth/services/offline_authentication_service.dart';
import '../../features/lessons/widgets/lesson_detail_widgets.dart';
import '../../features/profile/models/profile_settings.dart';
import '../../features/profile/models/support_report.dart';
import '../../features/profile/services/profile_settings_store.dart';
import '../../features/profile/services/support_report_store.dart';
import '../../features/profile/services/teacher_identity_repository.dart';
import '../../features/setup/data/location_data_source.dart';
import '../../features/setup/data/classroom_setup_storage.dart';
import '../../features/setup/models/classroom_setup.dart';
import '../../features/setup/models/location.dart';
import '../../features/setup/services/classroom_setup_repository.dart';
import '../../features/setup/widgets/setup_widgets.dart';
import '../../services/connectivity/connectivity_service.dart';
import '../../services/service_registry.dart';
import '../../services/storage/secure_storage_service.dart';

/// Mirrors `pubspec.yaml`'s `version: 1.0.0+1`. Kept in one place so the about
/// card and pubspec cannot drift silently.
const String kProfileAppVersion = '1.0.0';

/// The teacher's profile and settings hub.
///
/// Everything here reads and writes real local state: account and classroom
/// data through the existing session and repository services, preferences
/// through a small store over the app's persistent key-value channel, and the
/// connection banner from [ConnectivityService]. Nothing is decorative — every
/// toggle and save is persisted and re-read when the screen reopens.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    this.session,
    this.classrooms,
    this.storage,
    this.settingsStore,
    this.supportReports,
    this.locations,
    this.connectivity,
    this.identity,
    this.authentication,
    this.offline,
    super.key,
  });

  final AuthSessionStore? session;
  final ClassroomSetupRepository? classrooms;

  /// Backing store for the local implementations of [settingsStore] and
  /// [supportReports]; supplying [storage] is enough to run everything.
  final SecureStorageService? storage;

  final ProfileSettingsStore? settingsStore;
  final SupportReportStore? supportReports;
  final LocationDataSource? locations;
  final ConnectivityService? connectivity;

  /// Reads and writes canonical identity (account + classroom). When omitted,
  /// identity is device-local only — nothing is fetched over the network.
  final TeacherIdentityRepository? identity;

  /// Server-side account lifecycle, used by the sign-out action. Omitted means
  /// a server-backed service over the shared [ServiceRegistry] client.
  final AuthenticationService? authentication;

  /// Clears the device's offline account material on sign-out.
  final OfflineAuthenticationService? offline;

  static const Key screenKey = Key('profile-screen');
  static const Key backKey = Key('profile-back');
  static const Key themeToggleKey = Key('profile-theme-toggle');
  static const Key editButtonKey = Key('profile-edit');
  static const Key settingsLinkKey = Key('profile-link-settings');
  static const Key languageAudioLinkKey = Key('profile-link-language-audio');
  static const Key offlineStorageLinkKey = Key('profile-link-offline');
  static const Key accessibilityLinkKey = Key('profile-link-accessibility');
  static const Key supportLinkKey = Key('profile-link-support');

  static const Key editTeacherNameKey = Key('profile-edit-name');
  static const Key editSchoolKey = Key('profile-edit-school');
  static const Key editClassKey = Key('profile-edit-class');
  static const Key editMediumKey = Key('profile-edit-medium');
  static const Key editTargetKey = Key('profile-edit-target');
  static const Key editDistrictKey = Key('profile-edit-district');
  static const Key editBlockKey = Key('profile-edit-block');
  static const Key saveEditKey = Key('profile-edit-save');

  static const Key offlineLinkKey = Key('profile-offline-center-link');
  static const Key syncLinkKey = Key('profile-sync-link');

  static Key textSizeKey(TextSize value) =>
      Key('profile-text-size-${value.name}');
  static Key voiceSpeedKey(VoiceSpeed value) =>
      Key('profile-voice-speed-${value.name}');
  static Key pronunciationKey(PronunciationPreference value) =>
      Key('profile-pronunciation-${value.name}');
  static const Key contrastKey = Key('profile-high-contrast');
  static const Key audioKey = Key('profile-audio-assistance');
  static const Key translationLanguageKey = Key('profile-translation-language');

  static const Key helpKey = Key('profile-help');
  static const Key reportKey = Key('profile-report');
  static const Key contactKey = Key('profile-contact');
  static const Key reportFieldKey = Key('profile-report-field');
  static const Key reportSubmitKey = Key('profile-report-submit');

  static const Key classroomLinkKey = Key('profile-link-classroom');
  static const Key lessonsLinkKey = Key('profile-link-lessons');
  static const Key flashcardsLinkKey = Key('profile-link-flashcards');
  static const Key assessmentLinkKey = Key('profile-link-assessment');
  static const Key progressLinkKey = Key('profile-link-progress');
  static const Key resourcesLinkKey = Key('profile-link-resources');
  static const Key notificationsLinkKey = Key('profile-link-notifications');

  static const Key logoutButtonKey = Key('profile-logout');
  static const Key logoutConfirmKey = Key('profile-logout-confirm');

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

enum _ConnectionVisual { checking, online, offline }

class _ProfileScreenState extends State<ProfileScreen> {
  late final AuthSessionStore _session;
  late final ClassroomSetupRepository _classrooms;
  late final ProfileSettingsStore _settingsStore;
  late final SupportReportStore _supportReports;
  late final LocationDataSource _locations;
  late final ConnectivityService _connectivity;
  late final TeacherIdentityRepository _identity;
  late final AuthenticationService _authentication;
  late final OfflineAuthenticationService _offline;
  StreamSubscription<ConnectionStatus>? _connectionSubscription;

  TeacherAccount? _account;
  ClassroomSetup? _classroom;
  ProfileSettings _settings = const ProfileSettings();
  List<District> _districts = const <District>[];
  _ConnectionVisual _connection = _ConnectionVisual.checking;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final SecureStorageService storage =
        widget.storage ?? PlatformSecureStorageService();
    _session = widget.session ?? AuthSessionStore(storage);
    _classrooms =
        widget.classrooms ??
        LocalClassroomSetupRepository(defaultClassroomSetupStorage());
    _settingsStore =
        widget.settingsStore ??
        LocalProfileSettingsStore(
          widget.storage ?? PlatformSecureStorageService(),
        );
    _supportReports = widget.supportReports ?? LocalSupportReportStore(storage);
    _locations = widget.locations ?? AssetLocationDataSource();
    _connectivity = widget.connectivity ?? PlatformConnectivityService();
    _offline = widget.offline ?? OfflineAuthenticationService(store: _session);
    _authentication =
        widget.authentication ??
        FastApiAuthenticationService(
          api: ServiceRegistry.instance.api,
          offline: _offline,
          session: _session,
        );
    _identity =
        widget.identity ??
        LocalTeacherIdentityRepository(
          session: _session,
          classrooms: _classrooms,
        );
    _connection = _visualFor(_connectivity.status);

    _connectionSubscription = _connectivity.onStatusChanged.listen((_) {
      if (!mounted) return;
      setState(() {
        _connection = _visualFor(_connectivity.status);
      });
    });
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    if (widget.connectivity == null) {
      unawaited(_connectivity.dispose());
    }
    super.dispose();
  }

  static _ConnectionVisual _visualFor(ConnectionStatus status) =>
      switch (status) {
        ConnectionStatus.online => _ConnectionVisual.online,
        ConnectionStatus.offline => _ConnectionVisual.offline,
        ConnectionStatus.unknown => _ConnectionVisual.checking,
      };

  Future<void> _refresh({bool silent = false}) async {
    if (_busy) return;
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    _busy = true;
    try {
      final TeacherIdentity identity = await _identity.load();
      final TeacherAccount? account = identity.account;
      final ClassroomSetup? classroom = identity.classroom;
      final ProfileSettings settings = await _settingsStore.load();
      final List<District> districts = await _locations.districts();
      if (!mounted) return;
      setState(() {
        _account = account;
        _classroom = classroom;
        _settings = settings;
        _districts = districts;
        _loading = false;
        _error = null;
      });
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'profile load failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your profile on this device.';
      });
    } finally {
      _busy = false;
    }
  }

  // --- persistence actions (shared by the sheets) --------------------------

  Future<String?> _persistEdit(_EditProfileValues values) async {
    final String name = values.teacherName.trim();
    final String school = values.school.trim();
    if (name.isEmpty) return 'Enter the teacher name.';
    if (school.isEmpty) return 'Enter the school name.';

    final TeacherAccount? account = _account;
    if (account == null) return 'No device account found to save to.';
    if (!await _identity.updateDisplayName(name)) {
      return 'Could not save the teacher name. Please try again.';
    }

    final bool districtChanged =
        values.district != null &&
        values.district?.id != _classroom?.districtId;
    final String districtId =
        values.district?.id ?? _classroom?.districtId ?? '';
    final String districtName =
        values.district?.name ?? _classroom?.districtName ?? '—';
    final String blockId =
        values.block?.id ?? (districtChanged ? '' : _classroom?.blockId ?? '');
    final String blockName =
        values.block?.name ??
        (districtChanged ? '—' : _classroom?.blockName ?? '—');

    final ClassroomSetup? previous = _classroom;
    final ClassroomSetup next =
        (previous ??
                ClassroomSetup(
                  teacherId: account.id,
                  schoolName: school,
                  districtId: '',
                  districtName: '—',
                  blockId: '',
                  blockName: '—',
                  teachingMedium: values.medium,
                  targetLanguage: values.target,
                  classLevel: values.classLevel,
                  subjects: const <ClassroomSubject>{},
                  setupCompleted: false,
                ))
            .copyWith(
              schoolName: school,
              districtId: districtId,
              districtName: districtName,
              blockId: blockId,
              blockName: blockName,
              teachingMedium: values.medium,
              targetLanguage: values.target,
              classLevel: values.classLevel,
              pendingSync: true,
            );
    if (!await _classrooms.save(next)) {
      return 'Could not save the classroom details. Please try again.';
    }
    if (mounted) {
      setState(() {
        _account = account.copyWith(displayName: name);
        _classroom = next;
      });
    }
    return null;
  }

  Future<String?> _persistTargetLanguage(TargetLanguage target) async {
    final TeacherAccount? account = _account;
    final ClassroomSetup? previous = _classroom;
    if (account == null || previous == null) {
      return 'Complete classroom setup first.';
    }
    final ClassroomSetup next = previous.copyWith(
      targetLanguage: target,
      pendingSync: true,
    );
    if (!await _classrooms.save(next)) {
      return 'Could not save the translation language.';
    }
    if (mounted) {
      setState(() => _classroom = next);
    }
    return null;
  }

  Future<String?> _persistSettings(ProfileSettings next) async {
    if (!await _settingsStore.save(next)) {
      return 'Could not save your settings on this device.';
    }
    if (mounted) {
      setState(() => _settings = next);
    }
    return null;
  }

  Future<String?> _persistReport(String message) async {
    final String trimmed = message.trim();
    if (trimmed.isEmpty) return 'Describe the problem first.';
    final SupportReport report = SupportReport(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      message: trimmed,
      createdAt: DateTime.now(),
    );
    if (!await _supportReports.add(report)) {
      return 'Could not save the report on this device.';
    }
    return null;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // --- navigation helpers ---------------------------------------------------

  Future<void> _openEditProfile() async {
    final TeacherAccount? account = _account;
    final ClassroomSetup? classroom = _classroom;
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _EditProfileSheet(
        initialName: account?.displayName ?? 'Teacher',
        initialSchool: classroom?.schoolName ?? account?.schoolName ?? '',
        initialDistrict: _districtById(classroom?.districtId),
        initialBlock: _blockById(classroom?.blockId),
        initialClassLevel: classroom?.classLevel ?? 1,
        initialMedium: classroom?.teachingMedium ?? TeachingMedium.hindi,
        initialTarget: classroom?.targetLanguage ?? TargetLanguage.santali,
        districts: _districts,
        onSave: _persistEdit,
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      unawaited(_refresh(silent: true));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile updated.')));
    }
  }

  Future<void> _openLanguageAudio() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _LanguageAudioSheet(
        target: _classroom?.targetLanguage ?? TargetLanguage.santali,
        classroomUnset: _classroom == null,
        settings: _settings,
        onTarget: (TargetLanguage target) async {
          final String? error = await _persistTargetLanguage(target);
          if (error != null && mounted) _showError(error);
        },
        onSettings: (ProfileSettings next) async {
          final String? error = await _persistSettings(next);
          if (error != null && mounted) _showError(error);
        },
      ),
    );
  }

  void _openOfflineStorage() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _OfflineStorageSheet(
        onOfflineCenter: () {
          Navigator.of(sheetContext).pop();
          Navigator.of(context).pushNamed(AppRoutes.offline);
        },
        onSync: () {
          Navigator.of(sheetContext).pop();
          Navigator.of(context).pushNamed(AppRoutes.sync);
        },
      ),
    );
  }

  Future<void> _openAccessibility() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _AccessibilitySheet(
        settings: _settings,
        onSettings: (ProfileSettings next) async {
          final String? error = await _persistSettings(next);
          if (!mounted) return;
          context.read<AppSettings>().applyAccessibility(
            textScale: next.textScaleFactor,
            highContrast: next.highContrast,
          );
          if (error != null) _showError(error);
        },
      ),
    );
  }

  void _openSupport() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _SupportSheet(
        onHelp: () => _openHelp(sheetContext),
        onReport: () => _openReport(sheetContext),
        onContact: () => _openContact(sheetContext),
      ),
    );
  }

  void _openHelp(BuildContext anchor) {
    showModalBottomSheet<void>(
      context: anchor,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext _) => const _HelpSheet(),
    );
  }

  void _openReport(BuildContext anchor) {
    showModalBottomSheet<bool>(
      context: anchor,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) =>
          _ReportSheet(onSave: _persistReport),
    ).then((bool? saved) {
      if (saved == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Report saved on this device. It will be sent when you are online.',
            ),
          ),
        );
      }
    });
  }

  void _openContact(BuildContext anchor) {
    showModalBottomSheet<void>(
      context: anchor,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext _) => const _ContactSheet(),
    );
  }

  District? _districtById(String? id) {
    for (final District d in _districts) {
      if (d.id == id) return d;
    }
    return null;
  }

  Block? _blockById(String? id) {
    for (final District d in _districts) {
      final Block? block = d.blockById(id);
      if (block != null) return block;
    }
    return null;
  }

  void _openRoute(String route) => Navigator.of(context).pushNamed(route);

  /// Signs out per the privacy contract: the server session is dropped (the
  /// token is cleared, the server has nothing to revoke for a stateless JWT),
  /// and every piece of offline sign-in material for this device is removed.
  Future<void> _logout() async {
    final TeacherAccount? account = _account;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'This removes the account and offline sign-in material from this '
          'device. Work saved locally stays until you sign back in.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: ProfileScreen.logoutConfirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _authentication.signOut();
    await _offline.forgetDevice();
    if (account != null) {
      await _classrooms.clear(account.id);
    }
    if (!mounted) return;
    await AppRouter.replaceWithFade(context, AppRoutes.auth);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: ProfileScreen.screenKey,
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: <Widget>[
                  _ProfileHeader(
                    onBack: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(height: 10),
                  if (_loading && _account == null)
                    const _LoadingBody()
                  else ...<Widget>[
                    if (_error != null)
                      _InlineError(message: _error!, onRetry: _refresh),
                    _TeacherCard(
                      account: _account,
                      classroom: _classroom,
                      onEdit: _openEditProfile,
                    ),
                    const SizedBox(height: 14),
                    _OfflineStatusCard(connection: _connection),
                    const SizedBox(height: 22),
                    _SectionToolbar(title: 'Settings'),
                    const SizedBox(height: 12),
                    _buildSettings(),
                    const SizedBox(height: 22),
                    const _SectionToolbar(title: 'Teaching Tools'),
                    const SizedBox(height: 12),
                    _FeatureHub(onOpen: _openRoute),
                    const SizedBox(height: 26),
                    _AppAbout(onLogout: _logout),
                  ],
                ],
              ),
            ),
            const AppBottomNavigation(current: AppDestination.profile),
          ],
        ),
      ),
    );
  }

  Widget _buildSettings() {
    return Column(
      children: <Widget>[
        SectionCard(
          key: ProfileScreen.settingsLinkKey,
          icon: Icons.class_outlined,
          title: 'Classroom Settings',
          subtitle: 'Class & Subjects • Teaching Language • Student Groups',
          tint: _kSectionPurple,
          background: _kSectionPurple.withValues(alpha: 0.07),
          onTap: () => _openRoute(AppRoutes.setup),
        ),
        const SizedBox(height: 12),
        SectionCard(
          key: ProfileScreen.languageAudioLinkKey,
          icon: Icons.record_voice_over_outlined,
          title: 'Language & Audio',
          subtitle: 'Translation Language • Voice Speed • Pronunciation',
          tint: AppColors.success,
          background: AppColors.success.withValues(alpha: 0.08),
          onTap: _openLanguageAudio,
        ),
        const SizedBox(height: 12),
        SectionCard(
          key: ProfileScreen.offlineStorageLinkKey,
          icon: Icons.offline_pin_outlined,
          title: 'Offline & Storage',
          subtitle: 'Downloaded Content • Storage Usage • Sync Settings',
          tint: AppColors.info,
          background: AppColors.info.withValues(alpha: 0.08),
          onTap: _openOfflineStorage,
        ),
        const SizedBox(height: 12),
        SectionCard(
          key: ProfileScreen.accessibilityLinkKey,
          icon: Icons.accessible_forward_outlined,
          title: 'Accessibility',
          subtitle: 'Text Size • High Contrast • Audio Assistance',
          tint: AppColors.brandOrange,
          background: AppColors.brandOrange.withValues(alpha: 0.08),
          onTap: _openAccessibility,
        ),
        const SizedBox(height: 12),
        SectionCard(
          key: ProfileScreen.supportLinkKey,
          icon: Icons.support_agent_outlined,
          title: 'Support',
          subtitle: 'Help Center • Report Translation Issue • Contact Support',
          tint: AppColors.error,
          background: AppColors.error.withValues(alpha: 0.07),
          onTap: _openSupport,
        ),
      ],
    );
  }
}

const Color _kSectionPurple = Color(0xFF6C4AC1);

// --- header ----------------------------------------------------------------

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: <Widget>[
        Semantics(
          button: true,
          label: 'Back',
          child: ExcludeSemantics(
            child: InkWell(
              key: ProfileScreen.backKey,
              onTap: onBack,
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 20,
                  color: AppColors.brandNavy,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Image.asset(
          AppAssets.loginBrandMark,
          height: 36,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
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
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ),
        Semantics(
          button: true,
          label: isDark ? 'Switch to light theme' : 'Switch to dark theme',
          child: ExcludeSemantics(
            child: IconButton(
              key: ProfileScreen.themeToggleKey,
              tooltip: isDark ? 'Light theme' : 'Dark theme',
              onPressed: () {
                final AppSettings settings = context.read<AppSettings>();
                settings.setThemeMode(
                  isDark ? ThemeMode.light : ThemeMode.dark,
                );
              },
              icon: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                size: 24,
                color: AppColors.brandNavy,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 360,
      child: Center(
        child: CircularProgressIndicator(color: AppColors.brandNavy),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline, size: 20, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.error,
              ),
            ),
          ),
          TextButton(
            onPressed: () => onRetry(),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

// --- teacher card -----------------------------------------------------------

class _TeacherCard extends StatelessWidget {
  const _TeacherCard({
    required this.account,
    required this.classroom,
    required this.onEdit,
  });

  final TeacherAccount? account;
  final ClassroomSetup? classroom;
  final VoidCallback onEdit;

  String get _name => account?.displayName ?? 'Teacher';
  String get _school => classroom?.schoolName.isNotEmpty == true
      ? classroom!.schoolName
      : (account?.schoolName ?? '');

  @override
  Widget build(BuildContext context) {
    final ClassroomSetup? room = classroom;
    final String location = room == null || room.districtName == '—'
        ? room?.districtName ?? ''
        : <String>[
            room.districtName,
            if (room.blockName.isNotEmpty && room.blockName != '—')
              room.blockName,
          ].join(' • ');

    return Semantics(
      label:
          '$_name, Primary Teacher at $_school. Class ${room?.classLevel ?? '—'}, '
          'teaching ${room?.teachingMedium.label ?? '—'} to ${room?.targetLanguage.label ?? '—'}.',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.authFieldBorder),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.brandCreamWarm,
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 34,
                      color: AppColors.brandOrange,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _name,
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AppColors.brandNavy,
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Primary Teacher',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brandOrange.withValues(
                                alpha: 0.95,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  TextButton.icon(
                    key: ProfileScreen.editButtonKey,
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: const Text(
                      'Edit',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.brandNavy,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              if (_school.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                _MetaLine(icon: Icons.school_outlined, text: _school),
              ],
              if (location.isNotEmpty) ...<Widget>[
                const SizedBox(height: 7),
                _MetaLine(icon: Icons.location_on_outlined, text: location),
              ],
              const SizedBox(height: 14),
              Container(height: 1, color: AppColors.authFieldBorder),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _ProfileStat(
                    label: 'CLASS',
                    value: room == null ? '—' : 'Class ${room.classLevel}',
                  ),
                  _ProfileStat(
                    label: 'TEACHING',
                    value: room?.teachingMedium.label ?? '—',
                  ),
                  _ProfileStat(
                    label: 'TARGET',
                    value: room?.targetLanguage.label ?? '—',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 15, color: AppColors.brandNavy.withValues(alpha: 0.7)),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.brandNavy.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.brandOrange,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppColors.brandNavy,
            ),
          ),
        ],
      ),
    );
  }
}

// --- offline banner -----------------------------------------------------------

class _OfflineStatusCard extends StatelessWidget {
  const _OfflineStatusCard({required this.connection});

  final _ConnectionVisual connection;

  @override
  Widget build(BuildContext context) {
    const Color offlineTint = AppColors.success;
    switch (connection) {
      case _ConnectionVisual.checking:
        return _banner(
          tint: AppColors.brandMuted,
          icon: null,
          title: 'Checking connection…',
          body: 'Looking at how this device can reach the network.',
          trailing: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColors.brandNavy,
            ),
          ),
        );
      case _ConnectionVisual.online:
        return _banner(
          tint: AppColors.info,
          icon: Icons.cloud_done_outlined,
          title: 'You are Online',
          body:
              'Translation and speech can reach the network. '
              'Everything here still works offline.',
          trailing: null,
        );
      case _ConnectionVisual.offline:
        return _banner(
          tint: offlineTint,
          icon: Icons.wifi_off_rounded,
          title: 'You are in Offline Mode',
          body: 'All core features are available offline.',
          trailing: _Pill(label: 'Offline AI Active', tint: offlineTint),
        );
    }
  }

  Widget _banner({
    required Color tint,
    required IconData? icon,
    required String title,
    required String body,
    required Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: icon == null
                ? const SizedBox.shrink()
                : Icon(icon, size: 21, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: AppColors.brandNavy.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ?trailing,
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.tint});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: tint.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: tint,
        ),
      ),
    );
  }
}

// --- section & hub -----------------------------------------------------------

class _SectionToolbar extends StatelessWidget {
  const _SectionToolbar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.brandOrange,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
            color: AppColors.brandNavy,
          ),
        ),
      ],
    );
  }
}

class _FeatureHub extends StatelessWidget {
  const _FeatureHub({required this.onOpen});

  final void Function(String route) onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Column(
        children: <Widget>[
          _FeatureRow(
            key: ProfileScreen.classroomLinkKey,
            icon: Icons.groups_outlined,
            title: 'Classroom',
            subtitle: 'My classes & student groups',
            onTap: () => onOpen(AppRoutes.classroom),
          ),
          _divider(),
          _FeatureRow(
            key: ProfileScreen.lessonsLinkKey,
            icon: Icons.menu_book_outlined,
            title: 'Lesson Library',
            subtitle: 'Teaching plans for every class',
            onTap: () => onOpen(AppRoutes.lessons),
          ),
          _divider(),
          _FeatureRow(
            key: ProfileScreen.flashcardsLinkKey,
            icon: Icons.style_outlined,
            title: 'Flashcards',
            subtitle: 'Vocabulary practice cards',
            onTap: () => onOpen(AppRoutes.flashcards),
          ),
          _divider(),
          _FeatureRow(
            key: ProfileScreen.assessmentLinkKey,
            icon: Icons.quiz_outlined,
            title: 'Assessment',
            subtitle: 'End-of-lesson checks',
            onTap: () => onOpen(AppRoutes.assessment),
          ),
          _divider(),
          _FeatureRow(
            key: ProfileScreen.progressLinkKey,
            icon: Icons.insights_outlined,
            title: 'Learning Insights',
            subtitle: 'Your classroom’s learning records',
            onTap: () => onOpen(AppRoutes.progress),
          ),
          _divider(),
          _FeatureRow(
            key: ProfileScreen.resourcesLinkKey,
            icon: Icons.folder_open_outlined,
            title: 'Resources',
            subtitle: 'Extra material for your classroom',
            onTap: () => onOpen(AppRoutes.resources),
          ),
          _divider(),
          _FeatureRow(
            key: ProfileScreen.notificationsLinkKey,
            icon: Icons.notifications_none_rounded,
            title: 'Notifications',
            subtitle: 'Announcements for your school',
            onTap: () => onOpen(AppRoutes.notifications),
          ),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(
    height: 1,
    indent: 58,
    endIndent: 10,
    color: AppColors.authFieldBorder,
  );
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.brandCreamWarm,
                  ),
                  child: Icon(icon, size: 20, color: AppColors.brandOrange),
                ),
                const SizedBox(width: 13),
                Expanded(
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
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.brandNavy.withValues(alpha: 0.66),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 22,
                  color: AppColors.brandNavy.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- about ---------------------------------------------------------------

class _AppAbout extends StatelessWidget {
  const _AppAbout({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Image.asset(
          AppAssets.brandMark,
          height: 34,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
        ),
        const SizedBox(height: 8),
        Text(
          AppStrings.appName,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.brandNavy,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Bridging Languages. Building Futures.',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.brandNavy.withValues(alpha: 0.66),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Version $kProfileAppVersion • Offline First',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.brandNavy,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          '© 2025 ${AppStrings.appName}',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: AppColors.brandNavy),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: ProfileScreen.logoutButtonKey,
            onPressed: onLogout,
            icon: const Icon(Icons.logout, size: 17),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: BorderSide(
                color: AppColors.error.withValues(alpha: 0.5),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}

// --- edit profile ------------------------------------------------------------

/// The editable subset of a teacher's profile.
class _EditProfileValues {
  const _EditProfileValues({
    required this.teacherName,
    required this.school,
    required this.district,
    required this.block,
    required this.classLevel,
    required this.medium,
    required this.target,
  });

  final String teacherName;
  final String school;
  final District? district;
  final Block? block;
  final int classLevel;
  final TeachingMedium medium;
  final TargetLanguage target;
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({
    required this.initialName,
    required this.initialSchool,
    required this.initialDistrict,
    required this.initialBlock,
    required this.initialClassLevel,
    required this.initialMedium,
    required this.initialTarget,
    required this.districts,
    required this.onSave,
  });

  final String initialName;
  final String initialSchool;
  final District? initialDistrict;
  final Block? initialBlock;
  final int initialClassLevel;
  final TeachingMedium initialMedium;
  final TargetLanguage initialTarget;
  final List<District> districts;

  /// Persists the values; returns null on success or the error to show inline.
  final Future<String?> Function(_EditProfileValues values) onSave;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _name;
  late final TextEditingController _school;
  District? _district;
  Block? _block;
  late int _classLevel;
  late TeachingMedium _medium;
  late TargetLanguage _target;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _school = TextEditingController(text: widget.initialSchool);

    District? matchedDistrict;
    for (final District d in widget.districts) {
      if (d.id == widget.initialDistrict?.id) {
        matchedDistrict = d;
        break;
      }
    }
    _district = matchedDistrict;
    _block = matchedDistrict?.blockById(widget.initialBlock?.id);
    _classLevel = widget.initialClassLevel;
    _medium = widget.initialMedium;
    _target = widget.initialTarget;
  }

  @override
  void dispose() {
    _name.dispose();
    _school.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String? error = await widget.onSave(
      _EditProfileValues(
        teacherName: _name.text,
        school: _school.text,
        district: _district,
        block: _block,
        classLevel: _classLevel,
        medium: _medium,
        target: _target,
      ),
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final List<Block> blocks = _district?.blocks ?? const <Block>[];
    return SizedBox(
      width: MediaQuery.sizeOf(context).width,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'Edit Profile',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Changes are saved on this device.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.brandNavy.withValues(alpha: 0.66),
                ),
              ),
              const SizedBox(height: 18),
              const FieldLabel('Teacher name'),
              const SizedBox(height: 8),
              TextField(
                key: ProfileScreen.editTeacherNameKey,
                controller: _name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandNavy,
                ),
                decoration: const InputDecoration(
                  hintText: 'Teacher name',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: AppColors.authFieldBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: AppColors.authFieldBorder),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const FieldLabel('School name'),
              const SizedBox(height: 8),
              TextField(
                key: ProfileScreen.editSchoolKey,
                controller: _school,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandNavy,
                ),
                decoration: const InputDecoration(
                  hintText: 'School name',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: AppColors.authFieldBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: AppColors.authFieldBorder),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const FieldLabel('District'),
              const SizedBox(height: 8),
              SetupDropdown<District>(
                key: ProfileScreen.editDistrictKey,
                icon: Icons.location_on_outlined,
                hint: 'Select district',
                value: _district,
                items: widget.districts,
                labelOf: (District d) => d.name,
                semanticLabel: 'District',
                onChanged: (District? value) {
                  setState(() {
                    _district = value;
                    _block = null;
                  });
                },
              ),
              const SizedBox(height: 14),
              const FieldLabel('Block'),
              const SizedBox(height: 8),
              SetupDropdown<Block>(
                key: ProfileScreen.editBlockKey,
                icon: Icons.apartment_outlined,
                hint: 'Select block',
                value: _block,
                items: blocks,
                labelOf: (Block b) => b.name,
                enabled: _district != null,
                semanticLabel: 'Block',
                onChanged: (Block? value) => setState(() => _block = value),
              ),
              if (_district == null)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Select district first.',
                    style: TextStyle(fontSize: 12, color: AppColors.brandNavy),
                  ),
                ),
              const SizedBox(height: 14),
              const FieldLabel('Class'),
              const SizedBox(height: 8),
              SetupDropdown<int>(
                key: ProfileScreen.editClassKey,
                icon: Icons.class_outlined,
                hint: 'Select class',
                value: _classLevel,
                items: kSupportedClasses,
                labelOf: (int c) => 'Class $c',
                semanticLabel: 'Class',
                onChanged: (int? value) {
                  if (value != null) setState(() => _classLevel = value);
                },
              ),
              const SizedBox(height: 14),
              const FieldLabel('Teaching language'),
              const SizedBox(height: 8),
              SetupDropdown<TeachingMedium>(
                key: ProfileScreen.editMediumKey,
                icon: Icons.record_voice_over_outlined,
                hint: 'Teaching language',
                value: _medium,
                items: TeachingMedium.values,
                labelOf: (TeachingMedium m) => m.label,
                semanticLabel: 'Teaching language',
                onChanged: (TeachingMedium? value) {
                  if (value != null) setState(() => _medium = value);
                },
              ),
              const SizedBox(height: 14),
              const FieldLabel('Target language'),
              const SizedBox(height: 8),
              SetupDropdown<TargetLanguage>(
                key: ProfileScreen.editTargetKey,
                icon: Icons.translate_outlined,
                hint: 'Target language',
                value: _target,
                items: TargetLanguage.values,
                labelOf: (TargetLanguage t) => t.label,
                semanticLabel: 'Target language',
                onChanged: (TargetLanguage? value) {
                  if (value != null) setState(() => _target = value);
                },
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 10),
                FieldError(_error!),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: ProfileScreen.saveEditKey,
                    onPressed: _saving
                        ? null
                        : () {
                            setState(() {
                              _saving = true;
                              _error = null;
                            });
                            _save();
                          },
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(_saving ? 'Saving…' : 'Save'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandNavy,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- language & audio ---------------------------------------------------------

class _LanguageAudioSheet extends StatefulWidget {
  const _LanguageAudioSheet({
    required this.target,
    required this.classroomUnset,
    required this.settings,
    required this.onTarget,
    required this.onSettings,
  });

  final TargetLanguage target;
  final bool classroomUnset;
  final ProfileSettings settings;
  final ValueChanged<TargetLanguage> onTarget;
  final ValueChanged<ProfileSettings> onSettings;

  @override
  State<_LanguageAudioSheet> createState() => _LanguageAudioSheetState();
}

class _LanguageAudioSheetState extends State<_LanguageAudioSheet> {
  late TargetLanguage _target;
  ProfileSettings? _settings;

  @override
  void initState() {
    super.initState();
    _target = widget.target;
    _settings = widget.settings;
  }

  void _update(ProfileSettings next) {
    setState(() => _settings = next);
    widget.onSettings(next);
  }

  @override
  Widget build(BuildContext context) {
    final ProfileSettings settings = _settings ?? widget.settings;
    return SizedBox(
      width: MediaQuery.sizeOf(context).width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'Language & Audio',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'What the translator speaks and how it speaks it.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.brandNavy.withValues(alpha: 0.66),
                ),
              ),
              const SizedBox(height: 18),
              const FieldLabel('Translation language'),
              const SizedBox(height: 8),
              SetupDropdown<TargetLanguage>(
                key: ProfileScreen.translationLanguageKey,
                icon: Icons.translate_outlined,
                hint: 'Translation language',
                value: _target,
                items: TargetLanguage.values,
                labelOf: (TargetLanguage t) => t.label,
                enabled: !widget.classroomUnset,
                semanticLabel: widget.classroomUnset
                    ? 'Complete classroom setup first'
                    : 'Translation language',
                onChanged: (TargetLanguage? value) {
                  if (value == null) return;
                  setState(() => _target = value);
                  widget.onTarget(value);
                },
              ),
              if (widget.classroomUnset)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Complete classroom setup first.',
                    style: TextStyle(fontSize: 12, color: AppColors.brandNavy),
                  ),
                ),
              const SizedBox(height: 20),
              const _SettingLabel(
                icon: Icons.speed,
                title: 'Voice Speed',
                subtitle: 'How fast phrases are read aloud.',
              ),
              const SizedBox(height: 10),
              _ChoiceChips<VoiceSpeed>(
                values: VoiceSpeed.values,
                selected: settings.voiceSpeed,
                keyOf: ProfileScreen.voiceSpeedKey,
                onSelected: (VoiceSpeed v) =>
                    _update(settings.copyWith(voiceSpeed: v)),
              ),
              const SizedBox(height: 22),
              const _SettingLabel(
                icon: Icons.record_voice_over_outlined,
                title: 'Pronunciation',
                subtitle: 'Clear gives new words a slower, patient reading.',
              ),
              const SizedBox(height: 10),
              _ChoiceChips<PronunciationPreference>(
                values: PronunciationPreference.values,
                selected: settings.pronunciation,
                keyOf: ProfileScreen.pronunciationKey,
                onSelected: (PronunciationPreference v) =>
                    _update(settings.copyWith(pronunciation: v)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingLabel extends StatelessWidget {
  const _SettingLabel({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title. $subtitle',
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: AppColors.success),
            ),
            const SizedBox(width: 11),
            Expanded(
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
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.3,
                      color: AppColors.brandNavy.withValues(alpha: 0.66),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceChips<T> extends StatelessWidget {
  const _ChoiceChips({
    required this.values,
    required this.selected,
    required this.keyOf,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final Key Function(T value) keyOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final T value in values)
          ChoiceChip(
            key: keyOf(value),
            label: Text(value is Object ? _labelOf(value) : value.toString()),
            selected: value == selected,
            onSelected: (_) => onSelected(value),
            selectedColor: AppColors.brandNavy,
            backgroundColor: Colors.white,
            side: BorderSide(
              color: value == selected
                  ? AppColors.brandNavy
                  : AppColors.authFieldBorder,
            ),
            labelStyle: TextStyle(
              fontSize: 13,
              fontWeight: value == selected ? FontWeight.w800 : FontWeight.w600,
              color: value == selected ? Colors.white : AppColors.brandNavy,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
      ],
    );
  }

  static String _labelOf(Object value) {
    switch (value) {
      case final TextSize v:
        return v.label;
      case final VoiceSpeed v:
        return v.label;
      case final PronunciationPreference v:
        return v.label;
    }
    return value.toString();
  }
}

// --- offline & storage ---------------------------------------------------------

class _OfflineStorageSheet extends StatelessWidget {
  const _OfflineStorageSheet({
    required this.onOfflineCenter,
    required this.onSync,
  });

  final VoidCallback onOfflineCenter;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Offline & Storage',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.brandNavy,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'What is on this device, and how it stays in step.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.brandNavy.withValues(alpha: 0.66),
            ),
          ),
          const SizedBox(height: 14),
          _SheetActionRow(
            key: ProfileScreen.offlineLinkKey,
            icon: Icons.inventory_2_outlined,
            title: 'Offline Center',
            subtitle: 'Downloaded lessons, packs and resources on this device',
            tint: AppColors.info,
            onTap: onOfflineCenter,
          ),
          const SizedBox(height: 10),
          _SheetActionRow(
            key: ProfileScreen.syncLinkKey,
            icon: Icons.sync_outlined,
            title: 'Content Sync',
            subtitle: 'Sync lessons and classroom data',
            tint: AppColors.success,
            onTap: onSync,
          ),
        ],
      ),
    );
  }
}

class _SheetActionRow extends StatelessWidget {
  const _SheetActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tint,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.authFieldBorder),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 20, color: tint),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
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
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: AppColors.brandNavy.withValues(alpha: 0.66),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 22,
                    color: AppColors.brandNavy.withValues(alpha: 0.45),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- accessibility -------------------------------------------------------------

class _AccessibilitySheet extends StatefulWidget {
  const _AccessibilitySheet({required this.settings, required this.onSettings});

  final ProfileSettings settings;
  final ValueChanged<ProfileSettings> onSettings;

  @override
  State<_AccessibilitySheet> createState() => _AccessibilitySheetState();
}

class _AccessibilitySheetState extends State<_AccessibilitySheet> {
  ProfileSettings? _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  void _update(ProfileSettings next) {
    setState(() => _settings = next);
    widget.onSettings(next);
  }

  @override
  Widget build(BuildContext context) {
    final ProfileSettings settings = _settings ?? widget.settings;
    return SizedBox(
      width: MediaQuery.sizeOf(context).width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'Accessibility',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Applied across the app as soon as you change them.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.brandNavy.withValues(alpha: 0.66),
                ),
              ),
              const SizedBox(height: 18),
              const _SettingLabel(
                icon: Icons.text_fields,
                title: 'Text Size',
                subtitle: 'How large the letters everywhere appear.',
              ),
              const SizedBox(height: 10),
              _ChoiceChips<TextSize>(
                values: TextSize.values,
                selected: settings.textSize,
                keyOf: ProfileScreen.textSizeKey,
                onSelected: (TextSize v) =>
                    _update(settings.copyWith(textSize: v)),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                key: ProfileScreen.contrastKey,
                value: settings.highContrast,
                onChanged: (bool value) =>
                    _update(settings.copyWith(highContrast: value)),
                activeTrackColor: AppColors.brandOrange,
                title: const Text(
                  'High Contrast',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                ),
                subtitle: Text(
                  'Maximises text and background contrast.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.brandNavy.withValues(alpha: 0.66),
                  ),
                ),
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              SwitchListTile(
                key: ProfileScreen.audioKey,
                value: settings.audioAssistance,
                onChanged: (bool value) =>
                    _update(settings.copyWith(audioAssistance: value)),
                activeTrackColor: AppColors.brandOrange,
                title: const Text(
                  'Audio Assistance',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                ),
                subtitle: Text(
                  'Read teaching material aloud whenever it can be spoken.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.brandNavy.withValues(alpha: 0.66),
                  ),
                ),
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- support --------------------------------------------------------------------

class _SupportSheet extends StatelessWidget {
  const _SupportSheet({
    required this.onHelp,
    required this.onReport,
    required this.onContact,
  });

  final VoidCallback onHelp;
  final VoidCallback onReport;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Support',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.brandNavy,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Help that works even with no network.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.brandNavy.withValues(alpha: 0.66),
            ),
          ),
          const SizedBox(height: 14),
          _SheetActionRow(
            key: ProfileScreen.helpKey,
            icon: Icons.help_outline,
            title: 'Help Center',
            subtitle: 'How to use GyanSetu AI offline',
            tint: AppColors.info,
            onTap: onHelp,
          ),
          const SizedBox(height: 10),
          _SheetActionRow(
            key: ProfileScreen.reportKey,
            icon: Icons.flag_outlined,
            title: 'Report Translation Issue',
            subtitle: 'Saved on this device until you are online',
            tint: AppColors.error,
            onTap: onReport,
          ),
          const SizedBox(height: 10),
          _SheetActionRow(
            key: ProfileScreen.contactKey,
            icon: Icons.contact_support_outlined,
            title: 'Contact Support',
            subtitle: 'Who to speak to at school level',
            tint: AppColors.brandOrange,
            onTap: onContact,
          ),
        ],
      ),
    );
  }
}

class _HelpSheet extends StatelessWidget {
  const _HelpSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Help Center',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.brandNavy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'The whole app is built for zero-network classrooms.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.brandNavy.withValues(alpha: 0.66),
            ),
          ),
          const SizedBox(height: 16),
          for (final String line in const <String>[
            'Lessons, flashcards, worksheets and assessments work with no internet.',
            'The offline AI translates between your teaching language and the tribal language on the device.',
            'Offline Center & Content Sync live in Settings → Offline & Storage.',
            'Your classroom and teaching language are set in Settings → Classroom Settings.',
            'Translation issues can be reported in Settings → Support, even offline.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: AppColors.brandNavy.withValues(alpha: 0.86),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.onSave});

  final Future<String?> Function(String message) onSave;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String? error = await widget.onSave(_controller.text);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.sizeOf(context).width,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'Report Translation Issue',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Describe what was translated wrongly below. The report is '
                'kept on this device and sent when you are online.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AppColors.brandNavy.withValues(alpha: 0.66),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: ProfileScreen.reportFieldKey,
                controller: _controller,
                maxLines: 5,
                maxLength: 500,
                style: const TextStyle(
                  fontSize: 14.5,
                  color: AppColors.brandNavy,
                ),
                decoration: const InputDecoration(
                  hintText:
                      'For example: “On the flashcard for ‘seed’, the '
                      'Santali word sounds wrong.”',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: AppColors.authFieldBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: AppColors.authFieldBorder),
                  ),
                ),
              ),
              if (_error != null) FieldError(_error!),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: ProfileScreen.reportSubmitKey,
                    onPressed: _saving
                        ? null
                        : () {
                            setState(() {
                              _saving = true;
                              _error = null;
                            });
                            _submit();
                          },
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_outlined, size: 18),
                    label: Text(_saving ? 'Saving…' : 'Save report'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandNavy,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactSheet extends StatelessWidget {
  const _ContactSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Contact Support',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.brandNavy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'School-level support for teachers using GyanSetu AI.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.brandNavy.withValues(alpha: 0.66),
            ),
          ),
          const SizedBox(height: 16),
          for (final String line in const <String>[
            'Your block resource centre supports this device and its content packs.',
            'Translation issues are reported from Settings → Support and kept on the device until online.',
            'On-device help is available here any time, with or without a connection.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(
                      Icons.contact_support_outlined,
                      size: 16,
                      color: AppColors.brandOrange,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: AppColors.brandNavy.withValues(alpha: 0.86),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
