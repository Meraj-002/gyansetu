// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import '../../core/utils/app_logger.dart';
import '../ai/ai_model_manager.dart';
import 'text_translation_service.dart';

/// The downloadable pack id an on-device translation model, when one exists,
/// is served from. No such pack is advertised today.
const String offlineModelPackId = 'translation-model-hindi-santali';

/// [TextTranslationService] backed by an [AiModelManager]: kind-of-offline, in
/// the decision-engine slot between the phrasebook and the network.
///
/// Honest by construction: there is no real on-device NLP model in this build,
/// so [supportsPair] stays false while no verified model pack is installed,
/// [translate] refuses with [TranslationFailureReason.modelUnavailable], and
/// the offline-first orchestrator falls through to the network exactly as it
/// would for any uncovered sentence. The day a real model pack exists, this
/// adapter swaps `_manager.translate` in and nothing above it changes.
class OfflineModelTranslationService implements TextTranslationService {
  OfflineModelTranslationService({
    required AiModelManager manager,
    this.packId = offlineModelPackId,
  }) : _manager = manager;

  final AiModelManager _manager;
  final String packId;

  @override
  String get modelVersion => 'on-device-model-0';

  @override
  bool get isRealModel => false;

  @override
  bool get requiresNetwork => false;

  /// Whether the verified model pack is on disk. No pack is advertised in this
  /// build, so this is false in practice — which is the honest answer.
  Future<bool> isInstalled() async {
    try {
      return await _manager.isModelAvailable(packId);
    } on Object catch (error) {
      AppLogger.error('offline model availability check failed', error: error);
      return false;
    }
  }

  @override
  Future<bool> supportsPair(String sourceLanguage, String targetLanguage) async {
    if (!_pairIsKnown(sourceLanguage, targetLanguage)) return false;
    return await isInstalled();
  }

  bool _pairIsKnown(String sourceLanguage, String targetLanguage) =>
      const <String>{'hi-IN>sat', 'sat>hi-IN'}
          .contains('$sourceLanguage>$targetLanguage');

  @override
  Future<TranslationResult> translate(TranslationRequest request) async {
    if (!_pairIsKnown(request.sourceLanguage, request.targetLanguage)) {
      throw TextTranslationFailure(
        TranslationFailureReason.unsupportedPair,
        'Translation between these two languages is not available on-device.',
      );
    }
    if (!await isInstalled()) {
      throw const TextTranslationFailure(
        TranslationFailureReason.modelUnavailable,
        'No offline translation model is installed on this device yet.',
      );
    }
    // A real on-device translation engine is not implemented in this build, and
    // no translation is invented to stand in for it.
    throw const TextTranslationFailure(
      TranslationFailureReason.modelUnavailable,
      'An on-device translation engine is not implemented in this build yet.',
    );
  }
}