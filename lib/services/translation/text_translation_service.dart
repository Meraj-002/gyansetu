/// A sentence to translate, with the classroom it was said in.
///
/// The context travels as structured fields rather than being glued into the
/// sentence, so a model can use it — or ignore it — without corrupting the text
/// it is asked to translate.
class TranslationRequest {
  const TranslationRequest({
    required this.sourceText,
    required this.sourceLanguage,
    required this.targetLanguage,
    this.context = const <String, dynamic>{},
    this.lessonId,
    this.classroomId,
  });

  final String sourceText;

  /// Locale ids, e.g. `hi-IN` and `sat`.
  final String sourceLanguage;
  final String targetLanguage;

  /// Lesson title, learning outcome, class, subject, speaker role. What makes
  /// a classroom translation a classroom translation rather than a dictionary
  /// lookup.
  final Map<String, dynamic> context;

  /// Optional structured ids carried alongside the context. A provider can use
  /// them or ignore them, exactly like the context map.
  final String? lessonId;
  final String? classroomId;

  /// The cache key. Includes both languages, the text and the model version,
  /// so a new model or a corrected phrasebook never serves a stale answer.
  String cacheKey(String modelVersion) =>
      '$sourceLanguage>$targetLanguage#$modelVersion#'
      '${sourceText.trim().toLowerCase()}';
}

/// Where a translated sentence actually came from.
///
/// Always stated honestly: the UI is allowed to claim the on-device phrasebook,
/// an offline model, the online backend, a cached answer — or no answer at all
/// — but never to mislabel one for the other. Distinct from
/// [TextTranslationService.isRealModel], which asks whether any real model
/// stood behind the provider; a real model reached over the network is
/// [TranslationSource.onlineBackend] with `isRealModel == true`.
enum TranslationSource {
  /// The sentence was matched against a written-out local phrasebook pack.
  /// Offline, and never claimed to be an AI model even where the phrasebook is
  /// only a development dataset.
  phrasebook,

  /// An installed on-device translation model answered. There is no real
  /// on-device NLP model in this app today, so nothing reports this yet.
  offlineModel,

  /// The online backend answered, over the network.
  onlineBackend,

  /// A previously stored answer for this exact request, replayed from the local
  /// cache without asking any provider.
  cache;

  bool get isOffline =>
      this == TranslationSource.phrasebook ||
      this == TranslationSource.offlineModel;

  bool get isOnline => this == TranslationSource.onlineBackend;

  bool get isCached => this == TranslationSource.cache;

  /// The label a teacher-facing screen shows for this source. Deliberately
  /// never the word "AI" unless a real model produced the answer.
  String get label => switch (this) {
    TranslationSource.phrasebook => 'Phrasebook',
    TranslationSource.offlineModel => 'Offline',
    TranslationSource.onlineBackend => 'Online',
    TranslationSource.cache => 'Cached',
  };

  /// The quality-controlled label the translate screen shows, aware of the
  /// record's verification state: a phrasebook answer is only ever called
  /// "Verified phrase" when a speaker actually checked it, and an online answer
  /// is never dressed up as a model it was not.
  String displayLabel({bool reviewedBySpeaker = false}) => switch (this) {
    TranslationSource.phrasebook =>
      reviewedBySpeaker ? 'Verified phrase' : 'Phrasebook',
    TranslationSource.offlineModel => 'Offline model',
    TranslationSource.onlineBackend => 'Online translation',
    TranslationSource.cache => 'Cached',
  };

  static TranslationSource? byName(String? name) {
    for (final TranslationSource source in TranslationSource.values) {
      if (source.name == name) return source;
    }
    return null;
  }
}

/// A translated sentence, and how much the translator stands behind it.
class TranslationResult {
  TranslationResult({
    required this.translatedText,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.modelVersion,
    this.originalText,
    this.timestamp,
    this.confidence,
    this.spokenText,
    this.reviewedBySpeaker = false,
    this.fromCache = false,
    this.source,
    this.engineName,
    this.engineIsRealModel = false,
    this.provider,
    this.model,
  });

  final String translatedText;
  final String sourceLanguage;
  final String targetLanguage;

  /// Which model or phrasebook produced this. Part of the cache key.
  final String modelVersion;

  /// The sentence that was translated, recorded on the result so a cache replay
  /// can still show the teacher exactly what they asked. Null where the
  /// provider did not echo it back.
  final String? originalText;

  /// When the answer was produced. Null where a provider did not say.
  final DateTime? timestamp;

  /// 0..1 where the provider reports one. Null means it did not say, which is
  /// not the same as certain. No provider ever fabricates a score the model
  /// did not give it.
  final double? confidence;

  /// The same words in a script an existing voice can pronounce — Devanagari
  /// for the tribal languages. Null when there is none, in which case the
  /// audio layer must not substitute [translatedText].
  final String? spokenText;

  /// True only when a speaker of the language has checked this. A development
  /// phrasebook entry that has not been reviewed stays false and says so.
  final bool reviewedBySpeaker;

  /// Legacy flag; prefer [source]. True exactly when [source] is cache.
  final bool fromCache;

  /// How the answer was reached. Null when a provider did not say.
  final TranslationSource? source;

  /// The backend's own `source` claim, echoed verbatim (e.g. the IndicTrans2
  /// checkpoint id). Null for the development phrasebook and unexplained
  /// answers. Used only alongside [engineIsRealModel] — it is a provenance
  /// string, never a vanity label.
  final String? engineName;

  /// The backend provider that answered, e.g. `indic_trans2`.
  final String? provider;

  /// The backend model/checkpoint id, when one was reported.
  final String? model;

  /// True only when the backend answered from a real machine-translation model.
  /// The "AI translation" badge is gated on this single flag, so a development
  /// rule table can never be dressed up as AI.
  final bool engineIsRealModel;

  bool get cached => source == TranslationSource.cache;

  /// The AI badge label. Non-null only when a real model produced the answer;
  /// the engine name is appended verbatim when the backend supplied one.
  String? get aiEngineLabel => !engineIsRealModel
      ? null
      : engineName == null
      ? 'AI translation'
      : 'AI translation • $engineName';

  TranslationResult copyWith({
    bool? fromCache,
    TranslationSource? source,
    bool? engineIsRealModel,
  }) => TranslationResult(
    translatedText: translatedText,
    sourceLanguage: sourceLanguage,
    targetLanguage: targetLanguage,
    modelVersion: modelVersion,
    originalText: originalText,
    timestamp: timestamp,
    confidence: confidence,
    spokenText: spokenText,
    reviewedBySpeaker: reviewedBySpeaker,
    fromCache: fromCache ?? this.fromCache,
    source: source ?? this.source,
    engineName: engineName,
    engineIsRealModel: engineIsRealModel ?? this.engineIsRealModel,
    provider: provider,
    model: model,
  );
}

/// Why a sentence could not be translated.
enum TranslationFailureReason {
  /// This pair is not supported at all.
  unsupportedPair,

  /// Supported, but nothing on the device covers this sentence and there is no
  /// connection.
  needsConnection,

  /// The provider was asked and could not answer.
  failed,

  /// No provider is configured in this build.
  notConfigured,

  /// A requested on-device model is not installed or could not be loaded.
  modelUnavailable,

  /// The server rejected the stored session credential.
  unauthorized,
}

class TextTranslationFailure implements Exception {
  const TextTranslationFailure(this.reason, this.message);

  final TranslationFailureReason reason;

  /// Plain language for the teacher.
  final String message;

  @override
  String toString() => 'TextTranslationFailure($reason)';
}

/// Translates free text between the teaching medium and a mother tongue.
///
/// Distinct from the lesson-scoped translator in the lessons feature: that one
/// translates a known lesson script and can cache by lesson id, while this one
/// takes whatever a teacher just said. Both sit behind an interface for the
/// same reason — the provider will change and the callers must not.
///
/// Future shape:
///
///   Flutter -> TextTranslationService -> FastAPI -> NLP model -> result
///   Flutter -> TextTranslationService -> on-device model -> result
abstract interface class TextTranslationService {
  /// Identifies the provider and its version. Part of every cache key.
  String get modelVersion;

  /// True when a real model answers this. False for a development adapter.
  bool get isRealModel;

  /// True when answering requires a network. Used by the offline orchestrator
  /// to decide whether a provider can be asked while offline: an on-device
  /// model (false) may answer with no connection, a cloud model (true) must
  /// not even be tried.
  bool get requiresNetwork;

  Future<bool> supportsPair(String sourceLanguage, String targetLanguage);

  /// Throws [TextTranslationFailure]; the orchestrator turns that into a stage
  /// failure the teacher can retry.
  Future<TranslationResult> translate(TranslationRequest request);
}
