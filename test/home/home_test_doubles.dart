import 'package:gyan_setu_ai/features/home/models/home_dashboard.dart';
import 'package:gyan_setu_ai/features/home/services/home_repository.dart';
import 'package:gyan_setu_ai/features/lessons/services/lesson_repository.dart';
import 'package:gyan_setu_ai/models/lesson.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/features/setup/models/offline_resource_status.dart';
import 'package:gyan_setu_ai/services/audio/language_audio_service.dart';

/// A configured classroom for a teacher who has finished setup.
ClassroomSetup testClassroom({
  int classLevel = 1,
  TargetLanguage target = TargetLanguage.santali,
  TeachingMedium medium = TeachingMedium.hindi,
}) =>
    ClassroomSetup(
      teacherId: 'teacher-1',
      schoolName: 'Govt. Primary School, Jama',
      districtId: 'dumka',
      districtName: 'Dumka',
      blockId: 'dumka.jama',
      blockName: 'Jama',
      teachingMedium: medium,
      targetLanguage: target,
      classLevel: classLevel,
      subjects: const <ClassroomSubject>{
        ClassroomSubject.foundationalLiteracy,
        ClassroomSubject.numeracy,
      },
      setupCompleted: true,
      setupCompletedAt: null,
    );

final Lesson testLesson = Lesson(
  id: 'c1-num-counting-1-10',
  title: 'Counting 1–10',
  description: 'Counting practice.',
  subject: ClassroomSubject.numeracy,
  classNumber: 1,
  learningOutcome: 'Child can count objects from 1 to 10.',
  durationMinutes: 10,
  lessonOrder: 1,
  createdAt: DateTime(2026, 8, 1),
  updatedAt: DateTime(2026, 8, 1),
);

const LearningProgress testProgress = LearningProgress(
  lessonsCompleted: 2,
  lessonsPlanned: 3,
  studentsEngaged: 24,
  assessmentPercent: 78,
);

/// Returns whatever the test asks for, so every dashboard state is reachable.
class FakeHomeRepository implements HomeRepository {
  FakeHomeRepository({
    this.teacherName = 'Meraj',
    ClassroomSetup? classroom,
    Lesson? lesson,
    this.progress = testProgress,
    this.offlineState = HomeOfflineState.offlineReady,
    this.unread = 0,
    this.throwOnLoad = false,
    this.latency = Duration.zero,
  })  : classroom = classroom ?? testClassroom(),
        lesson = lesson ?? testLesson;

  String? teacherName;
  ClassroomSetup? classroom;
  Lesson? lesson;
  LearningProgress progress;
  HomeOfflineState offlineState;
  int unread;
  bool throwOnLoad;

  /// Holds the load open so the first-load skeleton is observable.
  Duration latency;

  int loadCalls = 0;

  @override
  Future<HomeDashboard> load({DateTime? now}) async {
    loadCalls++;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (throwOnLoad) throw StateError('dashboard unavailable');
    return HomeDashboard(
      teacherName: teacherName,
      classroom: classroom,
      todayLesson: classroom == null ? null : lesson,
      progress: progress,
      offlineState: offlineState,
      offlineStatus: const OfflineResourceStatus.unknown(),
      unreadNotifications: unread,
    );
  }
}

/// Lesson availability the test dictates.
class FakeLessonRepository implements LessonRepository {
  FakeLessonRepository({this.availableOffline = false, this.lesson});

  bool availableOffline;
  Lesson? lesson;
  int availabilityChecks = 0;

  @override
  Future<List<Lesson>> lessons() async =>
      <Lesson>[?lesson];

  @override
  Future<Lesson?> lessonById(String id) async =>
      lesson?.id == id ? lesson : null;

  @override
  Future<Lesson?> lessonForToday(
    ClassroomSetup classroom, {
    DateTime? on,
  }) async =>
      lesson;

  @override
  Future<bool> isAvailableOffline(String lessonId) async {
    availabilityChecks++;
    return availableOffline;
  }
}

/// Audio whose availability the test chooses.
class FakeHomeAudioService implements LanguageAudioService {
  FakeHomeAudioService({this.available = false});

  bool available;
  int playCalls = 0;
  int stopCalls = 0;

  @override
  Future<bool> canPlay({TargetLanguage? target, TeachingMedium? medium}) async =>
      available;

  @override
  Future<AudioPlaybackResult> play({
    TargetLanguage? target,
    TeachingMedium? medium,
  }) async {
    playCalls++;
    if (available) return const AudioPlaying();
    return const AudioUnavailable(
      AudioUnavailableReason.noVoice,
      'Audio for this language is not on this device yet.',
    );
  }

  @override
  String samplePhrase({TargetLanguage? target, TeachingMedium? medium}) => 'x';

  @override
  Future<void> stop() async => stopCalls++;
}
