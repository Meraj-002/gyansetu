import '../storage/secure_storage_service.dart';

/// Where the last successful sync record lives.
///
/// Kept deliberately tiny: the timestamp is the one piece of sync state that
/// must survive a restart. Resource-level metadata joins this store once a real
/// backend exists to generate it — the UI never invents it.
abstract interface class SyncMetadataStore {
  /// The last successful sync, or null when nothing has ever synced.
  Future<DateTime?> lastSyncedAt();

  /// Records a successful sync. The screen restores the timestamp on reopen.
  Future<void> saveLastSyncedAt(DateTime when);
}

/// Timestamp kept in the app's secure store, beside the session and the lesson
/// download records.
class LocalSyncMetadataStore implements SyncMetadataStore {
  LocalSyncMetadataStore(this._storage);

  static const String _lastSyncedAtKey = 'sync.last_synced_at';

  final SecureStorageService _storage;

  @override
  Future<DateTime?> lastSyncedAt() async {
    final String? raw = await _storage.read(_lastSyncedAtKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  @override
  Future<void> saveLastSyncedAt(DateTime when) async {
    await _storage.write(_lastSyncedAtKey, when.toIso8601String());
  }
}