import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:gyan_setu_ai/core/config/api_config.dart';
import 'package:gyan_setu_ai/core/errors/app_exception.dart';
import 'package:gyan_setu_ai/core/utils/result.dart';
import 'package:gyan_setu_ai/features/assessment/services/quiz_repository.dart';
import 'package:gyan_setu_ai/features/auth/models/auth_result.dart';
import 'package:gyan_setu_ai/features/auth/models/teacher_account.dart';
import 'package:gyan_setu_ai/features/auth/services/auth_session_store.dart';
import 'package:gyan_setu_ai/features/auth/services/authentication_service.dart';
import 'package:gyan_setu_ai/features/auth/services/fastapi_authentication_service.dart';
import 'package:gyan_setu_ai/features/auth/services/offline_authentication_service.dart';
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
import 'package:gyan_setu_ai/services/api/http_api_client.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';
import 'package:gyan_setu_ai/services/sync/fastapi_sync_service.dart';
import 'package:gyan_setu_ai/services/sync/sync_metadata_store.dart';
import 'package:gyan_setu_ai/services/sync/sync_status.dart';
import 'package:gyan_setu_ai/services/sync/synced_catalog_store.dart';

/// End-to-end verification against the real FastAPI backend, driving the *same
/// services the app buttons reach* (FastApiAuthenticationService and
/// FastApiSyncService over HttpApiClient), through an in-memory device.
///
/// Run it with uvicorn up on the base URL in [ApiConfig]:
///
///     flutter test --dart-define=LIVE_BACKEND=true test/live_e2e_test.dart
///
/// Every account is generated per run and nothing secret is hard-coded.
const bool live = bool.fromEnvironment('LIVE_BACKEND');

int _accountSeq = 0;

/// A fresh 10-digit mobile per call, so repeated live runs never collide.
String _uniqueMobile(String tag) {
  final String micro = (DateTime.now().microsecondsSinceEpoch % 1000000)
      .toString()
      .padLeft(6, '0');
  final String count = ((_accountSeq++) % 100).toString().padLeft(2, '0');
  return '7$tag$micro$count';
}

/// Records request bodies so a test can prove what was (and was not) pushed.
class _RecordingHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final List<(String, String)> posts = <(String, String)>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.method == 'POST') {
      String? body;
      if (request is http.Request) body = request.body;
      posts.add((request.url.path, body ?? ''));
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

class InMemorySupportReportStore implements SupportReportStore {
  final List<SupportReport> _reports = <SupportReport>[];

  @override
  Future<List<SupportReport>> reports() async =>
      List<SupportReport>.unmodifiable(_reports);

  @override
  Future<bool> add(SupportReport report) async {
    _reports.add(report);
    return true;
  }
}

void main() {
  if (!live) {
    test(
      'live E2E is skipped unless LIVE_BACKEND is set',
      () {},
      skip: 'not a live run',
    );
    return;
  }

  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

  final DateTime now = DateTime.now().toUtc();

  test('auth: register, duplicate, login, me, logout, invalid token', () async {
    final InMemorySecureStorageService storage =
        InMemorySecureStorageService();
    final AuthSessionStore session = AuthSessionStore(storage);
    final HttpApiClient api = HttpApiClient(baseUrl: ApiConfig.baseUrl);
    final FastApiAuthenticationService auth = FastApiAuthenticationService(
      api: api,
      offline: OfflineAuthenticationService(store: session),
      session: session,
    );

    final String mobile = _uniqueMobile('0');
    const String pin = '1234';

    // Valid registration through the documented endpoint.
    final Result<Map<String, dynamic>> register = await api.post(
      ApiEndpoints.register,
      body: <String, dynamic>{
        'displayName': 'E2E Teacher',
        'mobile': mobile,
        'password': pin,
      },
    );
    expect(register, isA<Ok<Map<String, dynamic>>>(), reason: 'register');
    final String teacherId =
        (register as Ok<Map<String, dynamic>>).value['account']['id'] as String;
    expect(teacherId, isNotEmpty);
    expect(
      (register.value['accessToken'] as String),
      isNotEmpty,
    );

    // Duplicate registration is rejected by the server, not faked around.
    final Result<Map<String, dynamic>> duplicate = await api.post(
      ApiEndpoints.register,
      body: <String, dynamic>{
        'displayName': 'E2E Teacher',
        'mobile': mobile,
        'password': pin,
      },
    );
    expect(
      duplicate,
      isA<Err<Map<String, dynamic>>>().having(
        (Err<Map<String, dynamic>> e) => e.error,
        'error',
        isA<ServerException>().having(
          (ServerException e) => e.statusCode,
          'statusCode',
          409,
        ),
      ),
    );

    // PIN recovery is acknowledged, but no fake delivery is claimed by the app.
    expect(await auth.requestPinRecovery(mobile), isTrue);

    // Wrong PIN through the app's service: honest invalid-credentials failure.
    final AuthResult badPin = await auth.signIn(
      AuthCredentials.mobile(mobile: mobile, pin: '0000'),
    );
    expect(badPin, isA<AuthFailure>());
    expect((badPin as AuthFailure).reason, AuthFailureReason.invalidCredentials);

    // Valid login through the app's service provisions the device + token.
    final AuthResult login = await auth.signIn(
      AuthCredentials.mobile(mobile: mobile, pin: pin),
    );
    expect(login, isA<AuthSuccess>());
    expect((login as AuthSuccess).account.id, teacherId);
    expect(await session.accessToken(), isNotEmpty);
    expect(await session.pinVerifier(), isNotNull);

    // The stored JWT is accepted by the documented /auth/me endpoint.
    final HttpApiClient authed = HttpApiClient(
      baseUrl: ApiConfig.baseUrl,
      accessTokenProvider: session.accessToken,
    );
    final Result<Map<String, dynamic>> me = await authed.get(ApiEndpoints.me);
    expect(me, isA<Ok<Map<String, dynamic>>>());
    expect((me as Ok<Map<String, dynamic>>).value['id'], teacherId);

    // Logout clears the device token; the server then rejects the bearer.
    await auth.signOut();
    expect(await session.accessToken(), isNull);
    final Result<Map<String, dynamic>> afterLogout =
        await authed.get(ApiEndpoints.me);
    expect(
      afterLogout,
      isA<Err<Map<String, dynamic>>>().having(
        (Err<Map<String, dynamic>> e) => e.error,
        'error',
        isA<UnauthorizedException>(),
      ),
      reason: 'a signed-out device has no credential to offer',
    );

    // An invalid/expired-looking token hits the same 401 path, visibly.
    await session.saveAccessToken('definitely.not.a.real.jwt');
    final Result<Map<String, dynamic>> bad = await authed.get(
      ApiEndpoints.me,
    );
    expect(
      bad,
      isA<Err<Map<String, dynamic>>>().having(
        (Err<Map<String, dynamic>> e) => e.error,
        'error',
        isA<UnauthorizedException>(),
      ),
    );
  });

  test('profile: /auth/me carries classroom identity after setup', () async {
    final InMemorySecureStorageService storage =
        InMemorySecureStorageService();
    final AuthSessionStore session = AuthSessionStore(storage);
    final HttpApiClient api = HttpApiClient(
      baseUrl: ApiConfig.baseUrl,
      accessTokenProvider: session.accessToken,
    );

    final String mobile = _uniqueMobile('2');
    const String pin = '1234';
    final Result<Map<String, dynamic>> register = await api.post(
      ApiEndpoints.register,
      body: <String, dynamic>{
        'displayName': 'Identity E2E',
        'mobile': mobile,
        'password': pin,
      },
    );
    expect(
      register,
      isA<Ok<Map<String, dynamic>>>(),
      reason: 'register: ${_describe(register)}',
    );
    final Map<String, dynamic> accountJson =
        (register as Ok<Map<String, dynamic>>).value['account']
            as Map<String, dynamic>;
    final String teacherId = accountJson['id'] as String;
    final TeacherAccount account = TeacherAccount.fromJson(accountJson);

    await storage.write('auth.account', account.encode());
    await storage.write('auth.device_id', 'identity-e2e-device');
    await storage.write(
      'auth.access_token',
      register.value['accessToken'] as String,
    );

    // Before any setup there is no classroom identity served by /auth/me.
    final Result<Map<String, dynamic>> pre = await api.get(ApiEndpoints.me);
    expect(pre, isA<Ok<Map<String, dynamic>>>(), reason: 'me before setup');
    expect((pre as Ok<Map<String, dynamic>>).value['id'], teacherId);
    expect((pre).value['setupCompleted'], isFalse);
    expect((pre).value['classLevel'], isNull);

    // Push a completed classroom setup through the sync service.
    final MemoryClassroomSetupStorage setupStorage =
        MemoryClassroomSetupStorage();
    final ClassroomSetup setup = ClassroomSetup(
      teacherId: teacherId,
      schoolName: 'GPS Identity Test',
      districtId: 'd1',
      districtName: 'Dumka',
      blockId: 'b1',
      blockName: 'Jama',
      teachingMedium: TeachingMedium.hindi,
      targetLanguage: TargetLanguage.santali,
      classLevel: 1,
      subjects: <ClassroomSubject>{ClassroomSubject.numeracy},
      setupCompleted: true,
      pendingSync: true,
    );
    await setupStorage.save(setup);
    final FastApiSyncService push = FastApiSyncService(
      api: api,
      session: session,
      metadata: LocalSyncMetadataStore(storage),
      connectivity: StaticConnectivityService(ConnectionStatus.online),
      storage: storage,
      classroomSetup: LocalClassroomSetupRepository(setupStorage),
      sessions: InMemoryClassroomSessionRepository(),
      worksheets: InMemoryWorksheetRepository(),
      assessments: InMemoryQuizRepository(),
      progress: InMemoryLearningProgressRepository(),
      supportReports: InMemorySupportReportStore(),
    );
    final Result<SyncStatus> synced = await push.syncNow();
    expect(synced, isA<Ok<SyncStatus>>(),
        reason: 'push: ${push.status.message}');
    expect(push.status.state, SyncState.completed);

    // After setup the same endpoint serves the classroom identity.
    final Result<Map<String, dynamic>> after = await api.get(ApiEndpoints.me);
    expect(after, isA<Ok<Map<String, dynamic>>>(), reason: 'me after setup');
    final Map<String, dynamic> me = (after as Ok<Map<String, dynamic>>).value;
    expect(me['id'], teacherId);
    expect(me['setupCompleted'], isTrue);
    expect(me['classLevel'], 1);
    expect(me['teachingMedium'], 'hindi');
    expect(me['targetLanguage'], 'santali');
    expect(me['schoolName'], 'GPS Identity Test');
    expect(me['subjects'], contains('numeracy'));

    // The teachers-scoped surface agrees: /teachers/me is the same teacher.
    final Result<Map<String, dynamic>> teachersMe = await api.get(
      ApiEndpoints.teachersMe,
    );
    expect(
      teachersMe,
      isA<Ok<Map<String, dynamic>>>(),
      reason: 'teachers/me',
    );
    expect(
      (teachersMe as Ok<Map<String, dynamic>>).value['id'],
      teacherId,
    );
  });

  test('sync: push, pull, ack, duplicate prevention, persistence, honesty',
      () async {
    final InMemorySecureStorageService storage =
        InMemorySecureStorageService();
    final AuthSessionStore session = AuthSessionStore(storage);
    final _RecordingHttpClient recorder = _RecordingHttpClient();
    final HttpApiClient api = HttpApiClient(
      baseUrl: ApiConfig.baseUrl,
      httpClient: recorder,
      accessTokenProvider: session.accessToken,
    );

    final String run = (DateTime.now().millisecondsSinceEpoch % 1000000000)
        .toString();
    final String mobile = _uniqueMobile('1');

    final Result<Map<String, dynamic>> register = await api.post(
      ApiEndpoints.register,
      body: <String, dynamic>{
        'displayName': 'E2E Sync Teacher',
        'mobile': mobile,
        'password': '1234',
      },
    );
    expect(
      register,
      isA<Ok<Map<String, dynamic>>>(),
      reason: 'register: ${_describe(register)}',
    );
    final Map<String, dynamic> accountJson =
        (register as Ok<Map<String, dynamic>>).value['account']
            as Map<String, dynamic>;
    final String teacherId = accountJson['id'] as String;
    final TeacherAccount account = TeacherAccount.fromJson(accountJson);

    // Provision the device exactly as a real sign-in would.
    await storage.write('auth.account', account.encode());
    await storage.write('auth.device_id', 'live-e2e-device-$run');
    await storage.write(
      'auth.access_token',
      register.value['accessToken'] as String,
    );

    final MemoryClassroomSetupStorage setupStorage =
        MemoryClassroomSetupStorage();
    final InMemoryClassroomSessionRepository sessions =
        InMemoryClassroomSessionRepository();
    final InMemoryWorksheetRepository worksheets = InMemoryWorksheetRepository();
    final InMemoryQuizRepository assessments = InMemoryQuizRepository();
    final InMemoryLearningProgressRepository progress =
        InMemoryLearningProgressRepository();
    final InMemorySupportReportStore reports = InMemorySupportReportStore();
    final LocalSyncMetadataStore metadata = LocalSyncMetadataStore(storage);

    final ClassroomSetup setup = ClassroomSetup(
      teacherId: teacherId,
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
    final ClassroomSession classroomSession = ClassroomSession(
      sessionId: 'LIVE-CLS-$run-1',
      lessonId: 'lesson-1',
      classNumber: 1,
      teachingLanguage: 'hi-IN',
      targetLanguage: 'sat',
      startedAt: now.subtract(const Duration(hours: 1)),
      syncStatus: SessionSyncStatus.localOnly,
    );
    final Worksheet worksheet = Worksheet(
      id: 'LIVE-WS-$run-1',
      lessonId: 'lesson-1',
      title: 'Live E2E Worksheet',
      learningOutcome: 'Count objects to 5',
      classNumber: 1,
      subject: ClassroomSubject.numeracy,
      teachingLanguage: TeachingMedium.hindi,
      targetLanguage: TargetLanguage.santali,
      difficulty: WorksheetDifficulty.easy,
      questions: const <WorksheetQuestion>[],
      generatedAt: now.subtract(const Duration(minutes: 30)),
      generationSource: GenerationSource.localOffline,
    );
    final QuizResult quiz = QuizResult(
      lessonId: 'lesson-1',
      score: 3,
      total: 4,
      concepts: const <ConceptPerformance>[],
      startedAt: now.subtract(const Duration(hours: 1)),
      finishedAt: now.subtract(const Duration(minutes: 20)),
      answers: const <String, QuizAnswer>{},
    );
    final ProgressEvent event = ProgressEvent.of(
      type: ProgressEventType.lessonCompleted,
      occurredAt: now.subtract(const Duration(minutes: 10)),
      lessonId: 'lesson-1',
    );
    final SupportReport report = SupportReport(
      id: 'LIVE-REP-$run-1',
      message: 'Live E2E translation gap',
      createdAt: now.subtract(const Duration(minutes: 5)),
    );

    FastApiSyncService service = FastApiSyncService(
      api: api,
      session: session,
      metadata: metadata,
      connectivity: StaticConnectivityService(ConnectionStatus.offline),
      storage: storage,
      classroomSetup: LocalClassroomSetupRepository(setupStorage),
      sessions: sessions,
      worksheets: worksheets,
      assessments: assessments,
      progress: progress,
      supportReports: reports,
    );
    await setupStorage.save(setup);
    await sessions.save(classroomSession);
    await worksheets.save(worksheet);
    await assessments.saveResult(quiz);
    await progress.record(event);
    await reports.add(report);

    // Offline: queued changes become pending; no server contact, no fake OK.
    final int postsBefore = recorder.posts.length;
    final Result<SyncStatus> offline = await service.syncNow();
    expect(offline, isA<Ok<SyncStatus>>());
    expect(service.status.state, SyncState.pending);
    expect(service.status.pendingChanges, 6, reason: 'all six kinds queued');
    expect(recorder.posts.length, postsBefore,
        reason: 'an offline run must not contact the server');

    // No token: honest failure, still no server contact.
    service = FastApiSyncService(
      api: api,
      session: session,
      metadata: metadata,
      connectivity: StaticConnectivityService(ConnectionStatus.online),
      storage: storage,
      classroomSetup: LocalClassroomSetupRepository(setupStorage),
      sessions: sessions,
      worksheets: worksheets,
      assessments: assessments,
      progress: progress,
      supportReports: reports,
    );
    await storage.write('auth.access_token', '');
    final Result<SyncStatus> noToken = await service.syncNow();
    expect(noToken, isA<Err<SyncStatus>>());
    expect(service.status.message, contains('Sign in again'));

    // A bad token surfaces the server's 401 honestly...
    await session.saveAccessToken('bad.jwt.value');
    final Result<SyncStatus> badToken = await service.syncNow();
    expect(badToken, isA<Err<SyncStatus>>());
    expect(service.status.state, SyncState.failed);

    // ...and a good token retries the same run to completion.
    await storage.write(
      'auth.access_token',
      register.value['accessToken'] as String,
    );
    final Result<SyncStatus> first = await service.syncNow();
    expect(first, isA<Ok<SyncStatus>>(),
        reason: 'first sync succeeds: ${service.status.message}');
    expect(
      service.status,
      isA<SyncStatus>().having((SyncStatus s) => s.state, 'state',
          SyncState.completed),
    );

    final List<(String, String)> pushes = <(String, String)>[
      for (final (String path, String body) in recorder.posts)
        if (path.endsWith('/sync/push')) (path, body),
    ];
    expect(pushes.length, 1, reason: 'exactly one push so far');
    final List<dynamic> pushed = _documentsOf(pushes.first.$2);
    expect(pushed.length, 6);
    expect(
      <String>{
        for (final dynamic d in pushed)
          (d as Map<String, dynamic>)['type'] as String,
      },
      <String>{
        'classroomSetup',
        'classroomSession',
        'worksheet',
        'assessmentResult',
        'progressEvent',
        'supportReport',
      },
    );

    // Pulled content landed: setup cleared, session synced, catalogue cached.
    final ClassroomSetup? storedSetup = await setupStorage.load(teacherId);
    expect(storedSetup?.pendingSync, isFalse);
    expect(
      (await sessions.byId(classroomSession.sessionId))?.syncStatus,
      SessionSyncStatus.synced,
    );
    expect(await SyncedCatalogStore(storage).lessons(), isA<List<Lesson>>());

    // The seeded development backend's catalogue is served by the pull and
    // cached, so a device pointed at it reads the real, authored lessons
    // (not the bundled MockLessons) with no UI change.
    final List<Lesson> catalog = await SyncedCatalogStore(storage).lessons();
    expect(catalog, isNotEmpty, reason: 'pull cached the generated catalogue');
    final Lesson seededLesson = catalog
        .firstWhere((Lesson l) => l.id == 'c1-num-counting-1-10');
    expect(seededLesson.title, 'Counting 1 to 10');
    expect(seededLesson.classNumber, 1);
    expect(seededLesson.worksheetResourceId, 'c1-ws-counting-1-10');
    expect(
      catalog.any((Lesson l) => l.id == 'c1-lit-santali-words'),
      isTrue,
      reason: 'the full seeded catalogue is served, not just one row',
    );

    // Last-synced persisted from the server's own clock.
    final DateTime? lastSynced = await metadata.lastSyncedAt();
    expect(lastSynced, isNotNull);
    expect(
      DateTime.now().toUtc().difference(lastSynced!).inMinutes < 5,
      isTrue,
      reason: 'serverNow is the current time, not a placeholder',
    );

    // Second run pushes nothing new: acks keep the device duplicate-free.
    final Result<SyncStatus> second = await service.syncNow();
    expect(second, isA<Ok<SyncStatus>>());
    expect(service.status.state, SyncState.completed);
    final List<(String, String)> pushes2 = <(String, String)>[
      for (final (String path, String body) in recorder.posts)
        if (path.endsWith('/sync/push')) (path, body),
    ];
    expect(pushes2.length, 2);
    expect(_documentsOf(pushes2.last.$2), isEmpty,
        reason: 'acknowledged records are never resent');

    recorder.close();
  });
}

List<dynamic> _documentsOf(String body) {
  final Map<String, dynamic> decoded =
      jsonDecode(body) as Map<String, dynamic>;
  return decoded['documents'] as List<dynamic>;
}

String _describe(Result<Map<String, dynamic>> result) => switch (result) {
      Ok<Map<String, dynamic>>() => 'unexpected success',
      Err<Map<String, dynamic>>(:final AppException error) => error.toString(),
    };