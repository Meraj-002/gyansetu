import '../../../core/utils/app_logger.dart';
import '../data/classroom_setup_storage.dart';
import '../models/classroom_setup.dart';

/// How the rest of the app reads and writes a classroom configuration.
///
/// The screen talks to this, never to storage. When the FastAPI backend exists,
/// a remote implementation slots in beside the local one and the UI is
/// untouched.
abstract interface class ClassroomSetupRepository {
  Future<ClassroomSetup?> load(String teacherId);

  /// Persists [setup]. Returns false when nothing was written.
  Future<bool> save(ClassroomSetup setup);

  /// Whether this teacher has finished setup, used to decide where sign-in
  /// lands.
  Future<bool> isSetupComplete(String teacherId);

  Future<void> clear(String teacherId);
}

/// Device-local implementation. This is the whole story today: there is no
/// server to talk to, so every save is local and marked [pendingSync] for the
/// first sync run that ever happens.
class LocalClassroomSetupRepository implements ClassroomSetupRepository {
  LocalClassroomSetupRepository(this._storage);

  final ClassroomSetupStorage _storage;

  @override
  Future<ClassroomSetup?> load(String teacherId) => _storage.load(teacherId);

  @override
  Future<bool> save(ClassroomSetup setup) async {
    final bool ok = await _storage.save(setup);
    if (!ok) {
      AppLogger.error('classroom setup was not persisted');
    }
    return ok;
  }

  @override
  Future<bool> isSetupComplete(String teacherId) async =>
      (await _storage.load(teacherId))?.setupCompleted ?? false;

  @override
  Future<void> clear(String teacherId) => _storage.clear(teacherId);
}
