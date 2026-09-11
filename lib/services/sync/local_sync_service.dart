import 'dart:async';

import '../../core/errors/app_exception.dart';
import '../../core/utils/result.dart';
import 'sync_metadata_store.dart';
import 'sync_service.dart';
import 'sync_status.dart';

/// DEVELOPMENT MOCK ONLY.
/// Replace with a FastAPI-backed implementation later.
///
/// Walks the real sync state machine — checking → uploading → downloading →
/// completed — with short simulated delays, and persists the completion
/// timestamp through [SyncMetadataStore]. It never claims that real bytes went
/// to a real server: nothing leaves this device. The [SyncService] boundary is
/// the seam a FastAPI implementation will slot into without the UI changing.
class DevSyncService implements SyncService {
  DevSyncService({
    required this.metadata,
    this.stepDelay = const Duration(milliseconds: 450),
    this.failTimes = 0,
    this.failureMessage = 'Could not reach the sync server.',
  });

  final SyncMetadataStore metadata;

  /// How long each simulated transfer phase lasts.
  final Duration stepDelay;

  /// How many runs fail before one succeeds. Test hook: makes the failed state
  /// and Retry reachable without needing a real server to be down.
  int failTimes;

  final String failureMessage;

  SyncStatus _status = const SyncStatus(state: SyncState.idle);
  final StreamController<SyncStatus> _stream =
      StreamController<SyncStatus>.broadcast();

  @override
  SyncStatus get status => _status;

  @override
  Stream<SyncStatus> get onStatusChanged => _stream.stream;

  bool get _inFlight =>
      _status.state == SyncState.checking ||
      _status.state == SyncState.uploading ||
      _status.state == SyncState.downloading ||
      _status.state == SyncState.syncing;

  @override
  Future<Result<SyncStatus>> syncNow() async {
    if (_inFlight) {
      return const Err<SyncStatus>(
        SyncException('A sync is already running.'),
      );
    }

    _emit(const SyncStatus(
      state: SyncState.checking,
      message: 'Checking for updates…',
      progress: 0.1,
    ));
    await _pause(stepDelay);

    if (failTimes > 0) {
      failTimes -= 1;
      _emit(SyncStatus(state: SyncState.failed, message: failureMessage));
      return Err<SyncStatus>(SyncException(failureMessage));
    }

    _emit(const SyncStatus(
      state: SyncState.uploading,
      message: 'Uploading local changes…',
      progress: 0.35,
    ));
    await _pause(stepDelay);

    _emit(const SyncStatus(
      state: SyncState.downloading,
      message: 'Downloading updates…',
      progress: 0.7,
    ));
    await _pause(stepDelay);

    final DateTime done = DateTime.now();
    await metadata.saveLastSyncedAt(done);
    _emit(SyncStatus(
      state: SyncState.completed,
      message: 'All content is up to date',
      lastSyncedAt: done,
      progress: 1,
    ));
    return Ok<SyncStatus>(_status);
  }

  @override
  Future<Result<void>> downloadPack(String packId) async {
    // DEVELOPMENT MOCK ONLY: no content pack exists on the server yet, so this
    // never pretends a download happened.
    return const Err<void>(
      SyncException(
        'Content packs cannot be downloaded in this development build.',
      ),
    );
  }

  @override
  Future<Result<void>> cancel() async {
    return const Ok<void>(null);
  }

  Future<void> _pause(Duration duration) async {
    if (duration <= Duration.zero) return;
    await Future<void>.delayed(duration);
  }

  void _emit(SyncStatus next) {
    _status = next;
    if (!_stream.isClosed) _stream.add(next);
  }

  Future<void> dispose() async {
    await _stream.close();
  }
}