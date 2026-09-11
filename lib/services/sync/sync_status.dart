/// Where a sync run currently stands.
enum SyncState {
  /// Nothing to do; local and server agree as of [SyncStatus.lastSyncedAt].
  idle,

  /// A run is in progress (generic in-flight state, kept for compatibility).
  syncing,

  /// Local changes are queued but the device is offline.
  pending,

  /// The last run failed; it will be retried.
  failed,

  /// A run is working out what has changed before transferring anything.
  checking,

  /// A run is pushing local changes to the server.
  uploading,

  /// A run is pulling updates from the server onto the device.
  downloading,

  /// A run finished without error as of [SyncStatus.lastSyncedAt].
  completed,
}

/// Snapshot of synchronisation state, suitable for rendering in the UI.
class SyncStatus {
  const SyncStatus({
    required this.state,
    this.pendingChanges = 0,
    this.lastSyncedAt,
    this.message,
    this.progress,
  });

  const SyncStatus.idle() : this._(state: SyncState.idle);

  const SyncStatus._({
    required this.state,
    this.pendingChanges = 0,
    this.lastSyncedAt,
    this.message,
    this.progress,
  });

  final SyncState state;

  /// Number of local records not yet accepted by the server.
  final int pendingChanges;

  final DateTime? lastSyncedAt;

  /// Human-readable detail for the failure case, or the run's headline.
  final String? message;

  /// 0.0 → 1.0 for an in-flight run; null when progress is not meaningful.
  final double? progress;

  /// The failure detail, for the [SyncState.failed] case.
  String? get errorMessage => message;

  bool get hasPendingWork => pendingChanges > 0;
}
