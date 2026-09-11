import '../../core/utils/result.dart';
import 'sync_status.dart';

/// Contract for reconciling on-device data with the server.
///
/// The app writes locally first and syncs afterwards, so this service is never
/// on the critical path of a teacher's action — it runs in the background and
/// reports progress through [onStatusChanged].
abstract interface class SyncService {
  SyncStatus get status;

  Stream<SyncStatus> get onStatusChanged;

  /// Pushes queued local changes, then pulls server updates.
  Future<Result<SyncStatus>> syncNow();

  /// Downloads a content pack for offline use.
  Future<Result<void>> downloadPack(String packId);

  /// Abandons an in-flight run. Queued changes stay queued.
  Future<Result<void>> cancel();
}
