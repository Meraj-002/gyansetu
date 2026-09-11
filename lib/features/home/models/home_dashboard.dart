import '../../../models/lesson.dart';
import '../../setup/models/classroom_setup.dart';
import '../../setup/models/offline_resource_status.dart';

/// Today's teaching progress, read from local records.
class LearningProgress {
  const LearningProgress({
    required this.lessonsCompleted,
    required this.lessonsPlanned,
    required this.studentsEngaged,
    required this.assessmentPercent,
  });

  /// Nothing recorded yet — the dashboard shows an empty state rather than
  /// zeros that look like failure.
  const LearningProgress.empty()
      : lessonsCompleted = 0,
        lessonsPlanned = 0,
        studentsEngaged = 0,
        assessmentPercent = null;

  final int lessonsCompleted;
  final int lessonsPlanned;
  final int studentsEngaged;

  /// Null when no assessment has been taken today.
  final int? assessmentPercent;

  bool get hasData =>
      lessonsPlanned > 0 || studentsEngaged > 0 || assessmentPercent != null;

  /// 0..1, for the lessons bar. Zero when nothing is planned.
  double get lessonFraction =>
      lessonsPlanned == 0 ? 0 : (lessonsCompleted / lessonsPlanned).clamp(0, 1);
}

/// How the dashboard should describe offline readiness.
///
/// Derived from the resource check and the connection, never assumed.
enum HomeOfflineState {
  /// Everything needed is on the device.
  offlineReady,

  /// Online, and the device still has content to fetch.
  onlineSyncAvailable,

  /// Some content is present, some is not.
  partial,

  /// Nothing has been provisioned yet.
  missing,

  /// The check itself failed.
  error,

  /// Not determined yet.
  unknown;

  String get title => switch (this) {
        HomeOfflineState.offlineReady => 'Offline Mode Ready',
        HomeOfflineState.onlineSyncAvailable => 'Sync available',
        HomeOfflineState.partial => 'Offline setup incomplete',
        HomeOfflineState.missing => 'Offline resources not ready',
        HomeOfflineState.error => 'Could not check resources',
        HomeOfflineState.unknown => 'Checking resources',
      };

  /// Short label for the classroom strip at the top of the dashboard.
  String get shortLabel => switch (this) {
        HomeOfflineState.offlineReady => 'Offline Ready',
        HomeOfflineState.onlineSyncAvailable => 'Sync available',
        HomeOfflineState.partial => 'Offline setup incomplete',
        HomeOfflineState.missing => 'Offline not ready',
        HomeOfflineState.error => 'Status unavailable',
        HomeOfflineState.unknown => 'Checking…',
      };

  String get description => switch (this) {
        HomeOfflineState.offlineReady =>
          'All essential classroom resources are available on this device.',
        HomeOfflineState.onlineSyncAvailable =>
          'You are online. Remaining classroom resources can be downloaded now.',
        HomeOfflineState.partial =>
          'Some classroom resources still need to be prepared.',
        HomeOfflineState.missing =>
          'Offline resources are not ready yet. Connect to the internet to '
              'prepare them.',
        HomeOfflineState.error =>
          'We could not read the offline resources on this device.',
        HomeOfflineState.unknown => 'Checking what is available on this device.',
      };
}

/// Everything the dashboard renders, assembled by `HomeRepository`.
class HomeDashboard {
  const HomeDashboard({
    required this.teacherName,
    required this.classroom,
    required this.todayLesson,
    required this.progress,
    required this.offlineState,
    required this.offlineStatus,
    required this.unreadNotifications,
  });

  /// Display name from the signed-in session; null falls back to "Teacher".
  final String? teacherName;

  /// Null when setup has not been completed, which the dashboard must show
  /// rather than inventing a classroom.
  final ClassroomSetup? classroom;

  /// Null when nothing is planned for today. The same [Lesson] the library
  /// and lesson detail use — there is no separate dashboard copy.
  final Lesson? todayLesson;

  final LearningProgress progress;
  final HomeOfflineState offlineState;
  final OfflineResourceStatus offlineStatus;
  final int unreadNotifications;

  bool get needsClassroomSetup => classroom == null;
}
