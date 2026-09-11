import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/features/setup/models/location.dart';
import 'package:gyan_setu_ai/features/setup/models/offline_resource_status.dart';
import 'package:gyan_setu_ai/features/setup/services/offline_resource_manager.dart';
import 'package:gyan_setu_ai/features/setup/services/setup_controller.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';

import 'setup_test_doubles.dart';

void main() {
  late TestRepository repository;
  late TestAudioService audio;
  late StaticConnectivityService connectivity;

  SetupController build({
    OfflineResourceStatus status = kResourcesPending,
    bool throwOnPrepare = false,
  }) {
    return SetupController(
      repository: repository,
      locations: testLocations(),
      resources: StaticOfflineResourceManager(
        status,
        throwOnPrepare: throwOnPrepare,
      ),
      audio: audio,
      connectivity: connectivity,
      teacherId: kTestTeacherId,
    );
  }

  /// The controller loads districts and any saved setup asynchronously.
  Future<SetupController> ready(SetupController c) async {
    while (c.loading) {
      await Future<void>.delayed(Duration.zero);
    }
    return c;
  }

  setUp(() {
    repository = TestRepository();
    audio = TestAudioService();
    connectivity = StaticConnectivityService(ConnectionStatus.online);
  });

  group('defaults', () {
    test('starts with Santali, Hindi, Class 1 and both subjects', () async {
      final SetupController c = await ready(build());

      expect(c.targetLanguage, TargetLanguage.santali);
      expect(c.teachingMedium, TeachingMedium.hindi);
      expect(c.classLevel, 1);
      expect(c.subjects, ClassroomSubject.values.toSet());
      expect(c.hasUnsavedChanges, isFalse);
      expect(c.isEditing, isFalse);
    });

    test('loads districts from the data source', () async {
      final SetupController c = await ready(build());
      expect(
        c.districts.map((District d) => d.name),
        <String>['Dumka', 'Ranchi'],
      );
    });
  });

  group('validation', () {
    test('requires school name, district and block', () async {
      final SetupController c = await ready(build());

      expect(c.validate(), isFalse);
      expect(c.errorFor(SetupField.schoolName), 'School name is required.');
      expect(c.errorFor(SetupField.district), 'Select a district.');
      expect(c.errorFor(SetupField.block), 'Select a block.');
      expect(c.firstInvalidField, SetupField.schoolName);
    });

    test('rejects a whitespace-only school name', () async {
      final SetupController c = await ready(build());
      c.setSchoolName('    ');
      c.validate();
      expect(c.errorFor(SetupField.schoolName), 'School name is required.');
    });

    test('rejects a school name that is too short', () async {
      final SetupController c = await ready(build());
      c.setSchoolName('AB');
      c.validate();
      expect(c.errorFor(SetupField.schoolName), 'School name looks too short.');
    });

    test('requires at least one subject', () async {
      final SetupController c = await ready(build());
      c.setSchoolName('Govt. Primary School');
      c.selectDistrict(kDumka);
      c.selectBlock(kDumka.blocks.first);
      for (final ClassroomSubject s in ClassroomSubject.values) {
        c.toggleSubject(s);
      }

      expect(c.subjects, isEmpty);
      expect(c.isComplete, isFalse);
      expect(c.validate(), isFalse);
      expect(c.errorFor(SetupField.subjects), 'Select at least one subject.');
    });

    test('isComplete only once every required part is present', () async {
      final SetupController c = await ready(build());
      expect(c.isComplete, isFalse);

      c.setSchoolName('Govt. Primary School');
      expect(c.isComplete, isFalse);

      c.selectDistrict(kDumka);
      expect(c.isComplete, isFalse, reason: 'block still missing');

      c.selectBlock(kDumka.blocks.first);
      expect(c.isComplete, isTrue);
    });
  });

  group('district and block', () {
    test('blocks are empty until a district is chosen', () async {
      final SetupController c = await ready(build());
      expect(c.availableBlocks, isEmpty);
    });

    test('blocks come from the chosen district only', () async {
      final SetupController c = await ready(build());

      c.selectDistrict(kRanchi);
      expect(
        c.availableBlocks.map((Block b) => b.name),
        <String>['Kanke', 'Namkum', 'Ratu'],
      );

      c.selectDistrict(kDumka);
      expect(
        c.availableBlocks.map((Block b) => b.name),
        <String>['Jama', 'Masalia'],
      );
    });

    test('changing district clears the chosen block', () async {
      final SetupController c = await ready(build());

      c.selectDistrict(kRanchi);
      c.selectBlock(kRanchi.blocks.first);
      expect(c.block, isNotNull);

      c.selectDistrict(kDumka);
      expect(c.block, isNull);
    });

    test('a block from another district is refused', () async {
      final SetupController c = await ready(build());

      c.selectDistrict(kDumka);
      c.selectBlock(kRanchi.blocks.first);

      expect(c.block, isNull, reason: 'mismatched block must not be accepted');
    });
  });

  group('selections', () {
    test('target language is single-select', () async {
      final SetupController c = await ready(build());

      c.selectTargetLanguage(TargetLanguage.mundari);
      expect(c.targetLanguage, TargetLanguage.mundari);

      c.selectTargetLanguage(TargetLanguage.ho);
      expect(c.targetLanguage, TargetLanguage.ho);
    });

    test('class is single-select', () async {
      final SetupController c = await ready(build());
      c.selectClass(3);
      expect(c.classLevel, 3);
      c.selectClass(5);
      expect(c.classLevel, 5);
    });

    test('subjects are multi-select and toggle independently', () async {
      final SetupController c = await ready(build());

      c.toggleSubject(ClassroomSubject.numeracy);
      expect(c.subjects, <ClassroomSubject>{
        ClassroomSubject.foundationalLiteracy,
      });

      c.toggleSubject(ClassroomSubject.numeracy);
      expect(c.subjects, ClassroomSubject.values.toSet());
    });

    test('teaching medium and target language are independent', () async {
      final SetupController c = await ready(build());

      c.selectTeachingMedium(TeachingMedium.english);
      c.selectTargetLanguage(TargetLanguage.mundari);

      expect(c.teachingMedium, TeachingMedium.english);
      expect(c.targetLanguage, TargetLanguage.mundari);
      expect(c.summaryLine, contains('English → Mundari'));
    });
  });

  group('summary', () {
    test('tracks every selection', () async {
      final SetupController c = await ready(build());

      expect(
        c.summaryLine,
        'Class 1  •  Hindi → Santali  •  FLN + Numeracy',
      );

      c.selectClass(3);
      c.selectTargetLanguage(TargetLanguage.ho);
      c.toggleSubject(ClassroomSubject.numeracy);

      expect(c.summaryLine, 'Class 3  •  Hindi → Ho  •  FLN');
    });

    test('detail line reports what is still missing, then the location',
        () async {
      final SetupController c = await ready(build());
      expect(c.summaryDetail, 'Add school, district and block to finish');

      c.setSchoolName('Govt. Primary School');
      c.selectDistrict(kDumka);
      c.selectBlock(kDumka.blocks.first);

      expect(c.summaryDetail, 'Govt. Primary School, Dumka • Jama');
    });
  });

  group('finish setup', () {
    Future<SetupController> filled({
      OfflineResourceStatus status = kResourcesPending,
      bool throwOnPrepare = false,
    }) async {
      final SetupController c = await ready(
        build(status: status, throwOnPrepare: throwOnPrepare),
      );
      c.setSchoolName('  Govt. Primary School, Jama  ');
      c.selectDistrict(kDumka);
      c.selectBlock(kDumka.blocks.last);
      return c;
    }

    test('refuses to save an invalid form', () async {
      final SetupController c = await ready(build());
      expect(await c.finishSetup(), SetupSaveOutcome.invalid);
      expect(repository.saveCalls, 0);
    });

    test('saves a trimmed, completed record', () async {
      final SetupController c = await filled();

      expect(await c.finishSetup(), SetupSaveOutcome.savedResourcesPending);

      final ClassroomSetup saved = repository.lastSaved!;
      expect(saved.schoolName, 'Govt. Primary School, Jama');
      expect(saved.districtId, 'dumka');
      expect(saved.blockName, 'Masalia');
      expect(saved.setupCompleted, isTrue);
      expect(saved.setupCompletedAt, isNotNull);
      expect(saved.pendingSync, isTrue, reason: 'nothing has synced yet');
      expect(saved.teacherId, kTestTeacherId);
      expect(c.hasUnsavedChanges, isFalse);
    });

    test('reports ready when every resource is present', () async {
      final SetupController c = await filled(status: kResourcesReady);
      expect(await c.finishSetup(), SetupSaveOutcome.savedAndReady);
    });

    test('keeps the setup when resource preparation throws', () async {
      final SetupController c = await filled(throwOnPrepare: true);

      expect(await c.finishSetup(), SetupSaveOutcome.savedResourcesFailed);
      expect(repository.recordFor(kTestTeacherId), isNotNull);
      expect(c.offlineStatus.readiness, OfflineReadiness.failed);
    });

    test('a failed save keeps the form and reports it', () async {
      repository.failOnSave = true;
      final SetupController c = await filled();

      expect(await c.finishSetup(), SetupSaveOutcome.saveFailed);
      expect(repository.recordFor(kTestTeacherId), isNull);
      expect(
        c.saveError,
        'Your classroom setup could not be saved. Please try again.',
      );
      // The teacher's entries survive so nothing has to be typed again.
      expect(c.schoolName.trim(), 'Govt. Primary School, Jama');
    });

    test('works offline: nothing in the save path needs a connection',
        () async {
      connectivity = StaticConnectivityService(ConnectionStatus.offline);
      final SetupController c = await filled();

      expect(await c.finishSetup(), SetupSaveOutcome.savedResourcesPending);
      expect(repository.recordFor(kTestTeacherId), isNotNull);
    });
  });

  group('editing an existing setup', () {
    test('loads saved values instead of the defaults', () async {
      repository = TestRepository(existing: existingSetup());
      final SetupController c = await ready(build());

      expect(c.isEditing, isTrue);
      expect(c.schoolName, 'Govt. Primary School, Kanke');
      expect(c.district?.id, 'ranchi');
      expect(c.block?.name, 'Namkum');
      expect(c.teachingMedium, TeachingMedium.english);
      expect(c.targetLanguage, TargetLanguage.ho);
      expect(c.classLevel, 4);
      expect(c.subjects, <ClassroomSubject>{ClassroomSubject.numeracy});
      expect(
        c.hasUnsavedChanges,
        isFalse,
        reason: 'loading is not a teacher edit',
      );
    });

    test('an edit is saved over the previous record', () async {
      repository = TestRepository(existing: existingSetup());
      final SetupController c = await ready(build());

      c.selectTargetLanguage(TargetLanguage.mundari);
      expect(c.hasUnsavedChanges, isTrue);

      expect(await c.finishSetup(), SetupSaveOutcome.savedResourcesPending);
      expect(
        repository.recordFor(kTestTeacherId)!.targetLanguage,
        TargetLanguage.mundari,
      );
    });
  });

  group('audio preview', () {
    test('reports unavailable when no voice exists, and says why', () async {
      final SetupController c = await ready(build());

      await c.previewTargetLanguage();

      expect(c.targetPreview, PreviewState.unavailable);
      expect(c.previewMessage, contains('not on this device'));
      expect(audio.playCalls, 1);
    });

    test('plays and then stops when a voice exists', () async {
      audio.available = true;
      final SetupController c = await ready(build());

      await c.previewTargetLanguage();
      expect(c.targetPreview, PreviewState.playing);

      await c.previewTargetLanguage();
      expect(c.targetPreview, PreviewState.idle);
      expect(audio.stopCalls, greaterThanOrEqualTo(1));
    });

    test('the two preview buttons hold separate state', () async {
      audio.available = true;
      final SetupController c = await ready(build());

      await c.previewTeachingMedium();
      expect(c.mediumPreview, PreviewState.playing);
      expect(c.targetPreview, PreviewState.idle);
    });
  });

  group('offline resources', () {
    test('status follows the current selections', () async {
      final SetupController c = await ready(build(status: kResourcesPending));
      await c.refreshOfflineStatus();
      expect(c.offlineStatus.readiness, OfflineReadiness.needsSync);
    });

    test('the bundled manager reports missing rather than pretending',
        () async {
      const BundledOfflineResourceManager manager =
          BundledOfflineResourceManager();
      final ClassroomSetup setup = existingSetup();

      final OfflineResourceStatus status =
          await manager.check(setup.resourceProfile);

      expect(status.readiness, OfflineReadiness.needsSync);
      expect(status.missing, isNotEmpty);
      expect(status.isReady, isFalse);
      expect(status.message, contains('after synchronisation'));
    });

    test('required resources depend on the chosen subjects', () async {
      const BundledOfflineResourceManager manager =
          BundledOfflineResourceManager();

      final ClassroomSetup literacyOnly = ClassroomSetup(
        teacherId: kTestTeacherId,
        schoolName: 'S',
        districtId: 'dumka',
        districtName: 'Dumka',
        blockId: 'dumka.jama',
        blockName: 'Jama',
        teachingMedium: TeachingMedium.hindi,
        targetLanguage: TargetLanguage.santali,
        classLevel: 1,
        subjects: const <ClassroomSubject>{
          ClassroomSubject.foundationalLiteracy,
        },
        setupCompleted: false,
      );

      expect(
        manager.requiredFor(literacyOnly.resourceProfile),
        contains(OfflineResourceKind.flashcards),
      );
    });
  });

  group('connectivity', () {
    test('tracks transitions without needing a rebuild of the form', () async {
      final SetupController c = await ready(build());
      expect(c.connectionStatus, ConnectionStatus.online);

      connectivity.set(ConnectionStatus.offline);
      await Future<void>.delayed(Duration.zero);

      expect(c.connectionStatus, ConnectionStatus.offline);
    });
  });
}
