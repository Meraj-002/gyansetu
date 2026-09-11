import 'package:flutter/foundation.dart';

import '../features/assessment/services/quiz_repository.dart';
import '../features/auth/services/authentication_service.dart';
import '../features/auth/services/auth_session_store.dart';
import '../features/auth/services/fastapi_authentication_service.dart';
import '../features/auth/services/offline_authentication_service.dart';
import '../features/classroom/services/classroom_session_repository.dart';
import '../features/profile/services/support_report_store.dart';
import '../features/profile/services/teacher_identity_repository.dart';
import '../features/progress/services/learning_progress_repository.dart';
import '../features/setup/data/classroom_setup_storage.dart';
import '../features/setup/services/classroom_setup_repository.dart';
import '../features/worksheet/services/worksheet_repository.dart';
import 'api/api_client.dart';
import 'api/api_endpoints.dart';
import 'api/http_api_client.dart';
import 'ai/ai_model_manager.dart';
import 'audio/audio_recorder.dart';
import 'audio/clip_player.dart';
import 'audio/record_audio_recorder.dart';
import 'audio/text_to_speech_service.dart';
import 'connectivity/connectivity_service.dart';
import 'downloads/download_manager.dart';
import 'downloads/download_transport.dart';
import 'resources/resource_catalogue_service.dart';
import 'speech/fallback_speech_recognition_service.dart';
import 'speech/speech_recognition_service.dart';
import 'storage/secure_storage_service.dart';
import 'sync/fastapi_sync_service.dart';
import 'sync/sync_metadata_store.dart';
import 'sync/sync_service.dart';
import 'translation/cache/translation_cache_store.dart';
import 'translation/cached_text_translation_service.dart';
import 'translation/fastapi_text_translation_service.dart';
import 'translation/fastapi_voice_translation_service.dart';
import 'translation/offline_first_translation_service.dart';
import 'translation/offline_model_translation_service.dart';
import 'translation/offline_phrasebook_translation_service.dart';
import 'translation/phrasebook_index/phrasebook_index_store.dart';
import 'translation/text_translation_service.dart';
import 'translation/voice_translation_service.dart';

/// A small shared-service locator.
///
/// The login screen and the sync screen need the *same* [ApiClient] and the
/// *same* [AuthSessionStore] so that a token stored at sign-in is exactly what
/// a later sync run reads. Each dependency is built once, lazily, and reused;
/// screens keep their injectable constructor parameters, so tests can still
/// hand in fakes and never touch this registry.
class ServiceRegistry {
  ServiceRegistry._();

  /// The production instance. Tests override by injecting services directly,
  /// never by pointing this at fakes.
  static final ServiceRegistry instance = ServiceRegistry._();

  SecureStorageService? _storage;
  AuthSessionStore? _session;
  PlatformConnectivityService? _connectivity;
  ApiClient? _api;
  ClassroomSetupRepository? _classrooms;
  ClassroomSessionRepository? _sessions;
  WorksheetRepository? _worksheets;
  QuizRepository? _assessments;
  LearningProgressRepository? _progress;
  SupportReportStore? _supportReports;
  OfflineAuthenticationService? _offline;
  AuthenticationService? _authentication;
  TeacherIdentityRepository? _identity;
  SyncService? _sync;
  DownloadManager? _downloadManager;
  ResourceCatalogueService? _resourceCatalogue;
  OfflinePhrasebookTranslationService? _offlineTranslation;
  TextTranslationService? _translation;
  AiModelManager? _aiModelManager;
  TranslationCacheStore? _cacheStore;
  PhrasebookIndexStore? _phrasebookIndexStore;
  SpeechRecognitionService? _speech;
  TextToSpeechService? _tts;
  VoiceTranslationService? _voice;
  AudioRecorder? _recorder;
  ClipPlayer? _player;

  SecureStorageService get storage =>
      _storage ??= PlatformSecureStorageService();

  AuthSessionStore get session => _session ??= AuthSessionStore(storage);

  ConnectivityService get connectivity =>
      _connectivity ??= PlatformConnectivityService();

  /// The one ApiClient everything shares, so the access token provider is read
  /// from the same session store the auth service wrote to.
  ApiClient get api => _api ??= HttpApiClient(
    baseUrl: ApiEndpoints.baseUrl,
    accessTokenProvider: () => session.accessToken(),
    onUnauthorized: session.handleUnauthorized,
  );

  /// The real offline download pipeline. Query params set the catalogue's
  /// mobile-page size; the transport shares this app's single ApiClient, so a
  /// token cached at sign-in is the token the downloader streams with.
  DownloadManager get downloadManager {
    final DownloadManager? held = _downloadManager;
    if (held != null) return held;
    final DownloadManager built = DownloadManager(
      storage: storage,
      transport: HttpDownloadTransport(
        baseUrl: ApiEndpoints.baseUrl,
        accessTokenProvider: () => session.accessToken(),
      ),
    );
    return _downloadManager = built;
  }

  ResourceCatalogueService get resourceCatalogue =>
      _resourceCatalogue ??= ResourceCatalogueService(api: api);

  /// The offline-first translator the classroom uses, wrapped in the bounded
  /// local cache so the full decision priority is:
  ///
  ///   cache → phrasebook → offline model → online backend → refused offline.
  ///
  /// Single graph, single cache, reused by every screen.
  TextTranslationService get translation {
    final TextTranslationService? held = _translation;
    if (held != null) return held;
    return _translation = CachedTextTranslationService(
      inner: OfflineFirstTranslationService(
        offline: offlineTranslation,
        offlineModel: OfflineModelTranslationService(manager: aiModelManager),
        online: FastApiTextTranslationService(api: api),
        connectivity: connectivity,
      ),
      store: translationCacheStore,
      connectivity: connectivity,
    );
  }

  /// One row per entry in SQLite on io targets, so a 2 GB device never holds
  /// the whole cache in memory; a session-only in-memory store elsewhere.
  TranslationCacheStore get translationCacheStore =>
      _cacheStore ??= deviceTranslationCacheStore;

  /// The device recogniser, with the development adapter only for languages no
  /// recogniser covers (which everything it produces labels as a mock). The
  /// fallback decision is made on first use, never at screen build.
  SpeechRecognitionService get speech =>
      _speech ??= FallbackSpeechRecognitionService();

  /// The platform TTS engine. Honest about which languages it has voices for.
  TextToSpeechService get tts => _tts ??= PlatformTextToSpeechService();

  /// The speech-to-speech translator: uploads a recorded clip to the backend,
  /// which proxies Adi Vaani and returns the translated text plus its spoken
  /// WAV (saved locally so the speaker button never re-asks the network).
  VoiceTranslationService get voice =>
      _voice ??= FastApiVoiceTranslationService(api: api);

  /// The device microphone recorder, for the voice-translation path.
  AudioRecorder get recorder => _recorder ??= RecordAudioRecorder();

  /// The local clip player, for replaying translated spoken WAVs.
  ClipPlayer get player => _player ??= AudioPlayersClipPlayer();

  /// The on-device phrasebook only. Everything it reports is genuinely on the
  /// device, and is genuinely [TranslationSource.offline]. Its index lives in
  /// the per-platform store (SQLite on io), so a larger phrasebook never sits
  /// in RAM on a 2 GB phone.
  OfflinePhrasebookTranslationService get offlineTranslation =>
      _offlineTranslation ??= OfflinePhrasebookTranslationService(
        source: downloadManager,
        indexStore: phrasebookIndexStore,
      );

  /// One row per record in SQLite on io targets; a session-only in-memory
  /// store elsewhere. The 2 GB phrasebook rule: a lookup reads one row.
  PhrasebookIndexStore get phrasebookIndexStore =>
      _phrasebookIndexStore ??= devicePhrasebookIndexStore;

  /// The model manager over the same download pipeline and catalogue.
  AiModelManager get aiModelManager =>
      _aiModelManager ??= ResourceBackedAiModelManager(
        downloadManager: downloadManager,
        catalogue: resourceCatalogue,
      );

  OfflineAuthenticationService get offline =>
      _offline ??= OfflineAuthenticationService(store: session);

  AuthenticationService get authentication =>
      _authentication ??= FastApiAuthenticationService(
        api: api,
        offline: offline,
        session: session,
        classrooms: classrooms,
      );

  /// Canonical identity over the shared client and the shared session.
  TeacherIdentityRepository get identity =>
      _identity ??= FastApiTeacherIdentityRepository(
        api: api,
        session: session,
        classrooms: classrooms,
      );

  ClassroomSetupRepository get classrooms => _classrooms ??=
      LocalClassroomSetupRepository(defaultClassroomSetupStorage());

  ClassroomSessionRepository get sessions =>
      _sessions ??= LocalClassroomSessionRepository(storage);

  WorksheetRepository get worksheets =>
      _worksheets ??= LocalWorksheetRepository(storage);

  QuizRepository get assessments =>
      _assessments ??= LocalQuizRepository(storage: storage);

  LearningProgressRepository get progress =>
      _progress ??= LocalLearningProgressRepository(storage);

  SupportReportStore get supportReports =>
      _supportReports ??= LocalSupportReportStore(storage);

  SyncService get sync {
    final SyncService? held = _sync;
    if (held != null) return held;
    final SyncService built = FastApiSyncService(
      api: api,
      session: session,
      metadata: LocalSyncMetadataStore(storage),
      connectivity: connectivity,
      storage: storage,
      classroomSetup: classrooms,
      sessions: sessions,
      worksheets: worksheets,
      assessments: assessments,
      progress: progress,
      supportReports: supportReports,
    );
    return _sync = built;
  }

  /// Test hook: forget every cached instance so the next getter constructs
  /// fresh ones. Production code never calls this.
  @visibleForTesting
  static void reset() {
    final ServiceRegistry r = instance;
    r._storage = null;
    r._session = null;
    r._connectivity = null;
    r._api = null;
    r._classrooms = null;
    r._sessions = null;
    r._worksheets = null;
    r._assessments = null;
    r._progress = null;
    r._supportReports = null;
    r._offline = null;
    r._authentication = null;
    r._identity = null;
    r._sync = null;
    r._downloadManager = null;
    r._resourceCatalogue = null;
    r._offlineTranslation = null;
    r._translation = null;
    r._aiModelManager = null;
    r._cacheStore = null;
    r._phrasebookIndexStore = null;
    r._speech = null;
    r._tts = null;
    r._voice = null;
    r._recorder = null;
    r._player = null;
  }
}
