import 'package:gyan_setu_ai/features/setup/data/classroom_setup_storage.dart';
import 'package:gyan_setu_ai/features/setup/data/location_data_source.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/features/setup/models/location.dart';
import 'package:gyan_setu_ai/features/setup/models/offline_resource_status.dart';
import 'package:gyan_setu_ai/features/setup/services/classroom_setup_repository.dart';
import 'package:gyan_setu_ai/services/audio/language_audio_service.dart';

const String kTestTeacherId = 'teacher-test-1';

/// Two districts with distinct blocks, which is all that is needed to prove
/// the dependency between them.
final District kDumka = District(
  id: 'dumka',
  name: 'Dumka',
  blocks: const <Block>[
    Block(id: 'dumka.jama', name: 'Jama', districtId: 'dumka'),
    Block(id: 'dumka.masalia', name: 'Masalia', districtId: 'dumka'),
  ],
);

final District kRanchi = District(
  id: 'ranchi',
  name: 'Ranchi',
  blocks: const <Block>[
    Block(id: 'ranchi.kanke', name: 'Kanke', districtId: 'ranchi'),
    Block(id: 'ranchi.namkum', name: 'Namkum', districtId: 'ranchi'),
    Block(id: 'ranchi.ratu', name: 'Ratu', districtId: 'ranchi'),
  ],
);

LocationDataSource testLocations() =>
    StaticLocationDataSource(<District>[kDumka, kRanchi]);

/// A repository over in-memory storage, with a hook for save failure.
class TestRepository implements ClassroomSetupRepository {
  TestRepository({ClassroomSetup? existing, this.failOnSave = false}) {
    if (existing != null) _records[existing.teacherId] = existing;
  }

  bool failOnSave;
  final Map<String, ClassroomSetup> _records = <String, ClassroomSetup>{};

  int saveCalls = 0;
  ClassroomSetup? lastSaved;

  ClassroomSetup? recordFor(String teacherId) => _records[teacherId];

  @override
  Future<ClassroomSetup?> load(String teacherId) async => _records[teacherId];

  @override
  Future<bool> save(ClassroomSetup setup) async {
    saveCalls++;
    if (failOnSave) return false;
    lastSaved = setup;
    _records[setup.teacherId] = setup;
    return true;
  }

  @override
  Future<bool> isSetupComplete(String teacherId) async =>
      _records[teacherId]?.setupCompleted ?? false;

  @override
  Future<void> clear(String teacherId) async => _records.remove(teacherId);
}

/// Audio service whose availability the test chooses.
class TestAudioService implements LanguageAudioService {
  TestAudioService({this.available = false});

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
  String samplePhrase({TargetLanguage? target, TeachingMedium? medium}) =>
      'sample';

  @override
  Future<void> stop() async => stopCalls++;
}

/// Offline status the test dictates.
const OfflineResourceStatus kResourcesReady = OfflineResourceStatus(
  readiness: OfflineReadiness.ready,
  resources: <OfflineResource>[
    OfflineResource(kind: OfflineResourceKind.lessons, available: true),
  ],
  message: 'Everything this classroom needs is on this device.',
);

const OfflineResourceStatus kResourcesPending = OfflineResourceStatus(
  readiness: OfflineReadiness.needsSync,
  resources: <OfflineResource>[
    OfflineResource(
      kind: OfflineResourceKind.lessons,
      available: false,
      detail: 'Not bundled with this build',
    ),
  ],
  message: 'Offline resources will be available after synchronisation.',
);

/// A completed setup, for the "returning teacher" path.
ClassroomSetup existingSetup() => ClassroomSetup(
      teacherId: kTestTeacherId,
      schoolName: 'Govt. Primary School, Kanke',
      districtId: kRanchi.id,
      districtName: kRanchi.name,
      blockId: 'ranchi.namkum',
      blockName: 'Namkum',
      teachingMedium: TeachingMedium.english,
      targetLanguage: TargetLanguage.ho,
      classLevel: 4,
      subjects: const <ClassroomSubject>{ClassroomSubject.numeracy},
      setupCompleted: true,
      setupCompletedAt: DateTime(2026, 8, 1),
    );

/// Storage double used by the storage-contract tests.
MemoryClassroomSetupStorage memorySetupStorage({bool failOnSave = false}) =>
    MemoryClassroomSetupStorage(failOnSave: failOnSave);
