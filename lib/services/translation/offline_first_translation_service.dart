// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import '../connectivity/connectivity_service.dart';
import 'text_translation_service.dart';

/// Offline-first orchestration of the translation providers — the decision
/// engine. One place owns the priority, so every consumer answers the same way:
///
///  1. Ask the on-device phrasebook first.
///  2. If it covers the sentence, answer — no connection was needed or used.
///  3. If not, ask the installed offline model (when one exists).
///  4. If neither covers the sentence and the device is offline, refuse with
///     the exact "Offline translation is unavailable for this language."
///     message; a guessed mother-tongue sentence must never reach the class.
///  5. If neither covers the sentence and the device is online, fall back to
///     the online provider and report the answer as online.
///
/// A local cache sits above this orchestration (see the cached decorator), so
/// the full priority is cache → phrasebook → offline model → online → refused.
///
/// Every result carries an honest [TranslationSource]. A development phrasebook
/// is a real offline provider (it really does run on the device); it is
/// [TextTranslationService.isRealModel] that stays false for it.
class OfflineFirstTranslationService implements TextTranslationService {
  OfflineFirstTranslationService({
    required TextTranslationService offline,
    TextTranslationService? offlineModel,
    required TextTranslationService online,
    required ConnectivityService connectivity,
    bool? forceOfflineOnly,
  })  : _offline = offline,
        _offlineModel = offlineModel,
        _online = online,
        _connectivity = connectivity,
        _forceOfflineOnly = forceOfflineOnly ?? false;

  final TextTranslationService _offline;

  /// The installed on-device model, when one exists. Consulted between the
  /// phrasebook and the network; a null slot simply falls through.
  final TextTranslationService? _offlineModel;

  final TextTranslationService _online;
  final ConnectivityService _connectivity;

  /// Test hook: pretend the device is offline regardless of the connectivity
  /// service, and verify that no network call happens.
  final bool _forceOfflineOnly;

  bool get isOfflineOnly => _forceOfflineOnly ||
      _connectivity.status == ConnectionStatus.offline;

  /// This orchestrator can answer some sentences with no connection, so it does
  /// not require one. Consumers still respect the result's [TranslationSource].
  @override
  bool get requiresNetwork => false;

  @override
  bool get isRealModel =>
      _offline.isRealModel ||
      (_offlineModel?.isRealModel ?? false) ||
      _online.isRealModel;

  @override
  String get modelVersion {
    // The version that actually answered depends on the sentence; a single
    // value is needed for the cache key, so prefer the online model's version
    // (the newer source of truth) while noting the offline providers.
    final String model = _offlineModel?.modelVersion ?? 'none';
    return 'offline-first(${_online.modelVersion}/$model/${_offline.modelVersion})';
  }

  @override
  Future<bool> supportsPair(String sourceLanguage, String targetLanguage) async {
    if (await _offline.supportsPair(sourceLanguage, targetLanguage)) return true;
    final TextTranslationService? model = _offlineModel;
    if (model != null && await model.supportsPair(sourceLanguage, targetLanguage)) {
      return true;
    }
    return await _online.supportsPair(sourceLanguage, targetLanguage);
  }

  @override
  Future<TranslationResult> translate(TranslationRequest request) async {
    // 1. The offline phrasebook — the only provider guaranteed to be local.
    try {
      return await _offline.translate(request);
    } on TextTranslationFailure catch (offlineFailure) {
      // A pair that no provider supports is refused as unsupported, period.
      if (offlineFailure.reason == TranslationFailureReason.unsupportedPair) {
        rethrow;
      }

      // 2. An installed offline model, if one is present.
      final TextTranslationService? model = _offlineModel;
      if (model != null) {
        try {
          return await model.translate(request);
        } on TextTranslationFailure catch (modelFailure) {
          if (modelFailure.reason == TranslationFailureReason.unsupportedPair) {
            rethrow;
          }
          // A model that is missing or failed is not an answer; fall through.
        }
      }

      // 3. Explicitly offline: no network call, honest refusal.
      if (isOfflineOnly) {
        throw const TextTranslationFailure(
          TranslationFailureReason.needsConnection,
          'Offline translation is unavailable for this language.',
        );
      }

      // 4. Online fallback, and whatever it says is what happened.
      return await _online.translate(request);
    }
  }
}