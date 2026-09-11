import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/core/models/app_language.dart';
import 'package:gyan_setu_ai/features/classroom/models/conversation_turn.dart';
import 'package:gyan_setu_ai/services/ai/ai_model_manager.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';
import 'package:gyan_setu_ai/services/translation/cache/translation_cache_defs.dart';
import 'package:gyan_setu_ai/services/translation/offline_first_translation_service.dart';
import 'package:gyan_setu_ai/services/translation/offline_model_translation_service.dart';
import 'package:gyan_setu_ai/services/translation/text_translation_service.dart';

import 'translation_test_doubles.dart';

/// A manager that reports the verified pack on disk, so the offline-model
/// adapter's supports/installed path is exercised without a download pipeline.
class ModelAvailableManager implements AiModelManager {
  const ModelAvailableManager();

  @override
  Future<AiModelState> modelState(String packId) async => AiModelState.ready;

  @override
  Future<bool> isModelAvailable(String packId) async => true;

  @override
  Future<AiModelInfo?> modelInfo(String packId) async =>
      AiModelInfo(id: packId, version: 'test-model-1', sizeBytes: 1);

  @override
  Future<void> download(String packId) async {}

  @override
  Future<void> loadModel(String packId) async {}

  @override
  Future<void> unloadModel(String packId) async {}

  @override
  Future<void> deleteModel(String packId) async {}
}

void main() {
  const TranslationRequest request = TranslationRequest(
    sourceText: 'बच्चों, कितने आम हैं?',
    sourceLanguage: 'hi-IN',
    targetLanguage: 'sat',
  );

  group('OfflineModelTranslationService', () {
    test('refuses honestly when no verified model pack is installed', () async {
      final OfflineModelTranslationService service =
          OfflineModelTranslationService(
        manager: const HaltWithoutCatalogueAiModelManager(),
      );

      expect(await service.isInstalled(), isFalse);
      expect(await service.supportsPair('hi-IN', 'sat'), isFalse);

      await expectLater(
        service.translate(request),
        throwsA(isA<TextTranslationFailure>()
            .having((TextTranslationFailure f) => f.reason, 'reason',
                TranslationFailureReason.modelUnavailable)
            .having((TextTranslationFailure f) => f.message, 'message',
                contains('No offline translation model is installed'))),
      );
    });

    test('supports the pair only once the verified pack is on disk', () async {
      final OfflineModelTranslationService service =
          OfflineModelTranslationService(
        manager: const ModelAvailableManager(),
      );

      expect(await service.isInstalled(), isTrue);
      expect(await service.supportsPair('hi-IN', 'sat'), isTrue);
      expect(await service.supportsPair('sat', 'hi-IN'), isTrue);
      expect(await service.supportsPair('hi-IN', 'bn-IN'), isFalse);
    });
  });

  group('the decision engine consults the offline model', () {
    test('phrasebook first: no model or network call is made', () async {
      final RecordingTranslator model = RecordingTranslator(
        answer: offlineResult(),
        supported: false,
      );
      final RecordingTranslator online = RecordingTranslator(
        answer: onlineResult(),
        requiresNetwork: true,
        supported: false,
      );
      final OfflineFirstTranslationService engine = OfflineFirstTranslationService(
        offline: RecordingTranslator(answer: offlineResult()),
        offlineModel: model,
        online: online,
        connectivity: StaticConnectivityService(ConnectionStatus.online),
      );

      final TranslationResult result = await engine.translate(request);

      expect(result.source, TranslationSource.phrasebook);
      expect(model.calls, 0);
      expect(online.calls, 0);
    });

    test('model answers when the phrasebook misses and the device is online',
        () async {
      final RecordingTranslator model = RecordingTranslator(
        answer: offlineResult(
          text: 'MODEL transliteration — a real engine would run here',
        ).copyWith(source: TranslationSource.offlineModel),
      );
      final RecordingTranslator online = RecordingTranslator(
        answer: onlineResult(),
        requiresNetwork: true,
        supported: false,
      );
      final OfflineFirstTranslationService engine = OfflineFirstTranslationService(
        offline: RecordingTranslator(
          failure: const TextTranslationFailure(
            TranslationFailureReason.notConfigured,
            "This sentence isn't in the offline phrasebook yet.",
          ),
        ),
        offlineModel: model,
        online: online,
        connectivity: StaticConnectivityService(ConnectionStatus.online),
      );

      final TranslationResult result = await engine.translate(request);

      expect(result.source, TranslationSource.offlineModel);
      expect(online.calls, 0);
    });

    test('a missing model falls through to the honest offline refusal',
        () async {
      final RecordingTranslator model = RecordingTranslator(
        failure: const TextTranslationFailure(
          TranslationFailureReason.modelUnavailable,
          'No offline translation model is installed on this device yet.',
        ),
        supported: false,
      );
      final RecordingTranslator online = RecordingTranslator(
        answer: onlineResult(),
        requiresNetwork: true,
        supported: false,
      );
      final OfflineFirstTranslationService engine = OfflineFirstTranslationService(
        offline: RecordingTranslator(
          failure: const TextTranslationFailure(
            TranslationFailureReason.notConfigured,
            "This sentence isn't in the offline phrasebook yet.",
          ),
        ),
        offlineModel: model,
        online: online,
        forceOfflineOnly: true,
        connectivity: StaticConnectivityService(ConnectionStatus.online),
      );

      await expectLater(
        engine.translate(request),
        throwsA(isA<TextTranslationFailure>()
            .having((TextTranslationFailure f) => f.reason, 'reason',
                TranslationFailureReason.needsConnection)
            .having((TextTranslationFailure f) => f.message, 'message',
                'Offline translation is unavailable for this language.')),
      );
      expect(online.calls, 0,
          reason: 'a missing model must never force a network call.');
    });

    test('a missing model falls through to the online provider when online',
        () async {
      final RecordingTranslator model = RecordingTranslator(
        failure: const TextTranslationFailure(
          TranslationFailureReason.modelUnavailable,
          'No offline translation model is installed on this device yet.',
        ),
        supported: false,
      );
      final RecordingTranslator online = RecordingTranslator(
        answer: onlineResult(),
        requiresNetwork: true,
      );
      final OfflineFirstTranslationService engine = OfflineFirstTranslationService(
        offline: RecordingTranslator(
          failure: const TextTranslationFailure(
            TranslationFailureReason.notConfigured,
            "This sentence isn't in the offline phrasebook yet.",
          ),
        ),
        offlineModel: model,
        online: online,
        connectivity: StaticConnectivityService(ConnectionStatus.online),
      );

      final TranslationResult result = await engine.translate(request);

      expect(result.source, TranslationSource.onlineBackend);
      expect(online.calls, 1);
    });
  });

  group('the per-row cache store', () {
    const TranslationRequest request = TranslationRequest(
      sourceText: 'एक',
      sourceLanguage: 'hi-IN',
      targetLanguage: 'sat',
    );

    test('round-trips a row and keeps its provenance honest', () async {
      final MemoryTranslationCacheStore store = MemoryTranslationCacheStore();
      await store.write(CachedTranslationEntry(
        key: request.cacheKey('offline-phrasebook-1'),
        translatedText: "mit'",
        modelVersion: 'offline-phrasebook-1',
        spokenText: 'मित्',
        confidence: null,
        reviewedBySpeaker: false,
        sourceName: TranslationSource.phrasebook.name,
        savedAt: DateTime.utc(2026, 1, 1),
      ));

      final CachedTranslationEntry? hit = await store.read(
        request.cacheKey('offline-phrasebook-1'),
      );
      expect(hit, isNotNull);
      expect(hit!.translatedText, "mit'");
      expect(hit.sourceName, TranslationSource.phrasebook.name);
      expect(hit.reviewedBySpeaker, isFalse);
      expect(await store.read(request.cacheKey('translation-model-v9')), isNull);
    });

    test('trim keeps the most recent rows and drops the oldest first',
        () async {
      final MemoryTranslationCacheStore store = MemoryTranslationCacheStore();
      for (int i = 0; i < 5; i++) {
        await store.write(CachedTranslationEntry(
          key: 'row-$i',
          translatedText: 'text-$i',
          modelVersion: 'v1',
          savedAt: DateTime.utc(2026, 1, i + 1),
        ));
      }

      await store.trim(3);

      expect(await store.count(), 3);
      expect(await store.read('row-0'), isNull);
      expect(await store.read('row-1'), isNull);
      expect(await store.read('row-4'), isNotNull);
    });

    test('clear empties the store', () async {
      final MemoryTranslationCacheStore store = MemoryTranslationCacheStore();
      await store.write(CachedTranslationEntry(
        key: 'a',
        translatedText: 'x',
        modelVersion: 'v1',
      ));

      await store.clear();

      expect(await store.count(), 0);
      expect(await store.read('a'), isNull);
    });
  });

  group('canonical language capabilities are honest', () {
    test('Hindi has recogniser, voice and the documented phrasebook pair', () {
      const AppLanguage hindi = AppLanguage.hindi;
      expect(hindi.capabilities.hasKnownSpeechRecognition, isTrue);
      expect(hindi.capabilities.hasKnownTtsVoice, isTrue);
      expect(hindi.knownOfflinePair('hi-IN', 'sat'), isTrue);
      expect(hindi.knownOfflinePair('sat', 'hi-IN'), isTrue);
      expect(hindi.knownOfflinePair('hi-IN', 'bn-IN'), isFalse);
    });

    test('the tribal languages never claim a recogniser or a voice', () {
      for (final AppLanguage language in <AppLanguage>[
        AppLanguage.santali,
        AppLanguage.mundari,
        AppLanguage.ho,
      ]) {
        expect(language.capabilities.hasKnownSpeechRecognition, isFalse,
            reason: '${language.name} has no recogniser anywhere.');
        expect(language.capabilities.hasKnownTtsVoice, isFalse,
            reason: '${language.name} has no TTS voice anywhere.');
      }
    });

    test('scalable languages are marked speech- and voice-capable', () {
      for (final AppLanguage language in <AppLanguage>[
        AppLanguage.english,
        AppLanguage.bengali,
      ]) {
        expect(language.capabilities.hasKnownSpeechRecognition, isTrue);
        expect(language.capabilities.hasKnownTtsVoice, isTrue);
      }
    });
  });

  group('ConversationTurn provenance survives serialization', () {
    ConversationTurn turnWith(TranslationSource? source) => ConversationTurn(
          id: 't1',
          sessionId: 's1',
          speaker: TurnSpeaker.teacher,
          sourceLanguage: 'hi-IN',
          targetLanguage: 'sat',
          timestamp: DateTime.utc(2026, 1, 1),
          status: TurnStatus.played,
          sourceText: 'एक',
          translatedText: 'mit\'',
          wasOffline: true,
          source: source,
        );

    test('a phrasebook source survives a toJson/fromJson round trip', () {
      final ConversationTurn restored =
          ConversationTurn.fromJson(turnWith(TranslationSource.phrasebook).toJson());
      expect(restored.source, TranslationSource.phrasebook);
      expect(restored.wasOffline, isTrue);
    });

    test('an online source survives, and a missing one stays null', () {
      final ConversationTurn restored =
          ConversationTurn.fromJson(turnWith(TranslationSource.onlineBackend).toJson());
      expect(restored.source, TranslationSource.onlineBackend);

      final ConversationTurn blank =
          ConversationTurn.fromJson(turnWith(null).toJson());
      expect(blank.source, isNull);
    });
  });
}