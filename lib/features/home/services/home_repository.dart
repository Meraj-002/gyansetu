// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore, so `this._session` is not expressible.
import '../../../core/utils/app_logger.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../auth/services/auth_session_store.dart';
import '../../setup/models/classroom_setup.dart';
import '../../setup/models/offline_resource_status.dart';
import '../../setup/services/classroom_setup_repository.dart';
import '../../setup/services/offline_resource_manager.dart';
import '../models/home_dashboard.dart';
import '../../lessons/services/lesson_repository.dart';
import 'home_repositories.dart';

/// Assembles everything the dashboard needs.
///
/// The screen asks this one object for a [HomeDashboard]; it never queries a
/// database or reaches for a service itself. A `RemoteHomeRepository` can sit
/// alongside the local one later without the screen changing.
abstract interface class HomeRepository {
  Future<HomeDashboard> load({DateTime? now});
}

/// Reads everything from the device.
///
/// Nothing here touches the network. Home has to render on a handset that has
/// never been online since setup, so every field comes from local state and the
/// connection is used only to describe what could be synced.
class LocalHomeRepository implements HomeRepository {
  LocalHomeRepository({
    required AuthSessionStore session,
    required ClassroomSetupRepository classrooms,
    required LessonRepository lessons,
    required ProgressRepository progress,
    required NotificationRepository notifications,
    required OfflineResourceManager resources,
    required ConnectivityService connectivity,
  })  : _session = session,
        _classrooms = classrooms,
        _lessons = lessons,
        _progress = progress,
        _notifications = notifications,
        _resources = resources,
        _connectivity = connectivity;

  final AuthSessionStore _session;
  final ClassroomSetupRepository _classrooms;
  final LessonRepository _lessons;
  final ProgressRepository _progress;
  final NotificationRepository _notifications;
  final OfflineResourceManager _resources;
  final ConnectivityService _connectivity;

  @override
  Future<HomeDashboard> load({DateTime? now}) async {
    final teacher = await _session.account();
    final String teacherId = teacher?.id ?? 'local-teacher';

    final ClassroomSetup? classroom = await _classrooms.load(teacherId);

    // Without a classroom there is nothing to plan, stock or measure. The
    // dashboard shows a setup prompt rather than inventing any of it.
    if (classroom == null) {
      return HomeDashboard(
        teacherName: teacher?.displayName,
        classroom: null,
        todayLesson: null,
        progress: const LearningProgress.empty(),
        offlineState: HomeOfflineState.unknown,
        offlineStatus: const OfflineResourceStatus.unknown(),
        unreadNotifications: await _unread(teacherId),
      );
    }

    final OfflineResourceStatus status = await _checkResources(classroom);

    return HomeDashboard(
      teacherName: teacher?.displayName,
      classroom: classroom,
      todayLesson: await _lessons.lessonForToday(classroom, on: now),
      progress: await _progress.today(teacherId, on: now),
      offlineState: _stateFor(status, _connectivity.status),
      offlineStatus: status,
      unreadNotifications: await _unread(teacherId),
    );
  }

  Future<int> _unread(String teacherId) async {
    try {
      return await _notifications.unreadCount(teacherId);
    } on Object catch (error) {
      AppLogger.error('unread notification count failed', error: error);
      return 0;
    }
  }

  Future<OfflineResourceStatus> _checkResources(ClassroomSetup classroom) async {
    try {
      return await _resources.check(classroom.resourceProfile);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'offline resource check failed',
        error: error,
        stackTrace: stackTrace,
      );
      return const OfflineResourceStatus(readiness: OfflineReadiness.failed);
    }
  }

  /// Turns the resource check and the connection into what the UI may claim.
  ///
  /// "Offline Ready" is only ever shown when the check found everything, and
  /// partial stock is called partial rather than rounded up.
  static HomeOfflineState _stateFor(
    OfflineResourceStatus status,
    ConnectionStatus connection,
  ) {
    return switch (status.readiness) {
      OfflineReadiness.ready => HomeOfflineState.offlineReady,
      OfflineReadiness.failed => HomeOfflineState.error,
      OfflineReadiness.preparing => HomeOfflineState.unknown,
      OfflineReadiness.unknown => HomeOfflineState.unknown,
      OfflineReadiness.needsSync when connection == ConnectionStatus.online =>
        HomeOfflineState.onlineSyncAvailable,
      OfflineReadiness.needsSync =>
        status.resources.any((OfflineResource r) => r.available)
            ? HomeOfflineState.partial
            : HomeOfflineState.missing,
    };
  }
}
