import '../models/home_dashboard.dart';

/// Where today's teaching progress comes from.
abstract interface class ProgressRepository {
  Future<LearningProgress> today(String teacherId, {DateTime? on});
}

/// Unread counts for the bell in the header.
abstract interface class NotificationRepository {
  Future<int> unreadCount(String teacherId);
}

/// Development progress source.
///
/// DEVELOPMENT DATA. Nothing writes progress yet — lessons, assessments and
/// attendance are not built — so these figures are generated here and nowhere
/// else. No widget contains a hard-coded count.
///
/// REPLACE WITH: a progress table written by the lesson and assessment
/// features, read here.
class DevelopmentProgressRepository implements ProgressRepository {
  const DevelopmentProgressRepository({this.hasData = true});

  final bool hasData;

  @override
  Future<LearningProgress> today(String teacherId, {DateTime? on}) async {
    if (!hasData) return const LearningProgress.empty();
    return const LearningProgress(
      lessonsCompleted: 2,
      lessonsPlanned: 3,
      studentsEngaged: 24,
      assessmentPercent: 78,
    );
  }
}

/// Development notification source.
///
/// DEVELOPMENT DATA. There is no notification store and no push
/// infrastructure; this reports nothing unread so the badge stays honest.
///
/// REPLACE WITH: a local notification table fed by sync.
class DevelopmentNotificationRepository implements NotificationRepository {
  const DevelopmentNotificationRepository({this.unread = 0});

  final int unread;

  @override
  Future<int> unreadCount(String teacherId) async => unread;
}
