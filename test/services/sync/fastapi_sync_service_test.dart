import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/core/errors/app_exception.dart';
import 'package:gyan_setu_ai/core/utils/result.dart';
import 'package:gyan_setu_ai/features/assessment/services/quiz_repository.dart';
import 'package:gyan_setu_ai/features/auth/services/auth_session_store.dart';
import 'package:gyan_setu_ai/features/classroom/models/classroom_session.dart';
import 'package:gyan_setu_ai/features/classroom/services/classroom_session_repository.dart';
import 'package:gyan_setu_ai/features/profile/models/support_report.dart';
import 'package:gyan_setu_ai/features/profile/services/support_report_store.dart';
import 'package:gyan_setu_ai/features/progress/services/learning_progress_repository.dart';
import 'package:gyan_setu_ai/features/setup/data/classroom_setup_storage.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/features/setup/services/classroom_setup_repository.dart';
import 'package:gyan_setu_ai/features/worksheet/services/worksheet_repository.dart';
import 'package:gyan_setu_ai/models/assessment_answer.dart';
import 'package:gyan_setu_ai/models/assessment_result.dart';
import 'package:gyan_setu_ai/models/lesson.dart';
import 'package:gyan_setu_ai/models/progress_event.dart';
import 'package:gyan_setu_ai/models/question.dart';
import 'package:gyan_setu_ai/models/worksheet.dart';
import 'package:gyan_setu_ai/services/api/api_endpoints.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';
import 'package:gyan_setu_ai/services/sync/fastapi_sync_service.dart';
import 'package:gyan_setu_ai/services/sync/sync_ack_store.dart';
import 'package:gyan_setu_ai/services/sync/sync_metadata_store.dart';
import 'package:gyan_setu_ai/services/sync/sync_status.dart';
import 'package:gyan_setu_ai/services/sync/synced_catalog_store.dart';

import '../../api/api_test_doubles.dart';
import '../../auth/auth_test_doubles.dart';

/// A support-report store in memory, mirroring the other in-memory fakes.
class InMemorySupportReportStore implements SupportReportStore {
  InMemorySupportReportStore([List<SupportReport>? seed])
      : _reports = <SupportReport>[...?seed];

  final List<SupportReport> _reports;

  @override
  Future<List<SupportReport>> reports() async =>
      List<SupportReport>.unmodifiable(_reports);

  @override
  Future<bool> add(SupportReport report) async {
    _reports.add(report);
    return true;
  }
}

final DateTime now = DateTime.now().toUtc();
const String serverNow = '2026-08-30T09:00:00.000Z';

ClassroomSetup testSetup() => ClassroomSetup(
      teacherId: kTestTeacher.id,
      schoolName: 'GPS Dumka',
      districtId: 'd1',
      districtName: 'Dumka',
      blockId: 'b1',
      blockName: 'Kathikund',
      teachingMedium: TeachingMedium.hindi,
      targetLanguage: TargetLanguage.santali,
      classLevel: 1,
      subjects: <ClassroomSubject>{ClassroomSubject.numeracy},
      setupCompleted: true,
      pendingSync: true,
    );

ClassroomSession testClassroomSession() => ClassroomSession(
      sessionId: 'CLS-240827-1000',
      lessonId: 'lesson-1',
      classNumber: 1,
      teachingLanguage: 'hi-IN',
      targetLanguage: 'sat',
      startedAt: now.subtract(const Duration(hours: 2)),
      syncStatus: SessionSyncStatus.localOnly,
    );

Worksheet testWorksheet() => Worksheet(
      id: 'w1',
      lessonId: 'lesson-1',
      title: 'Counting to 5',
      learningOutcome: 'Count objects to 5',
      classNumber: 1,
      subject: ClassroomSubject.numeracy,
      teachingLanguage: TeachingMedium.hindi,
      targetLanguage: TargetLanguage.santali,
      difficulty: WorksheetDifficulty.easy,
      questions: const <WorksheetQuestion>[],
      generatedAt: now.subtract(const Duration(hours: 1)),
      generationSource: GenerationSource.localOffline,
    );

QuizResult testQuizResult() => QuizResult(
      lessonId: 'lesson-1',
      score: 3,
      total: 4,
      concepts: const <ConceptPerformance>[],
      startedAt: now.subtract(const Duration(hours: 1)),
      finishedAt: now.subtract(const Duration(minutes: 20)),
      answers: const <String, QuizAnswer>{},
    );

ProgressEvent testProgressEvent() => ProgressEvent.of(
      type: ProgressEventType.lessonCompleted,
      occurredAt: now.subtract(const Duration(minutes: 10)),
      lessonId: 'lesson-1',
    );

SupportReport testSupportReport() => SupportReport(
      id: 'rep-1',
      message: 'Sunday word did not translate',
      createdAt: now.subtract(const Duration(minutes: 5)),
    );

void main() {
  late InMemorySecureStorageService storage;
  late AuthSessionStore session;
  late ScriptedApiClient api;
  late MemoryClassroomSetupStorage setupStorage;
  late InMemoryClassroomSessionRepository sessions;
  late InMemoryWorksheetRepository worksheets;
  late InMemoryQuizRepository assessments;
  late InMemoryLearningProgressRepository progress;
  late InMemorySupportReportStore reports;
  late FastApiSyncService service;

  setUp(() {
    storage = InMemorySecureStorageService();
    session = AuthSessionStore(storage);
    api = ScriptedApiClient();
    setupStorage = MemoryClassroomSetupStorage();
    sessions = InMemoryClassroomSessionRepository();
    worksheets = InMemoryWorksheetRepository();
    assessments = InMemoryQuizRepository();
    progress = InMemoryLearningProgressRepository();
    reports = InMemorySupportReportStore();
    service = FastApiSyncService(
      api: api,
      session: session,
      metadata: LocalSyncMetadataStore(storage),
      connectivity: StaticConnectivityService(ConnectionStatus.online),
      storage: storage,
      classroomSetup: LocalClassroomSetupRepository(setupStorage),
      sessions: sessions,
      worksheets: worksheets,
      assessments: assessments,
      progress: progress,
      supportReports: reports,
    );
  });

  Future<void> seedSession({bool token = true}) async {
    await storage.write('auth.account', kTestTeacher.encode());
    await storage.write('auth.device_id', 'device-1');
    if (token) await storage.write('auth.access_token', 'token-abc');
  }

  Future<void> seedPendingRecords() async {
    await setupStorage.save(testSetup());
    await sessions.save(testClassroomSession());
    await worksheets.save(testWorksheet());
    await assessments.saveResult(testQuizResult());
    await progress.record(testProgressEvent());
    await reports.add(testSupportReport());
  }

  List<Object?> defaultPushAcks() => <Object?>[
        <String, Object?>{'type': 'classroomSetup', 'id': kTestTeacher.id},
        <String, Object?>{'type': 'classroomSession', 'id': 'CLS-240827-1000'},
        <String, Object?>{'type': 'worksheet', 'id': 'w1'},
        <String, Object?>{'type': 'assessmentResult', 'id': 'assessment-lesson-1'},
        <String, Object?>{'type': 'progressEvent', 'id': testProgressEvent().id},
        <String, Object?>{'type': 'supportReport', 'id': 'rep-1'},
      ];

  group('FastApiSyncService', () {
    test('without an access token the run fails without contacting the server',
        () async {
      await seedSession(token: false);
      await seedPendingRecords();

      final Result<SyncStatus> output = await service.syncNow();

      expect(output, isA<Err<SyncStatus>>());
      expect(service.status.state, SyncState.failed);
      expect(service.status.message, contains('Sign in again'));
      expect(api.getPaths, isEmpty);
      expect(api.postPaths, isEmpty);
    });

    test('offline with queued changes ends pending, never a completed claim',
        () async {
      await seedSession();
      await seedPendingRecords();
      service = FastApiSyncService(
        api: api,
        session: session,
        metadata: LocalSyncMetadataStore(storage),
        connectivity: StaticConnectivityService(ConnectionStatus.offline),
        storage: storage,
        classroomSetup: LocalClassroomSetupRepository(setupStorage),
        sessions: sessions,
        worksheets: worksheets,
        assessments: assessments,
        progress: progress,
        supportReports: reports,
      );

      final Result<SyncStatus> output = await service.syncNow();

      expect(output, isA<Ok<SyncStatus>>());
      expect(service.status.state, SyncState.pending);
      expect(service.status.pendingChanges, 6);
      expect(service.status.message, 'Changes waiting to sync');
      expect(api.getPaths, isEmpty, reason: 'offline runs touch no server');
    });

    test('happy path pushes pending records, applies the pull and completes',
        () async {
      await seedSession();
      await seedPendingRecords();

      api.onGet = () => Ok<Map<String, dynamic>>(<String, dynamic>{});
      api.onPost = () {
        final String path = api.postPaths.last;
        if (path == ApiEndpoints.syncPush) {
          return Ok<Map<String, dynamic>>(<String, dynamic>{
            'acknowledged': defaultPushAcks(),
            'conflicts': <Object?>[],
            'errors': <Object?>[],
            'serverNow': serverNow,
          });
        }
        final Worksheet pulled = Worksheet(
          id: 'w2',
          lessonId: 'lesson-1',
          title: 'Counting to 5 (b)',
          learningOutcome: 'Count objects to 5',
          classNumber: 1,
          subject: ClassroomSubject.numeracy,
          teachingLanguage: TeachingMedium.hindi,
          targetLanguage: TargetLanguage.santali,
          difficulty: WorksheetDifficulty.medium,
          questions: const <WorksheetQuestion>[],
          generatedAt: now.subtract(const Duration(hours: 1)),
          generationSource: GenerationSource.remoteAi,
        );
        final ProgressEvent pulledEvent = ProgressEvent(
          id: 'evt-pulled',
          type: ProgressEventType.worksheetCompleted,
          occurredAt: now.subtract(const Duration(hours: 1)),
          lessonId: 'lesson-2',
        );
        final SupportReport pulledReport = SupportReport(
          id: 'rep-pulled',
          message: 'From another device',
          createdAt: now.subtract(const Duration(minutes: 1)),
        );
        return Ok<Map<String, dynamic>>(<String, dynamic>{
          'since': serverNow,
          'serverNow': serverNow,
          'documents': <Object?>[
            <String, Object?>{
              'type': 'worksheet',
              'id': 'w2',
              'updatedAt': serverNow,
              'data': pulled.toJson(),
            },
            <String, Object?>{
              'type': 'progressEvent',
              'id': 'evt-pulled',
              'updatedAt': serverNow,
              'data': pulledEvent.toJson(),
            },
            <String, Object?>{
              'type': 'supportReport',
              'id': 'rep-pulled',
              'updatedAt': serverNow,
              'data': pulledReport.toJson(),
            },
          ],
          'catalog': <Object?>[
            <String, Object?>{
              'type': 'lesson',
              'data': Lesson(
                id: 'lesson-1',
                title: 'Counting to 5',
                description: 'Numbers 1-5 with objects',
                subject: ClassroomSubject.numeracy,
                classNumber: 1,
                learningOutcome: 'Count objects to 5',
                durationMinutes: 20,
                lessonOrder: 1,
                createdAt: now.subtract(const Duration(days: 30)),
                updatedAt: now.subtract(const Duration(days: 1)),
              ).toJson(),
            },
          ],
        });
      };

      final List<SyncState> seen = <SyncState>[];
      final StreamSubscription<SyncStatus> sub = service.onStatusChanged.listen(
        (SyncStatus s) => seen.add(s.state),
      );

      final Result<SyncStatus> output = await service.syncNow();
      await pumpEventQueue();

      expect(output, isA<Ok<SyncStatus>>());
      final SyncStatus done = service.status;
      expect(done.state, SyncState.completed);
      expect(done.pendingChanges, 0);
      expect(done.message, 'All content is up to date');
      expect(
        done.lastSyncedAt,
        DateTime.parse(serverNow),
      );
      expect(seen, containsAll(<SyncState>[
        SyncState.checking,
        SyncState.uploading,
        SyncState.downloading,
        SyncState.completed,
      ]));

      // Acks were applied to the local stores.
      expect(
        (await sessions.byId('CLS-240827-1000'))!.syncStatus,
        SessionSyncStatus.synced,
      );
      expect((await setupStorage.load(kTestTeacher.id))!.pendingSync, isFalse);
      final SyncAckStore acks = SyncAckStore(storage);
      expect(await acks.has(SyncAckStore.worksheets, 'w1'), isTrue);
      expect(
        await acks.has(SyncAckStore.assessments, 'assessment-lesson-1'),
        isTrue,
      );
      expect(await acks.has(SyncAckStore.progressEvents, testProgressEvent().id), isTrue);
      expect(await acks.has(SyncAckStore.supportReports, 'rep-1'), isTrue);

      // Pulled documents landed.
      expect(await worksheets.byId('w2'), isNotNull);
      expect(
        (await progress.all()).any((ProgressEvent e) => e.id == 'evt-pulled'),
        isTrue,
      );
      expect(
        (await reports.reports()).any((SupportReport r) => r.id == 'rep-pulled'),
        isTrue,
      );

      // The server lesson catalogue was cached.
      final List<Lesson> catalog = await SyncedCatalogStore(storage).lessons();
      expect(catalog.map((Lesson l) => l.id), contains('lesson-1'));

      // Metadata records the successful run's server time.
      expect(
        await LocalSyncMetadataStore(storage).lastSyncedAt(),
        DateTime.parse(serverNow),
      );

      // The push carried exactly the pending set, nothing extra.
      final Map<String, dynamic> pushBody =
          api.postCallsFor(ApiEndpoints.syncPush).first['body']
              as Map<String, dynamic>;
      final List<dynamic> documents = pushBody['documents'] as List<dynamic>;
      expect(documents.length, 6);
      expect(
        documents.map((dynamic d) => (d as Map<String, dynamic>)['type']),
        containsAll(<String>[
          'classroomSetup',
          'classroomSession',
          'worksheet',
          'assessmentResult',
          'progressEvent',
          'supportReport',
        ]),
      );

      // A second run has nothing left to push.
      await service.syncNow();
      final Map<String, dynamic> secondPush =
          api.postCallsFor(ApiEndpoints.syncPush).first['body']
              as Map<String, dynamic>;
      expect((secondPush['documents'] as List<dynamic>), isEmpty);

      await sub.cancel();
    });

    test('an unacknowledged push ends the run failed with the count', () async {
      await seedSession();
      await seedPendingRecords();

      api.onGet = () => Ok<Map<String, dynamic>>(<String, dynamic>{});
      api.onPost = () {
        final String path = api.postPaths.last;
        if (path == ApiEndpoints.syncPush) {
          return Ok<Map<String, dynamic>>(<String, dynamic>{
            'acknowledged': <Object?>[
              <String, Object?>{'type': 'classroomSetup', 'id': kTestTeacher.id},
              <String, Object?>{'type': 'classroomSession', 'id': 'CLS-240827-1000'},
            ],
            'conflicts': <Object?>[],
            'errors': <Object?>[
              <String, Object?>{
                'type': 'worksheet',
                'id': 'w1',
                'error': 'rejected',
              },
            ],
            'serverNow': serverNow,
          });
        }
        return Ok<Map<String, dynamic>>(
          <String, dynamic>{'documents': <Object?>[], 'catalog': <Object?>[]},
        );
      };

      final Result<SyncStatus> output = await service.syncNow();

      expect(output, isA<Err<SyncStatus>>());
      expect(service.status.state, SyncState.failed);
      expect(service.status.pendingChanges, 1);
      expect(service.status.message, '1 item could not be synced.');
      expect(
        api.postPaths,
        isNot(contains(ApiEndpoints.syncPull)),
        reason: 'a failed push must not proceed to a pull',
      );
    });

    test('a server failure on the status check ends the run failed', () async {
      await seedSession();
      await seedPendingRecords();

      api.onGet = () =>
          Err<Map<String, dynamic>>(const ServerException('boom', statusCode: 500));
      api.onPost = () =>
          Err<Map<String, dynamic>>(const ServerException('boom', statusCode: 500));

      final Result<SyncStatus> output = await service.syncNow();

      expect(output, isA<Err<SyncStatus>>());
      expect(service.status.state, SyncState.failed);
      expect(api.getPaths, contains(ApiEndpoints.syncStatus));
      expect(api.postPaths, isEmpty);
    });

    test('content packs are not claimed to exist', () async {
      final Result<void> pack = await service.downloadPack('any-pack');
      expect(pack, isA<Err<void>>());
    });
  });
}