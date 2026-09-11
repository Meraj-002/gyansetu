// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:async';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/result.dart';
import '../../features/assessment/services/quiz_repository.dart';
import '../../features/classroom/models/classroom_session.dart';
import '../../features/classroom/services/classroom_session_repository.dart';
import '../../features/profile/models/support_report.dart';
import '../../features/progress/services/learning_progress_repository.dart';
import '../../features/profile/services/support_report_store.dart';
import '../../features/setup/models/classroom_setup.dart';
import '../../features/setup/services/classroom_setup_repository.dart';
import '../../features/worksheet/services/worksheet_repository.dart';
import '../../models/assessment_result.dart';
import '../../models/lesson.dart';
import '../../models/progress_event.dart';
import '../../models/worksheet.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../connectivity/connectivity_service.dart';
import '../storage/secure_storage_service.dart';
import '../../features/auth/models/teacher_account.dart';
import '../../features/auth/services/auth_session_store.dart';
import 'sync_ack_store.dart';
import 'sync_metadata_store.dart';
import 'sync_service.dart';
import 'sync_status.dart';
import 'synced_catalog_store.dart';

/// [SyncService] backed by the FastAPI sync bridge.
///
/// Runs the honest state machine (checking → uploading → downloading →
/// completed), never claiming a record left the device unless the server said
/// it accepted it:
///
/// * offline with queued changes ends in [SyncState.pending], not success;
/// * no access token ends in [SyncState.failed] telling the teacher to sign in;
/// * unacknowledged items after a push end in [SyncState.failed].
///
/// On success the local stores are reconciled with what the server accepted:
/// sessions are marked synced, classroom setup stops being pending, and
/// acknowledged worksheets/assessments/progress/support reports are memoised so
/// a later run does not resend them.
class FastApiSyncService implements SyncService {
  FastApiSyncService({
    required ApiClient api,
    required AuthSessionStore session,
    required SyncMetadataStore metadata,
    required ConnectivityService connectivity,
    required SecureStorageService storage,
    required ClassroomSetupRepository classroomSetup,
    required ClassroomSessionRepository sessions,
    required WorksheetRepository worksheets,
    required QuizRepository assessments,
    required LearningProgressRepository progress,
    required SupportReportStore supportReports,
  })  : _api = api,
        _session = session,
        _metadata = metadata,
        _connectivity = connectivity,
        _classroomSetup = classroomSetup,
        _sessions = sessions,
        _worksheets = worksheets,
        _assessments = assessments,
        _progress = progress,
        _supportReports = supportReports,
        _acks = SyncAckStore(storage),
        _catalog = SyncedCatalogStore(storage);

  final ApiClient _api;
  final AuthSessionStore _session;
  final SyncMetadataStore _metadata;
  final ConnectivityService _connectivity;
  final ClassroomSetupRepository _classroomSetup;
  final ClassroomSessionRepository _sessions;
  final WorksheetRepository _worksheets;
  final QuizRepository _assessments;
  final LearningProgressRepository _progress;
  final SupportReportStore _supportReports;
  final SyncAckStore _acks;
  final SyncedCatalogStore _catalog;

  SyncStatus _status = const SyncStatus(state: SyncState.idle);
  final StreamController<SyncStatus> _stream =
      StreamController<SyncStatus>.broadcast();
  bool _inFlight = false;

  @override
  SyncStatus get status => _status;

  @override
  Stream<SyncStatus> get onStatusChanged => _stream.stream;

  @override
  Future<Result<SyncStatus>> syncNow() async {
    if (_inFlight) {
      return const Err<SyncStatus>(
        SyncException('A sync is already running.'),
      );
    }
    _inFlight = true;
    try {
      return await _run();
    } finally {
      _inFlight = false;
    }
  }

  Future<Result<SyncStatus>> _run() async {
    final String? token = await _session.accessToken();
    if (token == null || token.isEmpty) {
      const String message = 'Sign in again to sync your data.';
      _emit(SyncStatus(state: SyncState.failed, message: message));
      return Err<SyncStatus>(SyncException(message));
    }

    if (await _connectivity.check() == ConnectionStatus.offline) {
      final int pending = await _countPending();
      _emit(SyncStatus(
        state: SyncState.pending,
        pendingChanges: pending,
        message: 'Changes waiting to sync',
      ));
      return Ok<SyncStatus>(_status);
    }

    _emit(const SyncStatus(
      state: SyncState.checking,
      message: 'Checking for updates…',
      progress: 0.1,
    ));

    final Result<Map<String, dynamic>> statusResult =
        await _api.get(ApiEndpoints.syncStatus);
    switch (statusResult) {
      case Err<Map<String, dynamic>>(:final AppException error):
        final String reason = _describeError(error);
        _emit(SyncStatus(state: SyncState.failed, message: reason));
        return Err<SyncStatus>(SyncException(reason, cause: error));
      case Ok<Map<String, dynamic>>():
        break;
    }

    final List<Map<String, dynamic>> documents = await _buildPushDocuments();
    final int total = documents.length;
    final DateTime? since = await _metadata.lastSyncedAt();
    final String? deviceId = await _session.deviceId();

    _emit(SyncStatus(
      state: SyncState.uploading,
      pendingChanges: total,
      message: 'Uploading local changes…',
      progress: 0.2,
    ));

    final Result<Map<String, dynamic>> pushResult = await _api.post(
      ApiEndpoints.syncPush,
      body: <String, dynamic>{
        'deviceId': ?deviceId,
        'documents': documents,
      },
    );
    final DateTime? pushServerNow;
    switch (pushResult) {
      case Err<Map<String, dynamic>>(:final AppException error):
        final String reason = _describeError(error);
        _emit(SyncStatus(
          state: SyncState.failed,
          pendingChanges: total,
          message: reason,
        ));
        return Err<SyncStatus>(SyncException(reason, cause: error));
      case Ok<Map<String, dynamic>>(:final Map<String, dynamic> value):
        final int unacknowledged = await _applyPushAck(value, documents);
        pushServerNow = _parseTimestamp(value['serverNow']);
        if (unacknowledged > 0) {
          final String reason = '$unacknowledged item'
              '${unacknowledged == 1 ? '' : 's'} could not be synced.';
          _emit(SyncStatus(
            state: SyncState.failed,
            pendingChanges: unacknowledged,
            message: reason,
          ));
          return Err<SyncStatus>(SyncException(reason));
        }
    }

    _emit(const SyncStatus(
      state: SyncState.downloading,
      message: 'Downloading updates…',
      progress: 0.6,
    ));

    final String? sinceString = since?.toUtc().toIso8601String();

    final Result<Map<String, dynamic>> pullResult = await _api.post(
      ApiEndpoints.syncPull,
      body: <String, dynamic>{
        'since': ?sinceString,
        'deviceId': ?deviceId,
        'includeCatalog': true,
      },
    );
    switch (pullResult) {
      case Err<Map<String, dynamic>>(:final AppException error):
        final String reason = _describeError(error);
        _emit(SyncStatus(state: SyncState.failed, message: reason));
        return Err<SyncStatus>(SyncException(reason, cause: error));
      case Ok<Map<String, dynamic>>(:final Map<String, dynamic> value):
        await _applyPull(value);

        final DateTime? serverNow =
            pushServerNow ?? _parseTimestamp(value['serverNow']);
        if (serverNow != null) await _metadata.saveLastSyncedAt(serverNow);

        final SyncStatus done = SyncStatus(
          state: SyncState.completed,
          pendingChanges: 0,
          lastSyncedAt: serverNow,
          message: 'All content is up to date',
          progress: 1,
        );
        _emit(done);
        return Ok<SyncStatus>(done);
    }
  }

  /// Marks every locally pushed record the server acknowledged, so a later run
  /// does not resend it. Returns how many items came back unaccepted.
  Future<int> _applyPushAck(
    Map<String, dynamic> value,
    List<Map<String, dynamic>> documents,
  ) async {
    final Set<String> acked = <String>{};
    for (final Object? raw in value['acknowledged'] as List<dynamic>? ??
        const <dynamic>[]) {
      if (raw is! Map<String, dynamic>) continue;
      final String? type = raw['type'] as String?;
      final String? id = raw['id'] as String?;
      if (type != null && id != null) acked.add('$type|$id');
    }

    final int conflicts = (value['conflicts'] as List<dynamic>?)?.length ?? 0;
    final int errors = (value['errors'] as List<dynamic>?)?.length ?? 0;

    final TeacherAccount? account = await _session.account();
    final String teacherId = account?.id ?? '';

    for (final Map<String, dynamic> doc in documents) {
      final String type = doc['type'] as String;
      final String id = doc['id'] as String;
      if (!acked.contains('$type|$id')) continue;

      try {
        switch (type) {
          case 'classroomSetup':
            final ClassroomSetup? setup =
                await _classroomSetup.load(teacherId);
            if (setup != null) {
              await _classroomSetup.save(setup.copyWith(pendingSync: false));
            }
          case 'classroomSession':
            final ClassroomSession? session = await _sessions.byId(id);
            if (session != null) {
              await _sessions.save(
                session.copyWith(syncStatus: SessionSyncStatus.synced),
              );
            }
          case 'worksheet':
            await _acks.mark(SyncAckStore.worksheets, id);
          case 'assessmentResult':
            await _acks.mark(SyncAckStore.assessments, id);
          case 'progressEvent':
            await _acks.mark(SyncAckStore.progressEvents, id);
          case 'supportReport':
            await _acks.mark(SyncAckStore.supportReports, id);
        }
      } on Object catch (error, stackTrace) {
        AppLogger.error(
          'sync ack could not be applied for $type/$id',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    return errors + conflicts;
  }

  Map<String, dynamic> _pushDocument(
    String type,
    String id,
    Object data,
  ) =>
      <String, dynamic>{'type': type, 'id': id, 'data': data};

  Future<List<Map<String, dynamic>>> _buildPushDocuments() async {
    final List<Map<String, dynamic>> documents = <Map<String, dynamic>>[];
    final TeacherAccount? account = await _session.account();
    final String teacherId = account?.id ?? '';
    if (teacherId.isEmpty) return documents;

    final ClassroomSetup? setup = await _classroomSetup.load(teacherId);
    if (setup != null && setup.pendingSync) {
      documents.add(
        _pushDocument('classroomSetup', setup.teacherId, setup.toJson()),
      );
    }

    for (final ClassroomSession session in await _sessions.recent(limit: 50)) {
      if (session.syncStatus == SessionSyncStatus.synced) continue;
      documents.add(
        _pushDocument('classroomSession', session.sessionId, session.toJson()),
      );
    }

    for (final Worksheet worksheet in await _worksheets.all(limit: 50)) {
      if (!await _acks.has(SyncAckStore.worksheets, worksheet.id)) {
        documents.add(
          _pushDocument('worksheet', worksheet.id, worksheet.toJson()),
        );
      }
    }

    for (final QuizResult result in await _assessments.allResults()) {
      final String id = _assessmentDocId(result.lessonId);
      if (!await _acks.has(SyncAckStore.assessments, id)) {
        documents.add(_pushDocument('assessmentResult', id, result.toJson()));
      }
    }

    for (final ProgressEvent event in await _progress.all()) {
      if (!await _acks.has(SyncAckStore.progressEvents, event.id)) {
        documents.add(_pushDocument('progressEvent', event.id, event.toJson()));
      }
    }

    for (final SupportReport report in await _supportReports.reports()) {
      if (!await _acks.has(SyncAckStore.supportReports, report.id)) {
        documents.add(
          _pushDocument('supportReport', report.id, report.toJson()),
        );
      }
    }

    return documents;
  }

  Future<int> _countPending() async => (await _buildPushDocuments()).length;

  Future<void> _applyPull(Map<String, dynamic> value) async {
    final List<dynamic> documents =
        value['documents'] as List<dynamic>? ?? const <dynamic>[];
    await _applyDocuments(documents);

    final List<dynamic>? catalog = value['catalog'] as List<dynamic>?;
    if (catalog != null) {
      final List<Lesson> lessons = <Lesson>[];
      for (final Object? raw in catalog) {
        if (raw is! Map<String, dynamic>) continue;
        if (raw['type'] != 'lesson') continue;
        final Object? data = raw['data'];
        if (data is! Map<String, dynamic>) continue;
        final Lesson? lesson = _tryLesson(data);
        if (lesson != null) lessons.add(lesson);
      }
      await _catalog.saveLessons(lessons);
    }
  }

  Future<void> _applyDocuments(List<dynamic> documents) async {
    final TeacherAccount? account = await _session.account();
    final String teacherId = account?.id ?? '';

    for (final Object? raw in documents) {
      if (raw is! Map<String, dynamic>) continue;
      final String? type = raw['type'] as String?;
      final Object? rawData = raw['data'];
      if (type == null || rawData is! Map<String, dynamic>) continue;
      final DateTime? updatedAt =
          DateTime.tryParse(raw['updatedAt'] as String? ?? '');

      try {
        switch (type) {
          case 'classroomSetup':
            final ClassroomSetup? setup =
                _trySetup(rawData, expectedTeacherId: teacherId);
            if (setup != null) {
              await _classroomSetup.save(setup.copyWith(pendingSync: false));
            }
          case 'classroomSession':
            final ClassroomSession? session = _trySession(rawData);
            if (session != null) await _sessions.save(session);
          case 'assessmentResult':
            final String? lessonId = rawData['lessonId'] as String?;
            if (lessonId != null) {
              final QuizResult? local =
                  await _assessments.latestResult(lessonId);
              final bool serverWins = local == null ||
                  (updatedAt != null && local.finishedAt.isBefore(updatedAt));
              if (serverWins) {
                final QuizResult? result = _tryAssessment(rawData);
                if (result != null) {
                  await _assessments.saveResult(result);
                  // The server just sent this record, so it already holds it:
                  // stop the device from pushing the same bytes back.
                  await _acks.mark(
                    SyncAckStore.assessments,
                    _assessmentDocId(lessonId),
                  );
                }
              }
            }
          case 'worksheet':
            final Worksheet? worksheet = _tryWorksheet(rawData);
            if (worksheet != null) {
              await _worksheets.save(worksheet);
              await _acks.mark(SyncAckStore.worksheets, worksheet.id);
            }
          case 'progressEvent':
            final ProgressEvent? event = _tryProgressEvent(rawData);
            if (event != null) {
              await _progress.record(event);
              await _acks.mark(SyncAckStore.progressEvents, event.id);
            }
          case 'supportReport':
            final SupportReport? report = _trySupportReport(rawData);
            if (report != null) {
              final List<SupportReport> existing =
                  await _supportReports.reports();
              if (!existing.any((SupportReport r) => r.id == report.id)) {
                await _supportReports.add(report);
              }
              await _acks.mark(SyncAckStore.supportReports, report.id);
            }
        }
      } on Object catch (error, stackTrace) {
        AppLogger.error(
          'sync pull could not apply a $type document',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  /// A single stable id per lesson, because the device keeps only the latest
  /// result per lesson and the server upserts by id.
  static String _assessmentDocId(String lessonId) =>
      'assessment-$lessonId';

  static DateTime? _parseTimestamp(Object? raw) {
    if (raw is! String) return null;
    return DateTime.tryParse(raw);
  }

  String _describeError(AppException error) => switch (error) {
        UnauthorizedException() => 'Sign in again to sync your data.',
        NetworkException() => 'Could not reach the server. Check your '
            'connection and try again.',
        ServerException() => 'The sync server returned an error.',
        SyncException() => error.message,
        _ => 'Sync could not be completed.',
      };

  void _emit(SyncStatus next) {
    _status = next;
    if (!_stream.isClosed) _stream.add(next);
  }

  // --- Tolerant decoders ----------------------------------------------------
  // A record that cannot be read back must not take a whole pull down with it.

  ClassroomSetup? _trySetup(
    Map<String, dynamic> data, {
    required String expectedTeacherId,
  }) {
    try {
      final ClassroomSetup setup = ClassroomSetup.fromJson(data);
      if (setup.teacherId != expectedTeacherId) return null;
      return setup;
    } on Object {
      return null;
    }
  }

  Lesson? _tryLesson(Map<String, dynamic> data) {
    try {
      return Lesson.fromJson(data);
    } on Object {
      return null;
    }
  }

  ClassroomSession? _trySession(Map<String, dynamic> data) {
    try {
      return ClassroomSession.fromJson(data);
    } on Object {
      return null;
    }
  }

  Worksheet? _tryWorksheet(Map<String, dynamic> data) {
    try {
      return Worksheet.fromJson(data);
    } on Object {
      return null;
    }
  }

  QuizResult? _tryAssessment(Map<String, dynamic> data) {
    try {
      return QuizResult.fromJson(data);
    } on Object {
      return null;
    }
  }

  ProgressEvent? _tryProgressEvent(Map<String, dynamic> data) {
    try {
      return ProgressEvent.fromJson(data);
    } on Object {
      return null;
    }
  }

  SupportReport? _trySupportReport(Map<String, dynamic> data) {
    try {
      return SupportReport.fromJson(data);
    } on Object {
      return null;
    }
  }

  @override
  Future<Result<void>> downloadPack(String packId) async {
    // Content packs (audio, language models) do not exist on the backend yet,
    // so nothing is downloaded and nothing is claimed.
    return const Err<void>(
      SyncException('Content packs are not available from the server in this '
          'build.'),
    );
  }

  @override
  Future<Result<void>> cancel() async {
    return const Ok<void>(null);
  }

  Future<void> dispose() async {
    await _stream.close();
  }
}