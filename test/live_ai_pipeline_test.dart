import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/core/config/api_config.dart';
import 'package:gyan_setu_ai/core/utils/result.dart';
import 'package:gyan_setu_ai/services/api/api_endpoints.dart';
import 'package:gyan_setu_ai/services/api/http_api_client.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';
import 'package:gyan_setu_ai/services/translation/fastapi_text_translation_service.dart';
import 'package:gyan_setu_ai/services/translation/offline_first_translation_service.dart';
import 'package:gyan_setu_ai/services/translation/offline_phrasebook_translation_service.dart';
import 'package:gyan_setu_ai/services/translation/text_translation_service.dart';

import 'translation/translation_test_doubles.dart';

/// End-to-end verification of the AI language pipeline against the real
/// FastAPI dev backend over HttpApiClient — the same transport the app uses —
/// through an in-memory device.
///
/// Run it with uvicorn up on the base URL in [ApiConfig]:
///
///     flutter test --dart-define=LIVE_BACKEND=true test/live_ai_pipeline_test.dart
///
/// A fresh teacher account is registered per run, so repeated runs never
/// collide. Nothing here invents answers: every assertion is about what the
/// live server (or the honest offline orchestrator) actually reported.
const bool live = bool.fromEnvironment('LIVE_BACKEND');

const String _authored = 'बच्चों, कितने आम हैं?';

int _accountSeq = 0;

String _uniqueMobile() {
  final String micro = (DateTime.now().microsecondsSinceEpoch % 1000000)
      .toString()
      .padLeft(6, '0');
  final String count = ((_accountSeq++) % 100).toString().padLeft(2, '0');
  return '7ai5$micro$count';
}

void main() {
  if (!live) {
    test(
      'live AI pipeline is skipped unless LIVE_BACKEND is set',
      () {},
      skip: 'not a live run',
    );
    return;
  }

  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

  late String token;

  setUp(() async {
    final HttpApiClient registrar = HttpApiClient(baseUrl: ApiConfig.baseUrl);
    final Result<Map<String, dynamic>> registered = await registrar.post(
      ApiEndpoints.register,
      body: <String, dynamic>{
        'displayName': 'AI Pipeline E2E',
        'mobile': _uniqueMobile(),
        'password': '1234',
      },
    );
    expect(
      registered,
      isA<Ok<Map<String, dynamic>>>(),
      reason: 'live registration failed',
    );
    token =
        (registered as Ok<Map<String, dynamic>>).value['accessToken'] as String;
    expect(token, isNotEmpty);
  });

  test(
    'online translation answers an authored sentence from the live model',
    () async {
      final FastApiTextTranslationService translator =
          FastApiTextTranslationService(
            api: HttpApiClient(
              baseUrl: ApiConfig.baseUrl,
              accessTokenProvider: () async => token,
            ),
          );

      final TranslationResult result = await translator.translate(
        TranslationRequest(
          sourceText: _authored,
          sourceLanguage: 'hi-IN',
          targetLanguage: 'sat',
          context: const <String, dynamic>{'lessonId': 'c1-num-counting-1-10'},
        ),
      );

      expect(result.translatedText, isNotEmpty);
      expect(result.translatedText.trim(), isNot(_authored.trim()));
      expect(result.source, TranslationSource.onlineBackend);
      expect(result.confidence, isNull, reason: 'no invented score');
      expect(result.engineIsRealModel, isTrue);
      expect(result.engineName, contains('indictrans2'));
      expect(translator.requiresNetwork, isTrue);
    },
  );

  test(
    'online translation handles the reverse pair through the live server',
    () async {
      final FastApiTextTranslationService translator =
          FastApiTextTranslationService(
            api: HttpApiClient(
              baseUrl: ApiConfig.baseUrl,
              accessTokenProvider: () async => token,
            ),
          );

      final TranslationResult result = await translator.translate(
        TranslationRequest(
          sourceText: 'Mit\n, bar, pe.',
          sourceLanguage: 'sat',
          targetLanguage: 'hi-IN',
        ),
      );

      expect(result.translatedText, isNotEmpty);
      expect(result.source, TranslationSource.onlineBackend);
      expect(result.engineIsRealModel, isTrue);
    },
  );

  test(
    'the real model answers a sentence outside the authored phrasebook',
    () async {
      final FastApiTextTranslationService translator =
          FastApiTextTranslationService(
            api: HttpApiClient(
              baseUrl: ApiConfig.baseUrl,
              accessTokenProvider: () async => token,
            ),
          );

      final TranslationResult result = await translator.translate(
        const TranslationRequest(
          sourceText: 'कल की छुट्टी के बारे में बात करें।',
          sourceLanguage: 'hi-IN',
          targetLanguage: 'sat',
        ),
      );
      expect(result.translatedText, isNotEmpty);
      expect(result.engineIsRealModel, isTrue);
    },
  );

  test('offline with no phrasebook refuses with the exact message', () async {
    final OfflineFirstTranslationService orchestrator =
        OfflineFirstTranslationService(
          offline: OfflinePhrasebookTranslationService(
            source: FixedPackSource(), // nothing installed on this device
            io: MemoryLocalContentIo(),
          ),
          online: FastApiTextTranslationService(
            api: HttpApiClient(
              baseUrl: ApiConfig.baseUrl,
              accessTokenProvider: () async => token,
            ),
          ),
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
              'Offline translation is unavailable for this language.',
            ),
      ),
    );
  });

  test(
    'online fallback answers through the live server and labels it online',
    () async {
      final OfflineFirstTranslationService orchestrator =
          OfflineFirstTranslationService(
            offline: OfflinePhrasebookTranslationService(
              source: FixedPackSource(), // nothing installed on this device
              io: MemoryLocalContentIo(),
            ),
            online: FastApiTextTranslationService(
              api: HttpApiClient(
                baseUrl: ApiConfig.baseUrl,
                accessTokenProvider: () async => token,
              ),
            ),
            connectivity: StaticConnectivityService(ConnectionStatus.online),
          );

      final TranslationResult result = await orchestrator.translate(
        TranslationRequest(
          sourceText: _authored,
          sourceLanguage: 'hi-IN',
          targetLanguage: 'sat',
        ),
      );

      expect(result.translatedText, isNotEmpty);
      expect(result.source, TranslationSource.onlineBackend);
      expect(result.engineIsRealModel, isTrue);
    },
  );

  test('without authentication the server refuses the translation', () async {
    final FastApiTextTranslationService translator =
        FastApiTextTranslationService(
          api: HttpApiClient(baseUrl: ApiConfig.baseUrl), // no token
        );

    await expectLater(
      translator.translate(
        TranslationRequest(
          sourceText: _authored,
          sourceLanguage: 'hi-IN',
          targetLanguage: 'sat',
        ),
      ),
      throwsA(isA<TextTranslationFailure>()),
    );
  });
}
