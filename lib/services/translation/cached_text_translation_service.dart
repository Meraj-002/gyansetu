// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import '../connectivity/connectivity_service.dart';
import 'cache/translation_cache_store.dart';
import 'text_translation_service.dart';

/// Cache-first translation over any other [TextTranslationService].
///
/// A decorator rather than a base class, so the caching works the same whether
/// the provider underneath is the development phrasebook, a FastAPI endpoint or
/// an on-device model.
///
/// The cache key carries both languages, the sentence and the provider's model
/// version, so a corrected phrasebook or a new model never serves an answer the
/// old one gave.
///
/// Persistence lives in [TranslationCacheStore]: one SQLite row per entry, so a
/// 2 GB device loads only the requested sentence and never the whole cache.
class CachedTextTranslationService implements TextTranslationService {
  CachedTextTranslationService({
    required TextTranslationService inner,
    required TranslationCacheStore store,
    required ConnectivityService connectivity,
    int maxEntries = 200,
  }) : _inner = inner,
       _store = store,
       _connectivity = connectivity,
       _maxEntries = maxEntries;

  final TextTranslationService _inner;
  final TranslationCacheStore _store;
  final ConnectivityService _connectivity;

  /// Bounded on purpose: this runs on a 2 GB phone, and an unbounded cache of
  /// everything ever said in a classroom is a leak with extra steps.
  final int _maxEntries;

  @override
  String get modelVersion => _inner.modelVersion;

  @override
  bool get isRealModel => _inner.isRealModel;

  @override
  bool get requiresNetwork => _inner.requiresNetwork;

  @override
  Future<bool> supportsPair(String sourceLanguage, String targetLanguage) =>
      _inner.supportsPair(sourceLanguage, targetLanguage);

  /// What is already on the device for this exact request, if anything.
  Future<TranslationResult?> cached(TranslationRequest request) async {
    final CachedTranslationEntry? entry = await _store.read(
      request.cacheKey(modelVersion),
    );
    if (entry == null || entry.translatedText.isEmpty) return null;
    return TranslationResult(
      translatedText: entry.translatedText,
      sourceLanguage: request.sourceLanguage,
      targetLanguage: request.targetLanguage,
      modelVersion: entry.modelVersion.isEmpty
          ? modelVersion
          : entry.modelVersion,
      originalText: request.sourceText,
      timestamp: entry.savedAt,
      confidence: entry.confidence,
      spokenText: entry.spokenText,
      reviewedBySpeaker: entry.reviewedBySpeaker,
      fromCache: true,
      source: TranslationSource.cache,
      provider: entry.provider,
      model: entry.model,
      engineName: entry.engineName,
      engineIsRealModel: entry.engineIsRealModel,
    );
  }

  @override
  Future<TranslationResult> translate(TranslationRequest request) async {
    final TranslationResult? hit = await cached(request);
    if (hit != null) return hit;

    // Only a provider that lives on the network can be blocked by being
    // offline. Saying so for an on-device provider would be the opposite lie.
    if (_inner.requiresNetwork &&
        _connectivity.status == ConnectionStatus.offline) {
      throw const TextTranslationFailure(
        TranslationFailureReason.needsConnection,
        'Connection unavailable, and this sentence is not saved on this '
        'device yet.',
      );
    }

    final TranslationResult result = await _inner.translate(request);
    await _store.write(
      CachedTranslationEntry(
        key: request.cacheKey(modelVersion),
        translatedText: result.translatedText,
        modelVersion: result.modelVersion,
        spokenText: result.spokenText,
        confidence: result.confidence,
        reviewedBySpeaker: result.reviewedBySpeaker,
        sourceName: result.source?.name,
        provider: result.provider,
        model: result.model,
        engineName: result.engineName,
        engineIsRealModel: result.engineIsRealModel,
        savedAt: result.timestamp ?? DateTime.now(),
      ),
    );
    await _store.trim(_maxEntries);
    return result;
  }

  /// Empties the cache, e.g. when the underlying provider was invalidated.
  Future<void> clear() => _store.clear();
}
