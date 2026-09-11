import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_radius.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/result.dart';
import '../../core/widgets/app_bottom_navigation.dart';
import '../../services/connectivity/connectivity_service.dart';
import '../../services/service_registry.dart';
import '../../services/storage/secure_storage_service.dart';
import '../../services/sync/local_sync_service.dart';
import '../../services/sync/sync_metadata_store.dart';
import '../../services/sync/sync_service.dart';
import '../../services/sync/sync_status.dart';
import '../auth/models/teacher_account.dart';
import '../auth/services/auth_session_store.dart';
import '../setup/data/classroom_setup_storage.dart';
import '../setup/models/classroom_setup.dart';
import '../setup/models/offline_resource_status.dart';
import '../setup/services/classroom_setup_repository.dart';
import '../setup/services/offline_resource_manager.dart';

/// Content Sync: reconciles on-device records with the server through the
/// [SyncService] boundary, and reports honestly what this device does and does
/// not hold.
///
/// The screen never talks to an HTTP client. It drives [SyncService]; the
/// default build backs it with the FastAPI sync bridge, which pushes pending
/// local records, pulls updates, and reports progress through the state machine
/// (checking → uploading → downloading → completed). Tests and previews still
/// inject any [SyncService], including the clearly-marked [DevSyncService].
class SyncCenterScreen extends StatefulWidget {
  const SyncCenterScreen({
    this.connectivityService,
    this.syncService,
    this.syncMetadata,
    this.session,
    this.classrooms,
    this.resources,
    super.key,
  });

  final ConnectivityService? connectivityService;
  final SyncService? syncService;
  final SyncMetadataStore? syncMetadata;
  final AuthSessionStore? session;
  final ClassroomSetupRepository? classrooms;
  final OfflineResourceManager? resources;

  @override
  State<SyncCenterScreen> createState() => _SyncCenterScreenState();
}

class _SyncCenterScreenState extends State<SyncCenterScreen> {
  late final ConnectivityService _connectivity;
  late final SyncService _syncService;
  late final SyncMetadataStore _metadata;
  late final AuthSessionStore _session;
  late final ClassroomSetupRepository _classrooms;
  late final OfflineResourceManager _resources;

  StreamSubscription<ConnectionStatus>? _connectionSubscription;
  StreamSubscription<SyncStatus>? _syncSubscription;

  ConnectionStatus _connection = ConnectionStatus.unknown;
  SyncStatus _status = const SyncStatus(state: SyncState.idle);
  DateTime? _lastSyncedAt;
  _SyncSnapshot? _snapshot;

  bool _loading = true;
  bool _checking = false;
  bool _syncing = false;
  String? _loadError;
  String? _runError;

  @override
  void initState() {
    super.initState();
    final SecureStorageService storage = PlatformSecureStorageService();
    _connectivity = widget.connectivityService ?? PlatformConnectivityService();
    _session = widget.session ?? AuthSessionStore(storage);
    _metadata = widget.syncMetadata ?? LocalSyncMetadataStore(storage);
    _classrooms = widget.classrooms ??
        LocalClassroomSetupRepository(defaultClassroomSetupStorage());
    _resources = widget.resources ?? const BundledOfflineResourceManager();
    _syncService =
        widget.syncService ?? ServiceRegistry.instance.sync;

    _connection = _connectivity.status;
    _status = _syncService.status;

    _connectionSubscription = _connectivity.onStatusChanged.listen(_onConnection);
    _syncSubscription = _syncService.onStatusChanged.listen(_onStatus);
    unawaited(_load());
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _syncSubscription?.cancel();
    if (widget.connectivityService == null) {
      unawaited(_connectivity.dispose());
    }
    if (widget.syncService == null && _syncService is DevSyncService) {
      unawaited(_syncService.dispose());
    }
    super.dispose();
  }

  void _onConnection(ConnectionStatus next) {
    if (!mounted) return;
    setState(() {
      _connection = next;
      // A sync started while online must not be reported as a clean success if
      // the device lost its connection before the (mock) run finished.
      if (_syncing && next != ConnectionStatus.online) {
        _runError = 'Connection was lost during sync.';
      }
    });
  }

  void _onStatus(SyncStatus next) {
    if (!mounted) return;
    setState(() {
      // Never let a completion overwrite a connection-loss error.
      if (next.state == SyncState.completed && _runError != null) return;
      _status = next;
      final DateTime? done = next.lastSyncedAt;
      if (done != null) _lastSyncedAt = done;
      if (next.state == SyncState.completed) {
        _runError = null;
        _syncing = false;
      } else if (next.state == SyncState.failed) {
        _syncing = false;
        _runError = next.errorMessage ?? 'Sync failed';
      }
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (_checking) return;
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    _checking = true;

    try {
      final TeacherAccount? account = await _session.account();
      final String teacherId = account?.id ?? 'local-teacher';

      ClassroomSetup? classroom;
      try {
        classroom = await _classrooms.load(teacherId);
      } on Object catch (error, stackTrace) {
        AppLogger.error('sync classroom load failed',
            error: error, stackTrace: stackTrace);
      }

      OfflineResourceStatus? resources;
      if (classroom != null) {
        try {
          resources = await _resources.check(classroom.resourceProfile);
        } on Object catch (error, stackTrace) {
          AppLogger.error('sync resource check failed',
              error: error, stackTrace: stackTrace);
        }
      }

      final DateTime? lastSynced = await _metadata.lastSyncedAt();

      if (mounted) {
        setState(() {
          _snapshot = _SyncSnapshot(classroom: classroom, resources: resources);
          _lastSyncedAt = lastSynced ?? _lastSyncedAt;
          _loading = false;
          _loadError = null;
        });
      }
    } on Object catch (error, stackTrace) {
      // The session store is the one dependency every other probe leans on:
      // if identifying the teacher fails, none of the reads can be trusted.
      AppLogger.error('sync center refresh failed',
          error: error, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Could not read the sync state. Please try again.';
        });
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _syncNow() async {
    if (_syncing || _statusIsInFlight) return;

    final ConnectionStatus connection = await _connectivity.check();
    if (!mounted) return;

    if (connection != ConnectionStatus.online) {
      setState(() {
        _connection = connection;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No internet connection.')),
      );
      return;
    }

    setState(() {
      _syncing = true;
      _runError = null;
    });

    final Result<SyncStatus> result = await _syncService.syncNow();
    if (!mounted) return;

    // A future FastAPI implementation may return an error without streaming a
    // failed status; degrade to the error line when nothing was emitted.
    if (result is Err<SyncStatus> &&
        !_statusIsInFlight &&
        _status.state != SyncState.failed) {
      setState(() => _runError = result.error.message);
    }
    setState(() => _syncing = false);
  }

  bool get _statusIsInFlight =>
      _status.state == SyncState.checking ||
      _status.state == SyncState.uploading ||
      _status.state == SyncState.downloading ||
      _status.state == SyncState.syncing;

  Future<void> _showAbout() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) => const _AboutSyncSheet(),
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
    if (_loading && _snapshot == null) return const _SyncSkeleton();
    if (_loadError != null && _snapshot == null) {
      return _ErrorState(onRetry: _load);
    }

    final double width = MediaQuery.sizeOf(context).width;
    final double contentWidth = width.clamp(0.0, 760.0);
    final double sidePad = ((width - contentWidth) / 2) + 16;

    final bool offline = _connection == ConnectionStatus.offline;

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.success,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(sidePad, 10, sidePad, 24),
        children: <Widget>[
          _Header(
            connection: _connection,
            onBack: () => Navigator.of(context).maybePop(),
            onRefresh: () => _load(silent: true),
            onHelp: _showAbout,
          ),
          const SizedBox(height: 18),
          const Text(
            'Content Sync',
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
            'Keep your classroom content up to date.',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.brandBody,
            ),
          ),
          const SizedBox(height: 16),
          if (offline) ...<Widget>[
            const _OfflineBanner(),
            const SizedBox(height: 16),
          ],
          _StatusCard(
            status: _status,
            lastSyncedAt: _lastSyncedAt,
            resourcesReady: _snapshot?.resources?.isReady ?? false,
            errorMessage: _runError,
          ),
          const SizedBox(height: 14),
          if (_statusIsInFlight) ...<Widget>[
            ClipRRect(
              borderRadius: AppRadius.pillAll,
              child: LinearProgressIndicator(
                value: _status.progress,
                minHeight: 6,
                color: AppColors.success,
                backgroundColor: AppColors.success.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 14),
          ],
          FilledButton.icon(
            onPressed: _syncing ? null : _syncNow,
            icon: Icon(_syncing ? Icons.sync_rounded : Icons.cloud_sync_outlined),
            label: Text(_syncing ? 'Syncing…' : 'Sync Now'),
          ),
          if (_runError != null) ...<Widget>[
            const SizedBox(height: 12),
            _InlineError(message: _runError!),
          ],
          const SizedBox(height: 22),
          _CategoryList(
            categories: _SyncCategory.values,
            stateFor: _stateForCategory,
            onTap: _openCategory,
          ),
          const SizedBox(height: 14),
          const _DataFriendlyCard(),
          if (_loadError != null) ...<Widget>[
            const SizedBox(height: 12),
            _InlineError(message: _loadError!),
          ],
        ],
      ),
    );
  }

  _CategoryState _stateForCategory(_SyncCategory category) {
    if (_statusIsInFlight) {
      switch (_status.state) {
        case SyncState.checking:
          return _CategoryState.checking;
        case SyncState.downloading:
          return _CategoryState.downloading;
        case SyncState.uploading:
        case SyncState.syncing:
          // Nothing has been downloaded during these phases, so the categories
          // keep reporting their real local state.
          break;
        case SyncState.idle:
        case SyncState.pending:
        case SyncState.failed:
        case SyncState.completed:
          break;
      }
    }

    if (category.kind == null) {
      // No probe measures AI vocabulary yet, so no state is claimed for it.
      return _CategoryState.unavailableOffline;
    }

    final _SyncSnapshot? snapshot = _snapshot;
    if (snapshot == null || snapshot.classroom == null) {
      return _CategoryState.unavailableOffline;
    }
    final OfflineResourceStatus? status = snapshot.resources;
    if (status == null) return _CategoryState.error;

    for (final OfflineResource resource in status.resources) {
      if (resource.kind == category.kind) {
        return resource.available
            ? _CategoryState.upToDate
            : _CategoryState.needsUpdate;
      }
    }
    return _CategoryState.missing;
  }

  Future<void> _openCategory(_SyncCategory category) async {
    final _CategoryState state = _stateForCategory(category);
    final bool offline = _connection == ConnectionStatus.offline;
    final bool available = _isAvailable(category, state);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) => _ResourceDetailSheet(
        category: category,
        state: state,
        available: available,
        offline: offline,
        lastSyncedAt: _lastSyncedAt,
        onSyncNow: () async {
          Navigator.of(context).pop();
          await _syncNow();
        },
      ),
    );
  }

  /// Whether a category's content really is on this device.
  bool _isAvailable(_SyncCategory category, _CategoryState state) {
    if (category.kind == null) return false;
    if (state == _CategoryState.upToDate) return true;
    if (_snapshot?.resources == null) return false;
    for (final OfflineResource resource in _snapshot!.resources!.resources) {
      if (resource.kind == category.kind) return resource.available;
    }
    return false;
  }
}

/// A truthful snapshot of the sync-related local reads for one refresh pass.
class _SyncSnapshot {
  const _SyncSnapshot({required this.classroom, required this.resources});

  final ClassroomSetup? classroom;
  final OfflineResourceStatus? resources;
}

/// The content categories shown in "What Gets Synced".
enum _SyncCategory {
  curriculum(
    title: 'Curriculum',
    description: 'Lesson plans, learning outcomes, activities',
    icon: Icons.menu_book_rounded,
    iconColor: Color(0xFF2B5C9B),
    iconBackground: Color(0xFFF2F7FD),
    kind: OfflineResourceKind.curriculum,
  ),
  languagePack(
    title: 'Santali Language Pack',
    description: 'Translations, vocabulary, local content',
    icon: Icons.translate_rounded,
    iconColor: Color(0xFF6C4AB6),
    iconBackground: Color(0xFFF0EBFB),
    kind: OfflineResourceKind.vocabulary,
  ),
  audio(
    title: 'Audio Resources',
    description: 'Pronunciations, stories, instructions',
    icon: Icons.volume_up_rounded,
    iconColor: Color(0xFF258C83),
    iconBackground: Color(0xFFE8F5F2),
    kind: OfflineResourceKind.audio,
  ),
  worksheets(
    title: 'Worksheets',
    description: 'Printable worksheets and activities',
    icon: Icons.description_rounded,
    iconColor: Color(0xFFC77B12),
    iconBackground: Color(0xFFFFF7EA),
    kind: OfflineResourceKind.worksheets,
  ),
  aiVocabulary(
    title: 'AI Vocabulary',
    description: 'AI vocabulary and contextual examples',
    icon: Icons.auto_awesome_rounded,
    iconColor: Color(0xFF7B4BBF),
    iconBackground: Color(0xFFF3EEFC),
    kind: null,
  ),
  models(
    title: 'Models',
    description: 'Translation and speech models',
    icon: Icons.psychology_alt_rounded,
    iconColor: Color(0xFF6C4AB6),
    iconBackground: Color(0xFFF0EBFB),
    kind: OfflineResourceKind.languageModel,
  );

  const _SyncCategory({
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    this.kind,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final OfflineResourceKind? kind;
}

/// How one category currently stands, derived from real local reads.
enum _CategoryState {
  upToDate,
  needsUpdate,
  checking,
  downloading,
  missing,
  unavailableOffline,
  error,
}

class _CategoryVisual {
  const _CategoryVisual({
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

class _StatusVisual {
  const _StatusVisual({
    required this.color,
    required this.background,
    required this.icon,
    required this.headline,
    required this.message,
  });

  final Color color;
  final Color background;
  final IconData icon;
  final String headline;
  final String message;
}

_CategoryVisual _categoryVisual(_CategoryState state) {
  return switch (state) {
    _CategoryState.upToDate => const _CategoryVisual(
        color: AppColors.success,
        background: Color(0xFFF0F8F3),
        icon: Icons.check_circle_outline_rounded,
        label: 'Up to date',
      ),
    _CategoryState.needsUpdate => const _CategoryVisual(
        color: AppColors.warning,
        background: Color(0xFFFFF7EA),
        icon: Icons.system_update_alt_rounded,
        label: 'Needs update',
      ),
    _CategoryState.checking => const _CategoryVisual(
        color: AppColors.info,
        background: Color(0xFFF1F6FD),
        icon: Icons.sync_rounded,
        label: 'Checking',
      ),
    _CategoryState.downloading => const _CategoryVisual(
        color: AppColors.info,
        background: Color(0xFFF1F6FD),
        icon: Icons.cloud_download_outlined,
        label: 'Downloading',
      ),
    _CategoryState.missing => const _CategoryVisual(
        color: AppColors.warning,
        background: Color(0xFFFFF7EA),
        icon: Icons.error_outline_rounded,
        label: 'Missing',
      ),
    _CategoryState.unavailableOffline => const _CategoryVisual(
        color: AppColors.textSecondary,
        background: Color(0xFFF4F5F7),
        icon: Icons.wifi_off_rounded,
        label: 'Unavailable offline',
      ),
    _CategoryState.error => const _CategoryVisual(
        color: AppColors.error,
        background: Color(0xFFFFF1F0),
        icon: Icons.error_outline_rounded,
        label: 'Error',
      ),
  };
}

enum _HeaderAction { refresh, help }

class _Header extends StatelessWidget {
  const _Header({
    required this.connection,
    required this.onBack,
    required this.onRefresh,
    required this.onHelp,
  });

  final ConnectionStatus connection;
  final VoidCallback onBack;
  final Future<void> Function() onRefresh;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final bool offline = connection == ConnectionStatus.offline;
    final Color color = offline ? AppColors.error : AppColors.success;
    final String label = switch (connection) {
      ConnectionStatus.offline => 'Offline Mode',
      ConnectionStatus.online => 'Online',
      ConnectionStatus.unknown => 'Checking connection…',
    };
    final IconData icon = switch (connection) {
      ConnectionStatus.offline => Icons.wifi_off_rounded,
      ConnectionStatus.online => Icons.cloud_done_outlined,
      ConnectionStatus.unknown => Icons.wifi_rounded,
    };
    final Color background = offline
        ? const Color(0xFFFFF1F0)
        : (connection == ConnectionStatus.online
            ? const Color(0xFFF0F8F3)
            : const Color(0xFFF1F6FD));

    return Row(
      children: <Widget>[
        IconButton(
          tooltip: 'Back',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.brandNavy),
        ),
        Image.asset(
          AppAssets.loginBrandMark,
          height: 34,
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
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _ConnectionPill(
          icon: icon,
          label: label,
          color: color,
          background: background,
        ),
        const SizedBox(width: 4),
        PopupMenuButton<_HeaderAction>(
          icon: const Icon(Icons.more_vert_rounded, color: AppColors.brandNavy),
          tooltip: 'More options',
          onSelected: (_HeaderAction action) {
            switch (action) {
              case _HeaderAction.refresh:
                unawaited(onRefresh());
              case _HeaderAction.help:
                onHelp();
            }
          },
          itemBuilder: (BuildContext context) =>
              const <PopupMenuEntry<_HeaderAction>>[
            PopupMenuItem<_HeaderAction>(
              value: _HeaderAction.refresh,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.refresh_rounded),
                title: Text('Refresh'),
              ),
            ),
            PopupMenuItem<_HeaderAction>(
              value: _HeaderAction.help,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.help_outline_rounded),
                title: Text('Sync help'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({
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
      label: 'Connection: $label',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 150),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadius.pillAll,
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: color,
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

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFFDE3E1),
            ),
            child: const Icon(Icons.wifi_off_rounded, color: AppColors.error),
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'No internet connection',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.error,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Your downloaded classroom resources remain available.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: AppColors.brandBody,
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

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.lastSyncedAt,
    required this.resourcesReady,
    required this.errorMessage,
  });

  final SyncStatus status;
  final DateTime? lastSyncedAt;
  final bool resourcesReady;

  /// Detail shown under the headline when the last run failed.
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final _StatusVisual visual = _visual();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
      decoration: BoxDecoration(
        color: visual.background,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: visual.color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Current Status',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: AppColors.brandMuted,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: visual.color.withValues(alpha: 0.12),
                  border: Border.all(
                    color: visual.color.withValues(alpha: 0.18),
                    width: 6,
                  ),
                ),
                child: Icon(visual.icon, size: 32, color: visual.color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      visual.headline,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: visual.color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      visual.message,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        color: AppColors.brandBody,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              const Icon(
                Icons.history_rounded,
                size: 18,
                color: AppColors.brandMuted,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Last synced',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandNavy,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  lastSyncedAt == null
                      ? 'Never'
                      : _formatSyncTime(lastSyncedAt!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  _StatusVisual _visual() {
    switch (status.state) {
      case SyncState.checking:
        return const _StatusVisual(
          color: AppColors.info,
          background: Color(0xFFF1F6FD),
          icon: Icons.sync_rounded,
          headline: 'Checking for updates…',
          message: 'Comparing local content with what is available.',
        );
      case SyncState.uploading:
        return const _StatusVisual(
          color: AppColors.info,
          background: Color(0xFFF1F6FD),
          icon: Icons.upload_rounded,
          headline: 'Uploading local changes…',
          message: 'Sending pending local records.',
        );
      case SyncState.downloading:
        return const _StatusVisual(
          color: AppColors.info,
          background: Color(0xFFF1F6FD),
          icon: Icons.download_rounded,
          headline: 'Downloading updates…',
          message: 'Pulling the latest content onto this device.',
        );
      case SyncState.completed:
        if (resourcesReady) {
          return const _StatusVisual(
            color: AppColors.success,
            background: Color(0xFFF2FAF4),
            icon: Icons.check_circle_outline_rounded,
            headline: 'All content is up to date',
            message: 'Content is current on this device.',
          );
        }
        return const _StatusVisual(
          color: AppColors.warning,
          background: Color(0xFFFFF8ED),
          icon: Icons.cloud_done_outlined,
          headline: 'Sync completed',
          message: 'Your local records are synced. Some resource packs still '
              'need downloading.',
        );
      case SyncState.failed:
        return _StatusVisual(
          color: AppColors.error,
          background: const Color(0xFFFFF1F0),
          icon: Icons.error_outline_rounded,
          headline: 'Sync failed',
          message: errorMessage ?? 'Something went wrong. Please try again.',
        );
      case SyncState.syncing:
        return const _StatusVisual(
          color: AppColors.info,
          background: Color(0xFFF1F6FD),
          icon: Icons.sync_rounded,
          headline: 'Syncing…',
          message: 'Working through pending changes.',
        );
      case SyncState.pending:
        return const _StatusVisual(
          color: AppColors.warning,
          background: Color(0xFFFFF8ED),
          icon: Icons.cloud_off_outlined,
          headline: 'Changes waiting to sync',
          message: 'Connect to the internet to send your local changes.',
        );
      case SyncState.idle:
        if (lastSyncedAt == null) {
          return const _StatusVisual(
            color: AppColors.brandNavy,
            background: Color(0xFFF0F2FA),
            icon: Icons.cloud_outlined,
            headline: 'Not synced yet',
            message: 'Run Sync Now to keep your classroom content up to date.',
          );
        }
        if (resourcesReady) {
          return const _StatusVisual(
            color: AppColors.success,
            background: Color(0xFFF2FAF4),
            icon: Icons.check_circle_outline_rounded,
            headline: 'All content is up to date',
            message: 'Content is current on this device.',
          );
        }
        return const _StatusVisual(
          color: AppColors.warning,
          background: Color(0xFFFFF8ED),
          icon: Icons.cloud_done_outlined,
          headline: 'Sync completed',
          message: 'Local records are synced. Some resource packs still need '
              'downloading.',
        );
    }
  }

  static String _formatSyncTime(DateTime when) {
    final DateTime now = DateTime.now();
    final bool isToday = when.year == now.year &&
        when.month == now.month &&
        when.day == now.day;
    final String time = _twelveHour(when);

    if (isToday) return 'Today, $time';

    final DateTime yesterday = now.subtract(const Duration(days: 1));
    final bool isYesterday = when.year == yesterday.year &&
        when.month == yesterday.month &&
        when.day == yesterday.day;
    if (isYesterday) return 'Yesterday, $time';

    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[when.month - 1]} ${when.day}, $time';
  }

  static String _twelveHour(DateTime when) {
    final int hour24 = when.hour;
    final int hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final String period = hour24 < 12 ? 'AM' : 'PM';
    final String minute = when.minute.toString().padLeft(2, '0');
    return '$hour12:$minute $period';
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({
    required this.categories,
    required this.stateFor,
    required this.onTap,
  });

  final List<_SyncCategory> categories;
  final _CategoryState Function(_SyncCategory category) stateFor;
  final void Function(_SyncCategory category) onTap;

  @override
  Widget build(BuildContext context) {
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'What Gets Synced',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Content shared between your classroom and this device.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.brandBody),
                ),
              ],
            ),
          ),
          for (int i = 0; i < categories.length; i++) ...<Widget>[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            _CategoryRow(
              category: categories[i],
              visual: _categoryVisual(stateFor(categories[i])),
              onTap: () => onTap(categories[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.visual,
    required this.onTap,
  });

  final _SyncCategory category;
  final _CategoryVisual visual;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: category.title,
      hint: '${visual.label}. Open details.',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: category.iconBackground,
                      borderRadius: AppRadius.mdAll,
                    ),
                    child: Icon(category.icon, size: 27, color: category.iconColor),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          category.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.brandNavy,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          category.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.3,
                            color: AppColors.brandBody,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: visual.background,
                        borderRadius: AppRadius.pillAll,
                        border: Border.all(
                          color: visual.color.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(visual.icon, size: 15, color: visual.color),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              visual.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: visual.color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: AppColors.brandMuted,
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

class _ResourceDetailSheet extends StatelessWidget {
  const _ResourceDetailSheet({
    required this.category,
    required this.state,
    required this.available,
    required this.offline,
    required this.lastSyncedAt,
    required this.onSyncNow,
  });

  final _SyncCategory category;
  final _CategoryState state;
  final bool available;
  final bool offline;
  final DateTime? lastSyncedAt;
  final VoidCallback onSyncNow;

  @override
  Widget build(BuildContext context) {
    final _CategoryVisual visual = _categoryVisual(state);

    final String offlineValue;
    if (category.kind == null) {
      offlineValue = 'Information unavailable';
    } else {
      offlineValue = available ? 'Available' : 'Not available offline';
    }

    final String statusValue = visual.label;
    final String sizeValue = 'Information unavailable';
    final String updatedValue = lastSyncedAt == null
        ? 'Information unavailable'
        : _StatusCard._formatSyncTime(lastSyncedAt!);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                category.title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                category.description,
                style: const TextStyle(fontSize: 13.5, color: AppColors.brandBody),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                decoration: BoxDecoration(
                  color: visual.background,
                  borderRadius: AppRadius.mdAll,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(visual.icon, size: 16, color: visual.color),
                    const SizedBox(width: 6),
                    Text(
                      visual.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: visual.color,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(color: AppColors.authFieldBorder),
                ),
                child: Column(
                  children: <Widget>[
                    _DetailRow(label: 'Status', value: statusValue),
                    _DetailRow(label: 'Offline', value: offlineValue),
                    _DetailRow(label: 'Local size', value: sizeValue),
                    _DetailRow(label: 'Last updated', value: updatedValue),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _actionHint(),
                style: const TextStyle(fontSize: 13, height: 1.45,
                    color: AppColors.brandBody),
              ),
              if (category.kind != null && !available && !offline) ...<Widget>[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onSyncNow,
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('Sync Now'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _actionHint() {
    if (category.kind == null) {
      return 'No probe in this build measures AI vocabulary yet, so its size '
          'and update state are not shown. Information unavailable.';
    }
    if (available) {
      return 'This content is current on this device. Nothing to download.';
    }
    if (offline) {
      return 'Connect to the internet and run Sync Now to download this '
          'content. Your downloaded resources keep working offline meanwhile.';
    }
    return 'Run Sync Now to download this content to this device.';
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.brandNavy,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: AppColors.brandBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DataFriendlyCard extends StatelessWidget {
  const _DataFriendlyCard();

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
            child: const Icon(Icons.data_saver_on_rounded, color: AppColors.info),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Data-friendly sync',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Sync only downloads required updates to save data.',
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
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.brandBody),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutSyncSheet extends StatelessWidget {
  const _AboutSyncSheet();

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
                'About Content Sync',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                ),
              ),
              const SizedBox(height: 12),
              _paragraph(
                'Content Sync shares this classroom\'s records with the '
                'server and pulls updates back. Every read shown here comes '
                'from the device itself.',
              ),
              _paragraph(
                'Sync Now uploads this device\'s pending records to the '
                'server and downloads updates. If the server cannot be '
                'reached, the run says so — nothing is claimed that did not '
                'actually happen.',
              ),
              _paragraph(
                'When there is no internet connection the app stays fully '
                'usable and never claims that data was synchronised.',
              ),
              _paragraph(
                'Resource packs, target-language audio and on-device AI '
                'models do not ship with this build yet. The list above '
                'says so instead of showing a fake “up to date” state.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _paragraph(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14.5,
          height: 1.5,
          color: AppColors.brandBody,
        ),
      ),
    );
  }
}

class _SyncSkeleton extends StatelessWidget {
  const _SyncSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        _Header(
          connection: ConnectionStatus.unknown,
          onBack: () {},
          onRefresh: _noop,
          onHelp: _noop,
        ),
        const SizedBox(height: 18),
        const Text(
          'Content Sync',
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
          'Keep your classroom content up to date.',
          style: TextStyle(
            fontSize: 16,
            color: AppColors.brandBody,
          ),
        ),
        const SizedBox(height: 22),
        for (int i = 0; i < 4; i++) ...<Widget>[
          Container(height: i == 0 ? 180 : 96, color: Colors.black12),
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
              'Could not read the sync state.',
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