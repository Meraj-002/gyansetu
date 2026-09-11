import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_radius.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/result.dart';
import '../../core/widgets/app_bottom_navigation.dart';
import '../../models/lesson.dart';
import '../../models/resource_manifest.dart';
import '../../services/audio/language_audio_service.dart';
import '../../services/connectivity/connectivity_service.dart';
import '../../services/downloads/download_manager.dart';
import '../../services/resources/resource_catalogue_service.dart';
import '../../services/storage/secure_storage_service.dart';
import '../auth/models/teacher_account.dart';
import '../auth/services/auth_session_store.dart';
import '../lessons/services/lesson_repository.dart';
import '../setup/data/classroom_setup_storage.dart';
import '../setup/models/classroom_setup.dart';
import '../setup/models/offline_resource_status.dart';
import '../setup/services/classroom_setup_repository.dart';
import '../setup/services/offline_resource_manager.dart';
import 'device_storage.dart';

/// Offline Centre: the device's truthful inventory of resources available for
/// teaching without a network connection.
///
/// This screen deliberately does not invent download or model states. Resource
/// availability comes from the existing [OfflineResourceManager], the lesson
/// download repository, and the actual bundled audio probe. Every probe is
/// isolated: one failure marks its own card as an error while the rest of the
/// screen keeps rendering.
class OfflineCenterScreen extends StatefulWidget {
  const OfflineCenterScreen({
    this.connectivityService,
    this.resources,
    this.classrooms,
    this.session,
    this.lessons,
    this.downloads,
    this.audio,
    this.storageProbe,
    this.downloadManager,
    this.resourceCatalogue,
    super.key,
  });

  final ConnectivityService? connectivityService;
  final OfflineResourceManager? resources;
  final ClassroomSetupRepository? classrooms;
  final AuthSessionStore? session;
  final LessonRepository? lessons;
  final LessonDownloadRepository? downloads;
  final LanguageAudioService? audio;

  /// Overrides the on-device storage measurement, which needs platform code
  /// that cannot run in widget tests or on the web.
  final Future<int?> Function()? storageProbe;

  /// The real download pipeline. When provided, Download Queue, Clear Cache
  /// and Update Packs show live state instead of "nothing yet" placeholders.
  final DownloadManager? downloadManager;

  /// The backend pack catalogue behind Update Packs.
  final ResourceCatalogueService? resourceCatalogue;

  @override
  State<OfflineCenterScreen> createState() => _OfflineCenterScreenState();
}

class _OfflineCenterScreenState extends State<OfflineCenterScreen> {
  late final ConnectivityService _connectivity;
  late final OfflineResourceManager _resources;
  late final ClassroomSetupRepository _classrooms;
  late final AuthSessionStore _session;
  late final LessonRepository _lessons;
  late final LessonDownloadRepository _downloads;
  late final LanguageAudioService _audio;
  late final Future<int?> Function() _storageProbe;
  late final DownloadManager? _downloadManager;
  late final ResourceCatalogueService? _resourceCatalogue;

  StreamSubscription<ConnectionStatus>? _connectionSubscription;
  _OfflineSnapshot? _snapshot;
  bool _loading = true;
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final SecureStorageService storage = PlatformSecureStorageService();
    _connectivity = widget.connectivityService ?? PlatformConnectivityService();
    _resources = widget.resources ?? const BundledOfflineResourceManager();
    _classrooms = widget.classrooms ??
        LocalClassroomSetupRepository(defaultClassroomSetupStorage());
    _session = widget.session ?? AuthSessionStore(storage);
    _downloads = widget.downloads ?? LocalLessonDownloadRepository(storage);
    _lessons = widget.lessons ??
        defaultLessonRepository(storage: storage, downloads: _downloads);
    _audio = widget.audio ?? const BundledLanguageAudioService();
    _storageProbe = widget.storageProbe ?? measureAppStorageBytes;
    _downloadManager = widget.downloadManager;
    _resourceCatalogue = widget.resourceCatalogue;
    _downloadManager?.addListener(_onDownloadsChanged);

    _connectionSubscription = _connectivity.onStatusChanged.listen((_) {
      if (mounted) _refresh(silent: true);
    });
    unawaited(_downloadManager?.init());
    unawaited(_refresh());
  }

  void _onDownloadsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _downloadManager?.removeListener(_onDownloadsChanged);
    _connectionSubscription?.cancel();
    if (widget.connectivityService == null) {
      unawaited(_connectivity.dispose());
    }
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_checking) return;
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    _checking = true;

    try {
      final TeacherAccount? account = await _session.account();
      final String teacherId = account?.id ?? 'local-teacher';

      // Each probe is isolated: a failure narrows to its own card instead of
      // taking the whole screen down with it.
      ClassroomSetup? classroom;
      try {
        classroom = await _classrooms.load(teacherId);
      } on Object catch (error, stackTrace) {
        AppLogger.error('classroom load failed', error: error, stackTrace: stackTrace);
      }

      OfflineResourceStatus? resourceStatus;
      if (classroom != null) {
        try {
          resourceStatus = await _resources.check(classroom.resourceProfile);
        } on Object catch (error, stackTrace) {
          AppLogger.error(
            'offline resource check failed',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }

      int? totalLessons;
      int? locallyAvailableLessons;
      try {
        final List<Lesson> catalogue = await _lessons.lessons();
        final Set<String> downloaded = await _downloads.downloadedIds();
        totalLessons = catalogue.length;
        locallyAvailableLessons = catalogue
            .where((Lesson lesson) => downloaded.contains(lesson.id))
            .length;
      } on Object catch (error, stackTrace) {
        AppLogger.error(
          'lesson inventory failed',
          error: error,
          stackTrace: stackTrace,
        );
      }

      bool? targetAudioAvailable;
      if (classroom != null) {
        try {
          targetAudioAvailable =
              await _audio.canPlay(target: classroom.targetLanguage);
        } on Object catch (error, stackTrace) {
          AppLogger.error(
            'audio probe failed',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }

      final int? appBytes = await _storageProbe();

      final _OfflineSnapshot next = _OfflineSnapshot(
        connection: _connectivity.status,
        classroom: classroom,
        resources: resourceStatus,
        locallyAvailableLessons: locallyAvailableLessons,
        totalLessons: totalLessons,
        targetAudioAvailable: targetAudioAvailable,
        appBytes: appBytes,
      );

      if (mounted) {
        setState(() {
          _snapshot = next;
          _loading = false;
          _error = null;
        });
      }
    } on Object catch (error, stackTrace) {
      // The session store is the one dependency the rest of the inventory
      // rests on: if identifying the teacher fails, none of the probes can be
      // trusted, so this is the only whole-screen failure path.
      AppLogger.error(
        'offline center refresh failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not inspect offline resources. Please try again.';
        });
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _testOfflineMode() async {
    if (_checking) return;
    await _refresh();
    if (!mounted) return;
    final _OfflineSnapshot? snapshot = _snapshot;
    if (snapshot == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) => _OfflineCheckSheet(
        snapshot: snapshot,
        downloadManager: _downloadManager,
      ),
    );
  }

  Future<void> _manageDownloads() async {
    final List<Lesson> catalogue = await _lessons.lessons();
    final Set<String> downloaded = await _downloads.downloadedIds();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return _DownloadsSheet(
          catalogue: catalogue,
          downloadedIds: downloaded,
          onRemove: (String lessonId) async {
            await _downloads.remove(lessonId);
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            await _refresh();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Lesson removed from offline list.'),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showHelp() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) => const _HelpSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.homePage,
      body: SafeArea(
        bottom: false,
        child: _body(context),
      ),
      bottomNavigationBar:
          const AppBottomNavigation(current: AppDestination.offline),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading && _snapshot == null) return const _OfflineSkeleton();
    if (_error != null && _snapshot == null) return _ErrorState(onRetry: _refresh);

    final _OfflineSnapshot snapshot = _snapshot!;
    final double width = MediaQuery.sizeOf(context).width;
    final double contentWidth = width.clamp(0.0, 760.0);
    final double sidePad = ((width - contentWidth) / 2) + 16;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.success,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(sidePad, 10, sidePad, 24),
        children: <Widget>[
          _Header(
            connection: snapshot.connection,
            onRefresh: _refresh,
            onHelp: _showHelp,
          ),
          const SizedBox(height: 18),
          const Text(
            'Offline Center',
            style: TextStyle(
              fontSize: 30,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
              color: AppColors.brandNavy,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'All your teaching resources, available offline.',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.brandBody,
            ),
          ),
          const SizedBox(height: 22),
          _ReadinessCard(snapshot: snapshot),
          const SizedBox(height: 18),
          _ResourceGrid(snapshot: snapshot),
          const SizedBox(height: 14),
          _StorageCard(appBytes: snapshot.appBytes),
          const SizedBox(height: 18),
          _ActionCard(
            icon: Icons.download_rounded,
            title: 'Manage Downloads',
            subtitle: 'View or remove locally saved lesson entries',
            color: AppColors.success,
            onTap: _manageDownloads,
          ),
          const SizedBox(height: 10),
          _ActionCard(
            icon: Icons.wifi_off_rounded,
            title: 'Test Offline Mode',
            subtitle: 'Check every required resource on this device',
            color: AppColors.brandNavy,
            outlined: true,
            onTap: _testOfflineMode,
          ),
          const SizedBox(height: 14),
          _QuickTools(
            downloadManager: _downloadManager,
            resourceCatalogue: _resourceCatalogue,
          ),
          const SizedBox(height: 12),
          const _TipCard(),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            _InlineError(message: _error!),
          ],
        ],
      ),
    );
  }
}

/// A truthful snapshot of every device-local probe for one refresh pass.
///
/// The nullable fields carry the per-resource isolation: a null resource list
/// means the check failed, a null lesson count means the catalogue probe failed,
/// a null audio answer means the audio probe failed, and a null byte count
/// means the platform cannot measure storage. Each card reports its own null.
class _OfflineSnapshot {
  const _OfflineSnapshot({
    required this.connection,
    required this.classroom,
    required this.resources,
    required this.locallyAvailableLessons,
    required this.totalLessons,
    required this.targetAudioAvailable,
    required this.appBytes,
  });

  final ConnectionStatus connection;
  final ClassroomSetup? classroom;
  final OfflineResourceStatus? resources;
  final int? locallyAvailableLessons;
  final int? totalLessons;
  final bool? targetAudioAvailable;
  final int? appBytes;

  OfflineResource? _resource(OfflineResourceKind kind) {
    final OfflineResourceStatus? status = resources;
    if (status == null) return null;
    for (final OfflineResource resource in status.resources) {
      if (resource.kind == kind) return resource;
    }
    return null;
  }

  String get missingCountMessage {
    final OfflineResourceStatus? status = resources;
    if (status == null) return 'Offline resources could not be verified';
    if (status.resources.isEmpty) return 'No resource categories verified';
    final int missing = status.missing.length;
    return '$missing resource categor${missing == 1 ? 'y' : 'ies'} missing';
  }

  _ResourceState get languagePackState {
    if (resources == null) return _ResourceState.error;
    final OfflineResource? vocabulary = _resource(OfflineResourceKind.vocabulary);
    final OfflineResource? model = _resource(OfflineResourceKind.languageModel);
    if (vocabulary?.available == true && model?.available == true) {
      return _ResourceState.ready;
    }
    if (vocabulary == null && model == null) return _ResourceState.unknown;
    return _ResourceState.missing;
  }

  String get languagePackSizeLabel {
    return switch (languagePackState) {
      _ResourceState.ready => 'Available locally',
      _ResourceState.missing => 'Not installed',
      _ResourceState.downloading => 'Checking…',
      _ResourceState.error => 'Check failed',
      _ResourceState.unknown => 'Not verified',
    };
  }

  _ResourceState get lessonState {
    final int? count = locallyAvailableLessons;
    final int? total = totalLessons;
    if (count == null || total == null) return _ResourceState.error;
    if (count > 0) return _ResourceState.ready;
    if (total > 0) return _ResourceState.missing;
    return _ResourceState.unknown;
  }

  String get lessonsDetail {
    final int? count = locallyAvailableLessons;
    final int? total = totalLessons;
    if (count == null || total == null) return 'Lesson inventory unavailable';
    return '$count of $total local lessons';
  }

  _ResourceState get audioState {
    final bool? available = targetAudioAvailable;
    if (available == null) return _ResourceState.error;
    return available ? _ResourceState.ready : _ResourceState.missing;
  }

  String get audioDetail {
    final bool? available = targetAudioAvailable;
    if (available == null) return 'Audio probe failed';
    final String language = classroom?.targetLanguage.label ?? 'target';
    return available
        ? '$language audio available locally'
        : 'No $language audio bundled';
  }

  _ResourceState get aiModelState {
    if (resources == null) return _ResourceState.error;
    final OfflineResource? model = _resource(OfflineResourceKind.languageModel);
    if (model == null) return _ResourceState.unknown;
    return model.available ? _ResourceState.ready : _ResourceState.missing;
  }

  String get aiModelDetail {
    final String language = classroom?.targetLanguage.label ?? 'target language';
    return aiModelState == _ResourceState.ready
        ? 'Translation model for $language on device'
        : 'Translation model for $language not installed';
  }

  bool get allRequiredAvailable =>
      resources?.isReady == true && targetAudioAvailable != false;

  String get headline {
    if (resources == null) return 'OFFLINE CHECK FAILED';
    if (resources!.isReady) return 'READY FOR OFFLINE TEACHING';
    return 'OFFLINE SETUP INCOMPLETE';
  }

  String get readinessMessage {
    if (resources == null) {
      return 'The local resource check could not be completed. Pull down to try again.';
    }
    if (resources!.isReady) {
      return 'Your classroom can continue without internet.';
    }
    if (classroom == null) {
      return 'Complete classroom setup before checking language resources.';
    }
    return 'Some resources are not on this device yet.';
  }
}

enum _ResourceState { ready, missing, downloading, error, unknown }

class _StateVisual {
  const _StateVisual({
    required this.color,
    required this.background,
    required this.icon,
    required this.label,
  });

  final Color color;
  final Color background;
  final IconData icon;
  final String label;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.connection,
    required this.onRefresh,
    required this.onHelp,
  });

  final ConnectionStatus connection;
  final Future<void> Function() onRefresh;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final bool offline = connection == ConnectionStatus.offline;
    final Color color = offline ? AppColors.error : AppColors.success;
    final String label = switch (connection) {
      ConnectionStatus.offline => 'Wi-Fi OFF',
      ConnectionStatus.online => 'Online',
      ConnectionStatus.unknown => 'Checking',
    };

    return Row(
      children: <Widget>[
        Image.asset(
          AppAssets.loginBrandMark,
          height: 40,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              const TextSpan(
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
                ),
              ),
            ),
          ),
        ),
        Semantics(
          label: 'Connection: $label',
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: offline ? const Color(0xFFFFF1F0) : const Color(0xFFF0F8F3),
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: color.withValues(alpha: 0.22)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    offline ? Icons.wifi_off_rounded : Icons.cloud_done_outlined,
                    size: 20,
                    color: color,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<_MenuAction>(
          icon: const Icon(Icons.more_vert_rounded, color: AppColors.brandNavy),
          tooltip: 'More options',
          onSelected: (_MenuAction action) {
            switch (action) {
              case _MenuAction.refresh:
                unawaited(onRefresh());
              case _MenuAction.help:
                onHelp();
            }
          },
          itemBuilder: (BuildContext context) => const <PopupMenuEntry<_MenuAction>>[
            PopupMenuItem<_MenuAction>(
              value: _MenuAction.refresh,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.refresh_rounded),
                title: Text('Refresh'),
              ),
            ),
            PopupMenuItem<_MenuAction>(
              value: _MenuAction.help,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.help_outline_rounded),
                title: Text('Offline help'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

enum _MenuAction { refresh, help }

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.snapshot});

  final _OfflineSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final bool ready = snapshot.allRequiredAvailable && snapshot.resources != null;
    final bool failed = snapshot.resources == null;
    final Color accent = failed ? AppColors.error : (ready ? AppColors.success : AppColors.warning);
    final Color background =
        failed ? const Color(0xFFFFF1F0) : (ready ? const Color(0xFFF2FAF4) : const Color(0xFFFFF8ED));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.12),
                  border: Border.all(color: accent.withValues(alpha: 0.16), width: 6),
                ),
                child: Icon(
                  failed
                      ? Icons.error_outline_rounded
                      : (ready ? Icons.check_rounded : Icons.cloud_off_rounded),
                  size: 34,
                  color: accent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      snapshot.headline,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      snapshot.readinessMessage,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: AppColors.brandBody,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          const Divider(height: 1),
          const SizedBox(height: 13),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              const _HonestChip(
                icon: Icons.lock_outline_rounded,
                label: 'Secure',
                color: AppColors.success,
                background: Color(0xFFF0F8F3),
              ),
              const _HonestChip(
                icon: Icons.bolt_rounded,
                label: 'Fast · checks run on-device',
                color: AppColors.info,
                background: Color(0xFFF1F6FD),
              ),
              const _HonestChip(
                icon: Icons.privacy_tip_outlined,
                label: 'Private',
                color: AppColors.brandNavy,
                background: Color(0xFFF0F2FA),
              ),
              _HonestChip(
                icon: snapshot.aiModelState == _ResourceState.ready
                    ? Icons.auto_awesome_rounded
                    : Icons.priority_high_rounded,
                label: snapshot.aiModelState == _ResourceState.ready
                    ? 'Offline AI ready'
                    : 'Offline AI — not installed',
                color: AppColors.warning,
                background: const Color(0xFFFFF7EA),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HonestChip extends StatelessWidget {
  const _HonestChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadius.pillAll,
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
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

/// The four resource cards: single column on narrow phones, two columns once
/// the content area is wide enough.
class _ResourceGrid extends StatelessWidget {
  const _ResourceGrid({required this.snapshot});

  final _OfflineSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double cardWidth = _cardWidth(constraints.maxWidth);
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            SizedBox(
              width: cardWidth,
              child: _ResourceCard(
                icon: Icons.translate_rounded,
                iconColor: const Color(0xFF6C4AB6),
                iconBackground: const Color(0xFFF0EBFB),
                title: 'Downloaded Language Pack',
                detail: snapshot.classroom?.targetLanguage.label ??
                    'Classroom setup required',
                size: snapshot.languagePackSizeLabel,
                state: snapshot.languagePackState,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _ResourceCard(
                icon: Icons.menu_book_rounded,
                iconColor: AppColors.secondaryDark,
                iconBackground: const Color(0xFFFFF3DE),
                title: 'Downloaded Lessons',
                detail: snapshot.lessonsDetail,
                size: 'Bundled/local catalogue',
                state: snapshot.lessonState,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _ResourceCard(
                icon: Icons.volume_up_rounded,
                iconColor: const Color(0xFF258C83),
                iconBackground: const Color(0xFFE8F5F2),
                title: 'Audio Library',
                detail: snapshot.audioDetail,
                size: snapshot.targetAudioAvailable == true
                    ? 'Available locally'
                    : '0 target-language files',
                state: snapshot.audioState,
              ),
            ),
            SizedBox(
              width: constraints.maxWidth,
              child: _AiModelsCard(snapshot: snapshot),
            ),
          ],
        );
      },
    );
  }

  static double _cardWidth(double wrapWidth) {
    if (wrapWidth < 640) return wrapWidth;
    return (wrapWidth - 10) / 2;
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.detail,
    required this.size,
    required this.state,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String detail;
  final String size;
  final _ResourceState state;

  @override
  Widget build(BuildContext context) {
    final _StateVisual visual = _visual(state);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: AppRadius.mdAll,
            ),
            child: Icon(icon, size: 35, color: iconColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, color: AppColors.brandBody),
                ),
                const SizedBox(height: 3),
                Text(
                  size,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.brandNavy),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: visual.background,
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: visual.color.withValues(alpha: 0.18)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(visual.icon, size: 17, color: visual.color),
                const SizedBox(width: 5),
                Text(
                  visual.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: visual.color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static _StateVisual _visual(_ResourceState state) {
    return switch (state) {
      _ResourceState.ready => const _StateVisual(
          color: AppColors.success,
          background: Color(0xFFF0F8F3),
          icon: Icons.check_rounded,
          label: 'Ready',
        ),
      _ResourceState.missing => const _StateVisual(
          color: AppColors.warning,
          background: Color(0xFFFFF7EA),
          icon: Icons.download_outlined,
          label: 'Missing',
        ),
      _ResourceState.downloading => const _StateVisual(
          color: AppColors.info,
          background: Color(0xFFF1F6FD),
          icon: Icons.sync_rounded,
          label: 'Checking',
        ),
      _ResourceState.error => const _StateVisual(
          color: AppColors.error,
          background: Color(0xFFFFF1F0),
          icon: Icons.error_outline_rounded,
          label: 'Error',
        ),
      _ResourceState.unknown => const _StateVisual(
          color: AppColors.textSecondary,
          background: Color(0xFFF4F5F7),
          icon: Icons.help_outline_rounded,
          label: 'Unknown',
        ),
    };
  }
}

/// AI capabilities reported on separate honest rows: the translation model
/// comes from the real resource check, the speech model is reported for what
/// it is (not shipped), rather than pretending one exists.
class _AiModelsCard extends StatelessWidget {
  const _AiModelsCard({required this.snapshot});

  final _OfflineSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0EBFB),
                  borderRadius: AppRadius.mdAll,
                ),
                child: const Icon(
                  Icons.psychology_alt_rounded,
                  size: 35,
                  color: Color(0xFF6C4AB6),
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'AI Models',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandNavy,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'On-device model pack',
                      style: TextStyle(fontSize: 12.5, color: AppColors.brandNavy),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.06),
                  borderRadius: AppRadius.mdAll,
                ),
                child: const Text(
                  'AI',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _AiRow(
            title: 'Translation Model',
            detail: snapshot.aiModelDetail,
            state: snapshot.aiModelState,
          ),
          const SizedBox(height: 8),
          const _AiRow(
            title: 'Speech Model',
            detail: 'No on-device speech model in this build',
            state: _ResourceState.missing,
          ),
        ],
      ),
    );
  }
}

class _AiRow extends StatelessWidget {
  const _AiRow({
    required this.title,
    required this.detail,
    required this.state,
  });

  final String title;
  final String detail;
  final _ResourceState state;

  @override
  Widget build(BuildContext context) {
    final _StateVisual visual = _ResourceCard._visual(state);
    return Row(
      children: <Widget>[
        const Icon(Icons.memory_rounded, size: 20, color: AppColors.brandMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandNavy,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(fontSize: 12, color: AppColors.brandBody),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: visual.background,
            borderRadius: AppRadius.pillAll,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(visual.icon, size: 15, color: visual.color),
              const SizedBox(width: 5),
              Text(
                visual.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: visual.color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.appBytes});

  final int? appBytes;

  @override
  Widget build(BuildContext context) {
    final String? label = appBytes == null ? null : _formatBytes(appBytes!);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.22),
                width: 7,
              ),
            ),
            child: const Icon(
              Icons.sd_storage_outlined,
              color: AppColors.brandNavy,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Device Storage',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'App data currently measured on this device',
                  style: TextStyle(fontSize: 13, color: AppColors.brandBody),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label ?? 'Unavailable on this platform',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: label == null ? 12.5 : 18,
                fontWeight: FontWeight.w900,
                color: AppColors.brandNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.outlined = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final Color foreground = outlined ? color : Colors.white;
    final Color titleColor = outlined ? AppColors.brandNavy : Colors.white;
    final Color subtitleColor = outlined
        ? AppColors.brandBody
        : Colors.white.withValues(alpha: 0.9);

    return Semantics(
      button: true,
      label: title,
      hint: subtitle,
      child: ExcludeSemantics(
        child: Material(
          color: outlined ? Colors.white : color,
          borderRadius: AppRadius.lgAll,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.lgAll,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              decoration: BoxDecoration(
                borderRadius: AppRadius.lgAll,
                border: outlined ? Border.all(color: color) : null,
              ),
              child: Row(
                children: <Widget>[
                  Icon(icon, size: 30, color: foreground),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(fontSize: 12.5, color: subtitleColor),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 28,
                    color: foreground,
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

/// Secondary tools. Download Queue, Clear Cache and Update Packs are honest:
/// with a [DownloadManager] they show the device's real transfers and pack
/// versions; without one they keep the "nothing yet" placeholders instead of
/// pretending downloads exist.
class _QuickTools extends StatelessWidget {
  const _QuickTools({
    this.downloadManager,
    this.resourceCatalogue,
  });

  final DownloadManager? downloadManager;
  final ResourceCatalogueService? resourceCatalogue;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DownloadManager? manager = downloadManager;
    final String queueTrailing = switch (manager) {
      null => 'No downloads in progress',
      _ when manager.isDownloading =>
        '${manager.statuses.values.where((ResourceDownloadStatus s) => s.state.isActive).length} downloading',
      _ when manager.queueOrder.isNotEmpty =>
        '${manager.queueOrder.length} queued',
      _ => 'All transfers finished',
    };
    final String cacheTrailing = manager == null
        ? 'Nothing to clear'
        : 'Removes interrupted transfers';
    final String updateTrailing = resourceCatalogue == null
        ? 'No packs to update yet'
        : 'Check for pack updates';

    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Quick Tools',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.brandNavy,
              ),
            ),
          ),
          if (manager == null)
            const _ToolRow(
              icon: Icons.downloading_rounded,
              title: 'Download Queue',
              subtitle: 'See what is downloading',
              trailing: 'No downloads in progress',
            )
          else
            _ToolRow(
              icon: Icons.downloading_rounded,
              title: 'Download Queue',
              subtitle: 'See what is downloading',
              trailing: queueTrailing,
              trailingColor: scheme.primary,
              onTap: (BuildContext context) => _openDownloadQueue(
                context,
                manager,
              ),
            ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          if (manager == null)
            const _ToolRow(
              icon: Icons.cleaning_services_outlined,
              title: 'Clear Cache',
              subtitle: 'Remove temporary files',
              trailing: 'Nothing to clear',
            )
          else
            _ToolRow(
              icon: Icons.cleaning_services_outlined,
              title: 'Clear Cache',
              subtitle: 'Remove interrupted transfer files',
              trailing: cacheTrailing,
              trailingColor: scheme.primary,
              onTap: (BuildContext context) => _clearTemporaryFiles(
                context,
                manager,
              ),
            ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          if (resourceCatalogue == null)
            const _ToolRow(
              icon: Icons.system_update_alt_rounded,
              title: 'Update Packs',
              subtitle: 'Download the latest resource packs',
              trailing: 'No packs to update yet',
            )
          else
            _ToolRow(
              icon: Icons.system_update_alt_rounded,
              title: 'Update Packs',
              subtitle: 'Download the latest resource packs',
              trailing: updateTrailing,
              trailingColor: scheme.primary,
              onTap: (BuildContext context) => _openUpdatePacks(
                context,
                manager,
                resourceCatalogue!,
              ),
            ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _ToolRow(
            icon: Icons.help_outline_rounded,
            title: 'Offline Help',
            subtitle: 'What this screen shows and why',
            trailing: 'Open',
            trailingColor: scheme.primary,
            onTap: (BuildContext context) async {
              await showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                isScrollControlled: true,
                builder: (BuildContext context) => const _HelpSheet(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _openDownloadQueue(BuildContext context, DownloadManager manager) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) => _DownloadQueueSheet(manager: manager),
    );
  }

  Future<void> _clearTemporaryFiles(
    BuildContext context,
    DownloadManager manager,
  ) async {
    final int removed = await manager.clearTemporaryFiles();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Row(
            children: <Widget>[
              const Icon(Icons.check_circle_outline, color: AppColors.success),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  removed == 0
                      ? 'No interrupted transfer files found.'
                      : '$removed interrupted transfer file'
                          '${removed == 1 ? '' : 's'} cleared.',
                  style: const TextStyle(fontSize: 14.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openUpdatePacks(
    BuildContext context,
    DownloadManager? manager,
    ResourceCatalogueService catalogue,
  ) async {
    final Map<String, String> localVersions = <String, String>{
      if (manager != null)
        for (final ResourceManifest manifest in manager.readyManifests)
          manifest.id: manifest.version,
    };
    final Result<Map<String, ResourceManifest>> diff = await catalogue.diffWith(
      localVersions,
    );
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => _UpdatePacksSheet(
        diff: diff,
        onDownload: (List<ResourceManifest> packs) async {
          if (manager == null) return;
          await manager.enqueue(packs);
          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
        },
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.trailingColor = AppColors.textSecondary,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final Color trailingColor;
  final void Function(BuildContext context)? onTap;

  @override
  Widget build(BuildContext context) {
    final bool tappable = onTap != null;
    return ListTile(
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(icon, color: AppColors.brandNavy),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: AppColors.brandNavy,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppColors.brandBody),
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 150),
        child: Text(
          trailing,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: trailingColor,
          ),
        ),
      ),
      enabled: tappable,
      onTap: tappable ? () => onTap!(context) : null,
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6FF),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: const Color(0xFFD7E3FA)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFE5EEFF),
            ),
            child: const Icon(Icons.lightbulb_outline, color: AppColors.info),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Tip: Keep your device charged',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Run Test Offline Mode before teaching without internet.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.brandBody),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

enum _CheckVerdict { ready, incomplete, error }

class _OfflineCheckSheet extends StatelessWidget {
  const _OfflineCheckSheet({
    required this.snapshot,
    this.downloadManager,
  });

  final _OfflineSnapshot snapshot;

  /// When present, packs downloaded through the real pipeline are checked too.
  final DownloadManager? downloadManager;

  _CheckVerdict get verdict {
    if (snapshot.resources == null ||
        snapshot.locallyAvailableLessons == null ||
        snapshot.targetAudioAvailable == null) {
      return _CheckVerdict.error;
    }
    if (!snapshot.resources!.isReady || snapshot.targetAudioAvailable == false) {
      return _CheckVerdict.incomplete;
    }
    return _CheckVerdict.ready;
  }

  @override
  Widget build(BuildContext context) {
    final _StateVisual verdictVisual = switch (verdict) {
      _CheckVerdict.ready => const _StateVisual(
          color: AppColors.success,
          background: Color(0xFFF0F8F3),
          icon: Icons.check_rounded,
          label: 'READY',
        ),
      _CheckVerdict.incomplete => const _StateVisual(
          color: AppColors.warning,
          background: Color(0xFFFFF7EA),
          icon: Icons.priority_high_rounded,
          label: 'INCOMPLETE',
        ),
      _CheckVerdict.error => const _StateVisual(
          color: AppColors.error,
          background: Color(0xFFFFF1F0),
          icon: Icons.error_outline_rounded,
          label: 'ERROR',
        ),
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Offline Mode Check',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: verdictVisual.background,
                  borderRadius: AppRadius.mdAll,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(verdictVisual.icon, color: verdictVisual.color),
                    const SizedBox(width: 6),
                    Text(
                      'Verdict: ${verdictVisual.label}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: verdictVisual.color,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                verdict == _CheckVerdict.ready
                    ? 'Every required resource reported available on this device.'
                    : verdict == _CheckVerdict.error
                        ? 'Some local checks completed with errors. See each row below.'
                        : snapshot.resources?.message ??
                            'Some required resources are unavailable.',
                style: const TextStyle(color: AppColors.brandBody),
              ),
              const SizedBox(height: 18),
              if (snapshot.classroom == null)
                const _CheckRow(
                  label: 'Classroom setup',
                  detail: 'No saved classroom configuration found',
                  state: _ResourceState.missing,
                )
              else ...<Widget>[
                for (final OfflineResource resource
                    in snapshot.resources?.resources ?? const <OfflineResource>[])
                  _CheckRow(
                    label: resource.kind.label,
                    detail: resource.available
                        ? 'Present on this build/device'
                        : resource.detail ?? 'Not available',
                    state: resource.available
                        ? _ResourceState.ready
                        : _ResourceState.missing,
                  ),
                _CheckRow(
                  label: 'Target-language audio',
                  detail: snapshot.targetAudioAvailable == true
                      ? 'Playable bundled audio detected'
                      : snapshot.targetAudioAvailable == false
                          ? 'No playable bundled target-language audio detected'
                          : 'Audio probe failed',
                  state: snapshot.targetAudioAvailable == true
                      ? _ResourceState.ready
                      : snapshot.targetAudioAvailable == false
                          ? _ResourceState.missing
                          : _ResourceState.error,
                ),
                if (downloadManager != null) ...<Widget>[
                  _CheckRow(
                    label: 'Downloaded content packs',
                    detail: downloadManager!.readyManifests.isEmpty
                        ? 'No packs verified on this device'
                        : '${downloadManager!.readyManifests.length} packs '
                            'verified by size and checksum',
                    state: downloadManager!.readyManifests.isEmpty
                        ? _ResourceState.missing
                        : _ResourceState.ready,
                  ),
                ],
                _CheckRow(
                  label: 'Device storage',
                  detail: snapshot.appBytes == null
                      ? 'Storage size unavailable on this platform'
                      : 'App data on device is being measured',
                  state: snapshot.appBytes == null
                      ? _ResourceState.error
                      : _ResourceState.ready,
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                'This check reads local resources. It does not download anything '
                'and does not claim that a model exists when the build does not '
                'contain one.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.label, required this.detail, required this.state});

  final String label;
  final String detail;
  final _ResourceState state;

  @override
  Widget build(BuildContext context) {
    final _StateVisual visual = _ResourceCard._visual(state);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: AppColors.authFieldBorder),
        ),
        child: Row(
          children: <Widget>[
            Icon(visual.icon, color: visual.color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              visual.label,
              style: TextStyle(fontWeight: FontWeight.w700, color: visual.color),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadsSheet extends StatelessWidget {
  const _DownloadsSheet({
    required this.catalogue,
    required this.downloadedIds,
    required this.onRemove,
  });

  final List<Lesson> catalogue;
  final Set<String> downloadedIds;
  final Future<void> Function(String lessonId) onRemove;

  @override
  Widget build(BuildContext context) {
    final List<Lesson> downloaded = catalogue
        .where((Lesson lesson) => downloadedIds.contains(lesson.id))
        .toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Manage Downloads',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                color: AppColors.brandNavy,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${downloaded.length} lesson entries are marked for offline use.',
              style: const TextStyle(color: AppColors.brandBody),
            ),
            const SizedBox(height: 14),
            if (downloaded.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No locally downloaded lesson entries found.'),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: downloaded.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final Lesson lesson = downloaded[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.menu_book_outlined,
                        color: AppColors.brandNavy,
                      ),
                      title: Text(lesson.title),
                      subtitle: Text(
                        'Class ${lesson.classNumber} • ${lesson.subject.label}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        onPressed: () => onRemove(lesson.id),
                        icon: const Icon(
                          Icons.delete_outline,
                          color: AppColors.error,
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HelpSheet extends StatelessWidget {
  const _HelpSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'About the Offline Centre',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                ),
              ),
              const SizedBox(height: 12),
              _helpParagraph(
                'Every card on this screen reports what this device actually '
                'holds, checked against local resources. Nothing here goes over '
                'the network.',
              ),
              _helpParagraph(
                'Manage Downloads lists lesson entries marked for offline use '
                'and lets you remove them.',
              ),
              _helpParagraph(
                'Test Offline Mode runs the same local checks and shows the '
                'result category by category.',
              ),
              _helpParagraph(
                'Some resources are not available yet: resource language packs, '
                'target-language audio and on-device AI models do not ship with '
                'this build. The screen says so instead of showing a fake '
                '“ready” state.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _helpParagraph(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14.5, height: 1.5, color: AppColors.brandBody),
      ),
    );
  }
}

class _DownloadQueueSheet extends StatelessWidget {
  const _DownloadQueueSheet({required this.manager});

  final DownloadManager manager;

  @override
  Widget build(BuildContext context) {
    final List<ResourceDownloadStatus> statuses =
        manager.statuses.values.toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Download Queue',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                color: AppColors.brandNavy,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              statuses.isEmpty
                  ? 'Nothing downloaded on this device yet.'
                  : '${statuses.where((s) => s.isReady).length} ready on this '
                      'device.',
              style: const TextStyle(color: AppColors.brandBody),
            ),
            const SizedBox(height: 14),
            if (statuses.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No packs queued or transferred.'),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: statuses.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final ResourceDownloadStatus status = statuses[index];
                    final _StateVisual visual = _downloadVisual(status.state);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(visual.icon, color: visual.color),
                      title: Text(status.manifest.id),
                      subtitle: Text(_statusDetail(status)),
                      trailing: Text(
                        visual.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: visual.color,
                        ),
                      ),
                      onTap: status.state == ResourceDownloadState.failed
                          ? () => manager.retry(status.manifest.id)
                          : null,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _statusDetail(ResourceDownloadStatus status) => switch (status.state) {
        ResourceDownloadState.downloading =>
          '${(status.progress * 100).round()}% • streaming to disk',
        ResourceDownloadState.verifying => 'Verifying file integrity…',
        ResourceDownloadState.queued => 'Waiting in line behind other packs',
        ResourceDownloadState.ready => '${status.manifest.sizeBytes} bytes verified',
        ResourceDownloadState.failed =>
          status.failure == ResourceDownloadFailure.insufficientStorage
              ? 'Not enough storage'
              : 'Failed — tap to retry',
        ResourceDownloadState.missing => 'No longer on this device',
      };

  static _StateVisual _downloadVisual(ResourceDownloadState state) {
    return switch (state) {
      ResourceDownloadState.ready => const _StateVisual(
          color: AppColors.success,
          background: Color(0xFFF0F8F3),
          icon: Icons.check_rounded,
          label: 'Ready',
        ),
      ResourceDownloadState.downloading => const _StateVisual(
          color: AppColors.info,
          background: Color(0xFFF1F6FD),
          icon: Icons.downloading_rounded,
          label: '…',
        ),
      ResourceDownloadState.verifying => const _StateVisual(
          color: AppColors.info,
          background: Color(0xFFF1F6FD),
          icon: Icons.fingerprint_rounded,
          label: '…',
        ),
      ResourceDownloadState.queued => const _StateVisual(
          color: AppColors.textSecondary,
          background: Color(0xFFF4F5F7),
          icon: Icons.schedule_rounded,
          label: 'Queued',
        ),
      ResourceDownloadState.failed => const _StateVisual(
          color: AppColors.error,
          background: Color(0xFFFFF1F0),
          icon: Icons.error_outline_rounded,
          label: 'Failed',
        ),
      ResourceDownloadState.missing => const _StateVisual(
          color: AppColors.textSecondary,
          background: Color(0xFFF4F5F7),
          icon: Icons.help_outline_rounded,
          label: 'Missing',
        ),
    };
  }
}

class _UpdatePacksSheet extends StatelessWidget {
  const _UpdatePacksSheet({required this.diff, required this.onDownload});

  final Result<Map<String, ResourceManifest>> diff;
  final Future<void> Function(List<ResourceManifest> packs) onDownload;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Update Packs',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                color: AppColors.brandNavy,
              ),
            ),
            const SizedBox(height: 14),
            switch (diff) {
              Err<Map<String, ResourceManifest>>() => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Could not check for pack updates. Check your connection '
                    'and pull down to retry.',
                    style: TextStyle(color: AppColors.brandBody),
                  ),
                ),
              Ok<Map<String, ResourceManifest>>(
                :final Map<String, ResourceManifest> value,
              ) when value.isEmpty => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'All content packs are up to date.',
                    style: TextStyle(color: AppColors.brandBody),
                  ),
                ),
              Ok<Map<String, ResourceManifest>>(
                :final Map<String, ResourceManifest> value,
              ) => Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 340),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: value.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) {
                        final ResourceManifest manifest =
                            value.values.elementAt(index);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.extension_rounded,
                            color: AppColors.brandNavy,
                          ),
                          title: Text(manifest.id),
                          subtitle: Text('v${manifest.version}'),
                          trailing: IconButton(
                            tooltip: 'Queue download',
                            onPressed: () =>
                                onDownload(<ResourceManifest>[manifest]),
                            icon: const Icon(
                              Icons.download_for_offline_outlined,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            },
          ],
        ),
      ),
    );
  }
}

class _OfflineSkeleton extends StatelessWidget {
  const _OfflineSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        _Header(
          connection: ConnectionStatus.unknown,
          onRefresh: _noop,
          onHelp: _noop,
        ),
        const SizedBox(height: 18),
        const Text(
          'Offline Center',
          style: TextStyle(
            fontSize: 30,
            height: 1.1,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
            color: AppColors.brandNavy,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'All your teaching resources, available offline.',
          style: TextStyle(
            fontSize: 16,
            color: AppColors.brandBody,
          ),
        ),
        const SizedBox(height: 22),
        for (int i = 0; i < 5; i++) ...<Widget>[
          Container(height: i == 0 ? 190 : 100, color: Colors.black12),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  static Future<void> _noop() async {}
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            const Text(
              'Could not inspect offline resources.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Try Again')),
          ],
        ),
      ),
    );
  }
}