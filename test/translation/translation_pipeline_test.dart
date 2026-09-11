import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/core/errors/app_exception.dart';
import 'package:gyan_setu_ai/core/utils/result.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';
import 'package:gyan_setu_ai/services/translation/cached_text_translation_service.dart';
import 'package:gyan_setu_ai/services/translation/cache/translation_cache_defs.dart';
import 'package:gyan_setu_ai/services/translation/fastapi_text_translation_service.dart';
import 'package:gyan_setu_ai/services/translation/offline_first_translation_service.dart';
import 'package:gyan_setu_ai/services/translation/offline_phrasebook_translation_service.dart';
import 'package:gyan_setu_ai/services/translation/text_translation_service.dart';

import '../api/api_test_doubles.dart';
import 'translation_test_doubles.dart';

void main() {
  group('OfflinePhrasebookTranslationService', () {
    const String packPath = '/memory/translation-hindi-santali.jsonl';
    late MemoryLocalContentIo io;

    setUp(() {
      io = MemoryLocalContentIo();
    });

    OfflinePhrasebookTranslationService build(
      String? content, {
      bool ready = true,
    }) {
      final FixedPackSource source = FixedPackSource();
      if (content != null) {
        io.put(packPath, content);
        source.path = ready ? packPath : null;
      }
      return OfflinePhrasebookTranslationService(source: source, io: io);
    }

    const String phrasebook = 'बच्चों, कितने आम हैं?';

    test('is not installed when no pack exists', () async {
      final OfflinePhrasebookTranslationService service = build(null);
      expect(await service.isInstalled(), isFalse);
      await expectLater(
        service.translate(
          TranslationRequest(
            sourceText: phrasebook,
            sourceLanguage: 'hi-IN',
            targetLanguage: 'sat',
          ),
        ),
        throwsA(
          isA<TextTranslationFailure>()
              .having(
                (TextTranslationFailure f) => f.reason,
                'reason',
                TranslationFailureReason.notConfigured,
              )
              .having(
                (TextTranslationFailure f) => f.message,
                'message',
                contains('not installed yet'),
              ),
        ),
      );
    });

    test('supports only the installed pair', () async {
      final OfflinePhrasebookTranslationService service = build(null);
      expect(await service.supportsPair('hi-IN', 'sat'), isFalse);
      expect(await service.supportsPair('sat', 'hi-IN'), isFalse);

      final OfflinePhrasebookTranslationService installed = build(
        buildPhrasebook(const <FixtureLine>[
          FixtureLine(
            sourceLanguage: 'hindi',
            targetLanguage: 'santali',
            sourceText: phrasebook,
            targetText: "Gidra'ko, kete ul menaka?",
            spokenText: 'गिड़ाको, केते उल् मेनाका?',
          ),
        ]),
      );
      expect(await installed.supportsPair('hi-IN', 'sat'), isTrue);
      expect(await installed.supportsPair('sat', 'hi-IN'), isTrue);
    });

    test(
      'answers an authored sentence as offline, with no invented score',
      () async {
        final OfflinePhrasebookTranslationService service = build(
          buildPhrasebook(const <FixtureLine>[
            FixtureLine(
              sourceLanguage: 'hindi',
              targetLanguage: 'santali',
              sourceText: phrasebook,
              targetText: "Gidra'ko, kete ul menaka?",
              spokenText: 'गिड़ाको, केते उल् मेनाका?',
            ),
          ]),
        );

        final TranslationResult result = await service.translate(
          TranslationRequest(
            sourceText: phrasebook,
            sourceLanguage: 'hi-IN',
            targetLanguage: 'sat',
          ),
        );

        expect(result.translatedText, "Gidra'ko, kete ul menaka?");
        expect(result.source, TranslationSource.phrasebook);
        expect(result.confidence, isNull);
        expect(result.spokenText, 'गिड़ाको, केते उल् मेनाका?');
        expect(await service.isInstalled(), isTrue);
      },
    );

    test('tolerates punctuation and case in the lookup', () async {
      final OfflinePhrasebookTranslationService service = build(
        buildPhrasebook(const <FixtureLine>[
          FixtureLine(
            sourceLanguage: 'hindi',
            targetLanguage: 'santali',
            sourceText: phrasebook,
            targetText: "Gidra'ko, kete ul menaka?",
          ),
        ]),
      );

      final TranslationResult result = await service.translate(
        TranslationRequest(
          sourceText: '${phrasebook.replaceFirst('?', ' ?')}  ',
          sourceLanguage: 'hi-IN',
          targetLanguage: 'sat',
        ),
      );

      expect(result.translatedText, "Gidra'ko, kete ul menaka?");
    });

    test('reads the reverse direction from its explicit pair field', () async {
      final OfflinePhrasebookTranslationService service = build(
        buildPhrasebook(const <FixtureLine>[
          FixtureLine(
            sourceLanguage: 'santali',
            targetLanguage: 'hindi',
            sourceText: "Gidra'ko, kete ul menaka?",
            targetText: phrasebook,
          ),
        ]),
      );

      final TranslationResult result = await service.translate(
        TranslationRequest(
          sourceText: "Gidra'ko, kete ul menaka?",
          sourceLanguage: 'sat',
          targetLanguage: 'hi-IN',
        ),
      );

      expect(result.translatedText, phrasebook);
    });

    test('refuses a sentence that is not written down — no guessing', () async {
      final OfflinePhrasebookTranslationService service = build(
        buildPhrasebook(const <FixtureLine>[
          FixtureLine(
            sourceLanguage: 'hindi',
            targetLanguage: 'santali',
            sourceText: phrasebook,
            targetText: "Gidra'ko, kete ul menaka?",
          ),
        ]),
      );

      await expectLater(
        service.translate(
          TranslationRequest(
            sourceText: 'कल की छुट्टी के बारे में बात करें।',
            sourceLanguage: 'hi-IN',
            targetLanguage: 'sat',
          ),
        ),
        throwsA(
          isA<TextTranslationFailure>()
              .having(
                (TextTranslationFailure f) => f.reason,
                'reason',
                TranslationFailureReason.notConfigured,
              )
              .having(
                (TextTranslationFailure f) => f.message,
                'message',
                contains("isn't in the offline phrasebook yet"),
              ),
        ),
      );
    });

    test('re-reads the pack after forget()', () async {
      final OfflinePhrasebookTranslationService service = build(
        buildPhrasebook(const <FixtureLine>[
          FixtureLine(
            sourceLanguage: 'hindi',
            targetLanguage: 'santali',
            sourceText: phrasebook,
            targetText: 'old answer',
          ),
        ]),
      );
      expect(
        (await service.translate(
          TranslationRequest(
            sourceText: phrasebook,
            sourceLanguage: 'hi-IN',
            targetLanguage: 'sat',
          ),
        )).translatedText,
        'old answer',
      );

      io.put(
        packPath,
        buildPhrasebook(const <FixtureLine>[
          FixtureLine(
            sourceLanguage: 'hindi',
            targetLanguage: 'santali',
            sourceText: phrasebook,
            targetText: 'corrected answer',
          ),
        ]),
      );
      service.forget();

      expect(
        (await service.translate(
          TranslationRequest(
            sourceText: phrasebook,
            sourceLanguage: 'hi-IN',
            targetLanguage: 'sat',
          ),
        )).translatedText,
        'corrected answer',
      );
    });
  });

  group('OfflineFirstTranslationService', () {
    const String exactOfflineMessage =
        'Offline translation is unavailable for this language.';

    test(
      'offline provider that covers the sentence answers without the network',
      () async {
        final RecordingTranslator offline = RecordingTranslator(
          answer: offlineResult(),
          requiresNetwork: false,
        );
        final RecordingTranslator online = RecordingTranslator(
          answer: onlineResult(),
          requiresNetwork: true,
        );
        final OfflineFirstTranslationService orchestrator =
            OfflineFirstTranslationService(
              offline: offline,
              online: online,
              connectivity: StaticConnectivityService(ConnectionStatus.offline),
            );

        final TranslationResult result = await orchestrator.translate(
          TranslationRequest(
            sourceText: 'बच्चों, कितने आम हैं?',
            sourceLanguage: 'hi-IN',
            targetLanguage: 'sat',
          ),
        );

        expect(result.source, TranslationSource.phrasebook);
        expect(offline.calls, 1);
        expect(
          online.calls,
          0,
          reason: 'offline answers; the network is not touched',
        );
        expect(orchestrator.requiresNetwork, isFalse);
      },
    );

    test(
      'offline and uncovered: refuses with the exact message, no network call',
      () async {
        final RecordingTranslator offline = RecordingTranslator(
          failure: const TextTranslationFailure(
            TranslationFailureReason.notConfigured,
            "This sentence isn't in the offline phrasebook yet.",
          ),
          requiresNetwork: false,
        );
        final RecordingTranslator online = RecordingTranslator(
          answer: onlineResult(),
          requiresNetwork: true,
        );
        final OfflineFirstTranslationService orchestrator =
            OfflineFirstTranslationService(
              offline: offline,
              online: online,
              connectivity: StaticConnectivityService(ConnectionStatus.offline),
            );

        await expectLater(
          orchestrator.translate(
            TranslationRequest(
              sourceText: 'कल की छुट्टी के बारे में बात करें।',
              sourceLanguage: 'hi-IN',
              targetLanguage: 'sat',
            ),
          ),
          throwsA(
            isA<TextTranslationFailure>()
                .having(
                  (TextTranslationFailure f) => f.reason,
                  'reason',
                  TranslationFailureReason.needsConnection,
                )
                .having(
                  (TextTranslationFailure f) => f.message,
                  'message',
                  exactOfflineMessage,
                ),
          ),
        );
        expect(online.calls, 0, reason: 'offline means no network call, ever.');
      },
    );

    test(
      'offline and uncovered but online: falls back and labels the answer',
      () async {
        final RecordingTranslator offline = RecordingTranslator(
          failure: const TextTranslationFailure(
            TranslationFailureReason.notConfigured,
            "This sentence isn't in the offline phrasebook yet.",
          ),
          requiresNetwork: false,
        );
        final RecordingTranslator online = RecordingTranslator(
          answer: onlineResult(),
          requiresNetwork: true,
        );
        final OfflineFirstTranslationService orchestrator =
            OfflineFirstTranslationService(
              offline: offline,
              online: online,
              connectivity: StaticConnectivityService(ConnectionStatus.online),
            );

        final TranslationResult result = await orchestrator.translate(
          TranslationRequest(
            sourceText: 'कल की छुट्टी के बारे में बात करें।',
            sourceLanguage: 'hi-IN',
            targetLanguage: 'sat',
          ),
        );

        expect(result.source, TranslationSource.onlineBackend);
        expect(offline.calls, 1);
        expect(online.calls, 1);
      },
    );

    test(
      'uncovered while offline still refuses even inside force-offline tests',
      () async {
        final RecordingTranslator offline = RecordingTranslator(
          failure: const TextTranslationFailure(
            TranslationFailureReason.notConfigured,
            "This sentence isn't in the offline phrasebook yet.",
          ),
        );
        final RecordingTranslator online = RecordingTranslator(
          answer: onlineResult(),
          requiresNetwork: true,
        );
        final OfflineFirstTranslationService orchestrator =
            OfflineFirstTranslationService(
              offline: offline,
              online: online,
              connectivity: StaticConnectivityService(ConnectionStatus.offline),
            );

        await expectLater(
          orchestrator.translate(
            TranslationRequest(
              sourceText: 'कल की छुट्टी के बारे में बात करें।',
              sourceLanguage: 'hi-IN',
              targetLanguage: 'sat',
            ),
          ),
          throwsA(
            isA<TextTranslationFailure>().having(
              (TextTranslationFailure f) => f.reason,
              'reason',
              TranslationFailureReason.needsConnection,
            ),
          ),
        );
        expect(online.calls, 0);
      },
    );

    test('an unsupported pair is refused as unsupported immediately', () async {
      final RecordingTranslator offline = RecordingTranslator(
        failure: const TextTranslationFailure(
          TranslationFailureReason.unsupportedPair,
          'pair not supported',
        ),
        requiresNetwork: false,
      );
      final RecordingTranslator online = RecordingTranslator(
        answer: onlineResult(),
        requiresNetwork: true,
      );
      final OfflineFirstTranslationService orchestrator =
          OfflineFirstTranslationService(
            offline: offline,
            online: online,
            connectivity: StaticConnectivityService(ConnectionStatus.online),
          );

      await expectLater(
        orchestrator.translate(
          TranslationRequest(
            sourceText: 'hello',
            sourceLanguage: 'en-IN',
            targetLanguage: 'sat',
          ),
        ),
        throwsA(
          isA<TextTranslationFailure>().having(
            (TextTranslationFailure f) => f.reason,
            'reason',
            TranslationFailureReason.unsupportedPair,
          ),
        ),
      );
      expect(online.calls, 0);
    });
  });

  group('FastApiTextTranslationService', () {
    test('decodes an online answer and reports the online source', () async {
      final ScriptedApiClient api = ScriptedApiClient()
        ..onPost = () => Ok<Map<String, dynamic>>(<String, dynamic>{
          'translatedText': "Gidra'ko, kete ul menaka?",
          'spokenText': 'गिड़ाको, केते उल् मेनाका?',
          'sourceText': 'बच्चों, कितने आम हैं?',
          'sourceLanguage': 'hindi',
          'targetLanguage': 'santali',
          'provider': 'indic_trans2',
          'model': 'TigreGotico/indictrans2-indic-indic-dist-320M-onnx',
          'modelVersion': 'indictrans2-indic-indic-dist-320M-onnx-int8',
          'isRealModel': true,
          'confidence': null,
          'reviewedBySpeaker': false,
        });
      final FastApiTextTranslationService service =
          FastApiTextTranslationService(api: api);

      final TranslationResult result = await service.translate(
        TranslationRequest(
          sourceText: 'बच्चों, कितने आम हैं?',
          sourceLanguage: 'hi-IN',
          targetLanguage: 'sat',
          context: const <String, dynamic>{'lessonId': 'c1-num-counting-1-10'},
        ),
      );

      expect(result.translatedText, "Gidra'ko, kete ul menaka?");
      expect(result.originalText, 'बच्चों, कितने आम हैं?');
      expect(result.sourceLanguage, 'hindi');
      expect(result.targetLanguage, 'santali');
      expect(result.provider, 'indic_trans2');
      expect(
        result.model,
        'TigreGotico/indictrans2-indic-indic-dist-320M-onnx',
      );
      expect(
        result.modelVersion,
        'indictrans2-indic-indic-dist-320M-onnx-int8',
      );
      expect(result.engineIsRealModel, isTrue);
      expect(result.source, TranslationSource.onlineBackend);
      expect(result.spokenText, 'गिड़ाको, केते उल् मेनाका?');
      expect(api.postPaths, <String>['/api/v1/translation/translate']);
      final Map<String, Object?> body =
          api.postBodies.single as Map<String, Object?>;
      expect(body['text'], 'बच्चों, कितने आम हैं?');
      expect(body['source_language'], 'hin');
      expect(body['target_language'], 'sat');
      expect(
        body.keys,
        unorderedEquals(<String>['text', 'source_language', 'target_language']),
      );
      expect(service.requiresNetwork, isTrue);
    });

    test('a 404 becomes an honest no-rule answer', () async {
      final ScriptedApiClient api = ScriptedApiClient()
        ..onPost = () => Err<Map<String, dynamic>>(
          ServerException('no rule', statusCode: 404),
        );
      final FastApiTextTranslationService service =
          FastApiTextTranslationService(api: api);

      await expectLater(
        service.translate(
          TranslationRequest(
            sourceText: 'unmapped sentence',
            sourceLanguage: 'hi-IN',
            targetLanguage: 'sat',
          ),
        ),
        throwsA(
          isA<TextTranslationFailure>()
              .having(
                (TextTranslationFailure f) => f.reason,
                'reason',
                TranslationFailureReason.notConfigured,
              )
              .having(
                (TextTranslationFailure f) => f.message,
                'message',
                contains('no rule'),
              ),
        ),
      );
    });

    test(
      'a network error becomes needsConnection, never a fake answer',
      () async {
        final ScriptedApiClient api = ScriptedApiClient()
          ..onPost = () =>
              Err<Map<String, dynamic>>(NetworkException('timed out'));
        final FastApiTextTranslationService service =
            FastApiTextTranslationService(api: api);

        await expectLater(
          service.translate(
            TranslationRequest(
              sourceText: 'बच्चों, कितने आम हैं?',
              sourceLanguage: 'hi-IN',
              targetLanguage: 'sat',
            ),
          ),
          throwsA(
            isA<TextTranslationFailure>().having(
              (TextTranslationFailure f) => f.reason,
              'reason',
              TranslationFailureReason.needsConnection,
            ),
          ),
        );
      },
    );

    test('an empty server answer is a failure, not empty success', () async {
      final ScriptedApiClient api = ScriptedApiClient()
        ..onPost = () =>
            Ok<Map<String, dynamic>>(<String, dynamic>{'translatedText': ''});
      final FastApiTextTranslationService service =
          FastApiTextTranslationService(api: api);

      await expectLater(
        service.translate(
          TranslationRequest(
            sourceText: 'बच्चों, कितने आम हैं?',
            sourceLanguage: 'hi-IN',
            targetLanguage: 'sat',
          ),
        ),
        throwsA(
          isA<TextTranslationFailure>().having(
            (TextTranslationFailure f) => f.reason,
            'reason',
            TranslationFailureReason.failed,
          ),
        ),
      );
    });

    test(
      'an expired session is surfaced without inventing an answer',
      () async {
        final ScriptedApiClient api = ScriptedApiClient()
          ..onPost = () => Err<Map<String, dynamic>>(
            const UnauthorizedException('invalid_token'),
          );
        final FastApiTextTranslationService service =
            FastApiTextTranslationService(api: api);

        await expectLater(
          service.translate(
            TranslationRequest(
              sourceText: 'बच्चों, कितने आम हैं?',
              sourceLanguage: 'hi-IN',
              targetLanguage: 'sat',
            ),
          ),
          throwsA(
            isA<TextTranslationFailure>()
                .having(
                  (TextTranslationFailure f) => f.reason,
                  'reason',
                  TranslationFailureReason.unauthorized,
                )
                .having(
                  (TextTranslationFailure f) => f.message,
                  'message',
                  contains('sign in again'),
                ),
          ),
        );
      },
    );

    test('a validation error is actionable', () async {
      final ScriptedApiClient api = ScriptedApiClient()
        ..onPost = () => Err<Map<String, dynamic>>(
          const ServerException(
            'this language pair is not supported yet',
            statusCode: 422,
          ),
        );
      final FastApiTextTranslationService service =
          FastApiTextTranslationService(api: api);

      await expectLater(
        service.translate(
          TranslationRequest(
            sourceText: 'hello',
            sourceLanguage: 'hi-IN',
            targetLanguage: 'sat',
          ),
        ),
        throwsA(
          isA<TextTranslationFailure>()
              .having(
                (TextTranslationFailure f) => f.reason,
                'reason',
                TranslationFailureReason.failed,
              )
              .having(
                (TextTranslationFailure f) => f.message,
                'message',
                contains('language pair'),
              ),
        ),
      );
    });

    test('a model outage is retryable', () async {
      final ScriptedApiClient api = ScriptedApiClient()
        ..onPost = () => Err<Map<String, dynamic>>(
          const ServerException(
            'The translation model is unavailable right now.',
            statusCode: 503,
          ),
        );
      final FastApiTextTranslationService service =
          FastApiTextTranslationService(api: api);

      await expectLater(
        service.translate(
          TranslationRequest(
            sourceText: 'बच्चों, कितने आम हैं?',
            sourceLanguage: 'hi-IN',
            targetLanguage: 'sat',
          ),
        ),
        throwsA(
          isA<TextTranslationFailure>()
              .having(
                (TextTranslationFailure f) => f.reason,
                'reason',
                TranslationFailureReason.modelUnavailable,
              )
              .having(
                (TextTranslationFailure f) => f.message,
                'message',
                contains('unavailable'),
              ),
        ),
      );
    });
  });

  group('CachedTextTranslationService', () {
    test('an on-device provider is never blocked by being offline', () async {
      final RecordingTranslator inner = RecordingTranslator(
        answer: offlineResult(),
        requiresNetwork: false,
      );
      final CachedTextTranslationService cached = CachedTextTranslationService(
        inner: inner,
        store: MemoryTranslationCacheStore(),
        connectivity: StaticConnectivityService(ConnectionStatus.offline),
      );

      final TranslationResult result = await cached.translate(
        TranslationRequest(
          sourceText: 'बच्चों, कितने आम हैं?',
          sourceLanguage: 'hi-IN',
          targetLanguage: 'sat',
        ),
      );

      expect(result.source, TranslationSource.phrasebook);
      expect(inner.calls, 1);
    });

    test(
      'an online provider is blocked offline only when not cached',
      () async {
        final RecordingTranslator inner = RecordingTranslator(
          answer: onlineResult(),
          requiresNetwork: true,
        );
        final CachedTextTranslationService cached =
            CachedTextTranslationService(
              inner: inner,
              store: MemoryTranslationCacheStore(),
              connectivity: StaticConnectivityService(ConnectionStatus.offline),
            );

        await expectLater(
          cached.translate(
            TranslationRequest(
              sourceText: 'बच्चों, कितने आम हैं?',
              sourceLanguage: 'hi-IN',
              targetLanguage: 'sat',
            ),
          ),
          throwsA(
            isA<TextTranslationFailure>().having(
              (TextTranslationFailure f) => f.reason,
              'reason',
              TranslationFailureReason.needsConnection,
            ),
          ),
        );
        expect(
          inner.calls,
          0,
          reason: 'no network call while the device is offline.',
        );
      },
    );

    test(
      'a cached answer is served cached and the provider is not called',
      () async {
        final MemoryTranslationCacheStore store = MemoryTranslationCacheStore();
        final RecordingTranslator inner = RecordingTranslator(
          answer: onlineResult(),
          requiresNetwork: true,
        );
        final CachedTextTranslationService cached =
            CachedTextTranslationService(
              inner: inner,
              store: store,
              connectivity: StaticConnectivityService(ConnectionStatus.online),
            );

        await cached.translate(
          TranslationRequest(
            sourceText: 'बच्चों, कितने आम हैं?',
            sourceLanguage: 'hi-IN',
            targetLanguage: 'sat',
          ),
        );
        expect(inner.calls, 1);

        final CachedTextTranslationService second =
            CachedTextTranslationService(
              inner: RecordingTranslator(
                answer: onlineResult(text: 'WRONG — must not be reached'),
                requiresNetwork: true,
              ),
              store: store,
              connectivity: StaticConnectivityService(ConnectionStatus.online),
            );
        final TranslationResult hit = await second.translate(
          TranslationRequest(
            sourceText: 'बच्चों, कितने आम हैं?',
            sourceLanguage: 'hi-IN',
            targetLanguage: 'sat',
          ),
        );

        expect(hit.source, TranslationSource.cache);
        expect(hit.fromCache, isTrue);
        expect(hit.translatedText, "Gidra'ko, kete ul menaka?");
      },
    );
  });
}
