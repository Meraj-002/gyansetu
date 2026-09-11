import 'package:gyan_setu_ai/features/lessons/services/lesson_download_service.dart';
import 'package:gyan_setu_ai/features/lessons/services/lesson_repository.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/models/lesson.dart';

const String kTeacherId = 'teacher-1';

ClassroomSetup testClassroom({
  int classLevel = 1,
  TargetLanguage target = TargetLanguage.santali,
  TeachingMedium medium = TeachingMedium.hindi,
}) =>
    ClassroomSetup(
      teacherId: kTeacherId,
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
    );

Lesson testLesson({
  required String id,
  required String title,
  ClassroomSubject subject = ClassroomSubject.numeracy,
  int classNumber = 1,
  String outcome = 'An outcome.',
  int minutes = 10,
  int order = 1,
  int daysOld = 0,
}) =>
    Lesson(
      id: id,
      title: title,
      description: '$title description',
      subject: subject,
      classNumber: classNumber,
      learningOutcome: outcome,
      durationMinutes: minutes,
      lessonOrder: order,
      createdAt: DateTime(2026, 8, 1).subtract(Duration(days: daysOld)),
      updatedAt: DateTime(2026, 8, 1).subtract(Duration(days: daysOld)),
    );

/// A catalogue the test controls completely.
class FakeLessonRepository implements LessonRepository {
  FakeLessonRepository({
    List<Lesson>? catalogue,
    this.throwOnLessons = false,
    this.latency = Duration.zero,
  }) : catalogue = catalogue ?? <Lesson>[];

  List<Lesson> catalogue;
  bool throwOnLessons;

  /// Holds the load open so the first-load skeleton is observable.
  Duration latency;
  Set<String> offlineIds = <String>{};

  @override
  Future<List<Lesson>> lessons() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (throwOnLessons) throw StateError('catalogue unavailable');
    return catalogue;
  }

  @override
  Future<Lesson?> lessonById(String id) async {
    for (final Lesson l in catalogue) {
      if (l.id == id) return l;
    }
    return null;
  }

  @override
  Future<Lesson?> lessonForToday(
    ClassroomSetup classroom, {
    DateTime? on,
  }) async =>
      catalogue.isEmpty ? null : catalogue.first;

  @override
  Future<bool> isAvailableOffline(String lessonId) async =>
      offlineIds.contains(lessonId);
}

class FakeProgressRepository implements LessonProgressRepository {
  FakeProgressRepository([Map<String, int>? seed])
      : _values = Map<String, int>.from(seed ?? <String, int>{});

  final Map<String, int> _values;

  @override
  Future<Map<String, int>> all() async => _values;

  @override
  Future<int> percentFor(String lessonId) async => _values[lessonId] ?? 0;

  @override
  Future<void> setPercent(String lessonId, int percent) async =>
      _values[lessonId] = percent;
}

class FakeDownloadRepository implements LessonDownloadRepository {
  FakeDownloadRepository([Set<String>? seed])
      : _ids = Set<String>.from(seed ?? <String>{});

  final Set<String> _ids;

  @override
  Future<Set<String>> downloadedIds() async => _ids;

  @override
  Future<void> markDownloaded(String lessonId) async => _ids.add(lessonId);

  @override
  Future<void> remove(String lessonId) async => _ids.remove(lessonId);
}

/// Download service whose outcome the test dictates.
class FakeDownloadService implements LessonDownloadService {
  FakeDownloadService({
    this.outcome = const DownloadCompleted(),
    this.hasRoom = true,
    this.latency = Duration.zero,
    this.downloads,
  });

  DownloadOutcome outcome;
  bool hasRoom;
  Duration latency;
  FakeDownloadRepository? downloads;

  int downloadCalls = 0;

  @override
  Future<bool> hasRoomFor(Lesson lesson) async => hasRoom;

  @override
  Future<DownloadOutcome> download(Lesson lesson) async {
    downloadCalls++;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (outcome is DownloadCompleted) {
      await downloads?.markDownloaded(lesson.id);
    }
    return outcome;
  }

  @override
  Future<void> remove(Lesson lesson) async => downloads?.remove(lesson.id);
}

