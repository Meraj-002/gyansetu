// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import '../../core/errors/app_exception.dart';
import '../../core/utils/result.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import 'text_translation_service.dart';

/// The online half of the offline-first orchestrator: POSTs to the backend's
/// `/api/v1/translation/translate` endpoint.
///
/// This adapter is not a model. It reports [modelVersion] as whatever the
/// backend answered, and [isRealModel] is derived from the backend's own
/// `source` claim so the app never labels a development phrasebook as AI.
/// When a real model is served, every caller above this class changes nothing.
class FastApiTextTranslationService implements TextTranslationService {
  const FastApiTextTranslationService({required ApiClient api}) : _api = api;

  final ApiClient _api;

  @override
  String get modelVersion =>
      // The live version is returned per-response; this placeholder keeps the
      // offline-first cache key stable between device runs.
      'api-translate-v1';

  @override
  bool get isRealModel => false;

  @override
  bool get requiresNetwork => true;

  /// True for the supported live pair regardless of what is cached locally.
  ///
  /// This intentionally answers without any storage checks — the network is the
  /// source of truth. The orchestrator decides whether the network may be used.
  static const Set<String> _supportedPairs = <String>{'hin>sat', 'sat>hin'};

  @override
  Future<bool> supportsPair(
    String sourceLanguage,
    String targetLanguage,
  ) async => _supportedPairs.contains(
    '${_backendLanguage(sourceLanguage)}>${_backendLanguage(targetLanguage)}',
  );

  @override
  Future<TranslationResult> translate(TranslationRequest request) async {
    final Result<Map<String, dynamic>> result = await _api.post(
      ApiEndpoints.translationTranslate,
      body: <String, dynamic>{
        'text': request.sourceText,
        'source_language': _backendLanguage(request.sourceLanguage),
        'target_language': _backendLanguage(request.targetLanguage),
      },
    );

    return switch (result) {
      Ok<Map<String, dynamic>>(:final Map<String, dynamic> value) => _decode(
        value,
        request,
      ),
      Err<Map<String, dynamic>>(:final AppException error) => throw _failure(
        error,
      ),
    };
  }

  /// The app keeps BCP-47 locale ids for speech and records; the backend's
  /// translation contract uses the IndicTrans2-friendly short codes.
  static String _backendLanguage(String value) {
    final String folded = value.trim().toLowerCase().replaceAll('_', '-');
    return switch (folded) {
      'hi' || 'hi-in' || 'hindi' || 'hin' || 'hin-deva' => 'hin',
      'sat' || 'santali' || 'santhali' || 'sat-olck' => 'sat',
      _ => value,
    };
  }

  TranslationResult _decode(
    Map<String, dynamic> json,
    TranslationRequest request,
  ) {
    final String? translated = json['translatedText'] as String?;
    final String? spoken = json['spokenText'] as String?;
    if (translated == null || translated.isEmpty) {
      throw const TextTranslationFailure(
        TranslationFailureReason.failed,
        'The translation server returned an empty answer.',
      );
    }
    final String? source = json['source'] as String?;
    final String? provider = json['provider'] as String?;
    final String? model = json['model'] as String?;
    return TranslationResult(
      translatedText: translated,
      originalText: json['sourceText'] as String? ?? request.sourceText,
      sourceLanguage:
          json['sourceLanguage'] as String? ?? request.sourceLanguage,
      targetLanguage:
          json['targetLanguage'] as String? ?? request.targetLanguage,
      modelVersion: json['modelVersion'] as String? ?? modelVersion,
      confidence: (json['confidence'] as num?)?.toDouble(),
      spokenText: spoken,
      reviewedBySpeaker:
          json['reviewedBySpeaker'] as bool? ??
          json['reviewed'] as bool? ??
          false,
      source: TranslationSource.onlineBackend,
      // The backend's model id is the useful provenance shown beside a real
      // answer; retain its provider and source claims separately as well.
      engineName: model ?? source,
      engineIsRealModel: json['isRealModel'] as bool? ?? false,
      provider: provider,
      model: model,
    );
  }

  /// Turns a transport/server failure into the honest reason for the
  /// orchestrator, without ever inventing an answer.
  TextTranslationFailure _failure(AppException error) {
    if (error is NetworkException) {
      return const TextTranslationFailure(
        TranslationFailureReason.needsConnection,
        'No internet connection. Check your network and try again.',
      );
    }
    if (error is UnauthorizedException) {
      return const TextTranslationFailure(
        TranslationFailureReason.unauthorized,
        'Your session has expired. Please sign in again.',
      );
    }
    if (error is ServerException && error.statusCode == 404) {
      return const TextTranslationFailure(
        TranslationFailureReason.notConfigured,
        'The translation server has no rule for this sentence yet.',
      );
    }
    if (error is ServerException && error.statusCode == 422) {
      return TextTranslationFailure(
        TranslationFailureReason.failed,
        error.message == 'The server rejected the request.'
            ? 'Please check the sentence and selected languages.'
            : error.message,
      );
    }
    if (error is ServerException &&
        (error.statusCode == 500 || error.statusCode == 503)) {
      return TextTranslationFailure(
        TranslationFailureReason.modelUnavailable,
        error.message == 'The server rejected the request.'
            ? 'The translation model is unavailable right now. Please try again.'
            : error.message,
      );
    }
    return TextTranslationFailure(
      TranslationFailureReason.failed,
      error.message,
    );
  }
}
