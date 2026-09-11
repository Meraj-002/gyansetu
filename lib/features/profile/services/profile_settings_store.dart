import '../../../services/storage/secure_storage_service.dart';
import '../models/profile_settings.dart';

/// Where the teacher's accessibility and audio preferences live.
///
/// A feature-level store over the app's single persistent key-value channel,
/// mirroring the pattern of [LocalSyncMetadataStore]: the screen never reads
/// from storage directly, and tests substitute an in-memory implementation.
abstract interface class ProfileSettingsStore {
  Future<ProfileSettings> load();

  /// Returns false when the value could not be persisted; the UI must then
  /// keep showing the old preference rather than pretend it saved.
  Future<bool> save(ProfileSettings settings);
}

/// Device-persisted implementation via secure storage.
class LocalProfileSettingsStore implements ProfileSettingsStore {
  const LocalProfileSettingsStore(this._storage);

  static const String _key = 'profile.settings';

  final SecureStorageService _storage;

  @override
  Future<ProfileSettings> load() async =>
      ProfileSettings.tryDecode(await _storage.read(_key));

  @override
  Future<bool> save(ProfileSettings settings) =>
      _storage.write(_key, settings.encode());
}