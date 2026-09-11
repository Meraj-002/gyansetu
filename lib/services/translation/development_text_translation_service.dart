import 'text_translation_service.dart';

/// One curated pair of sentences.
class PhrasebookEntry {
  const PhrasebookEntry({
    required this.source,
    required this.target,
    this.spoken,
  });

  final String source;
  final String target;

  /// The target sentence in Devanagari, which an Indic voice can pronounce.
  /// Null where no such form has been written, in which case the audio layer
  /// reports that it cannot speak it.
  final String? spoken;
}

/// DEVELOPMENT MOCK ONLY.
/// Replace with `FastApiTextTranslationService` posting to the backend's
/// translation endpoint, or with an on-device model. Nothing above
/// [TextTranslationService] changes when it is replaced.
///
/// There is no model behind this class and it does not pretend there is:
/// [isRealModel] is false, and the session labels its measurements as a demo
/// pipeline all the way to the latency badge.
///
/// It is a phrasebook, not a translator. It answers sentences that were written
/// out in advance and refuses everything else, because a word-by-word guess at
/// Santali put in front of a class of six-year-olds is worse than an honest
/// "this sentence is not available yet".
///
/// The Santali lines below use documented Santali numerals and a small set of
/// common words. Every entry is unreviewed, and says so. No confidence score is
/// invented: a sentence either has a written-out translation here or it cannot
/// be answered at all, so [TranslationResult.confidence] is always null for
/// this provider.
class DevelopmentTextTranslationService implements TextTranslationService {
  const DevelopmentTextTranslationService();

  @override
  String get modelVersion => 'dev-phrasebook-1';

  @override
  bool get isRealModel => false;

  @override
  bool get requiresNetwork => false;

  /// Keyed by `source>target`, then by the normalised source sentence.
  static const Map<String, Map<String, PhrasebookEntry>> _book =
      <String, Map<String, PhrasebookEntry>>{
    'hi-IN>sat': <String, PhrasebookEntry>{
      'बच्चों, कितने आम हैं?': PhrasebookEntry(
        source: 'बच्चों, कितने आम हैं?',
        target: "Gidra'ko, kete ul menaka?",
        spoken: 'गिड़ाको, केते उल् मेनाका?',
      ),
      'अब हम एक से दस तक गिनेंगे।': PhrasebookEntry(
        source: 'अब हम एक से दस तक गिनेंगे।',
        target: "Nitok bo lekha: mit', bar, pe, pon, more, "
            'turui, eae, iril, are, gel.',
        spoken: 'नितोक् बो लेखा: मित्, बार, पे, पोन, मोड़े, '
            'तुरुइ, एयाए, इरिल, आरे, गेल।',
      ),
      'सब बच्चे पाँच पत्थर उठाओ।': PhrasebookEntry(
        source: 'सब बच्चे पाँच पत्थर उठाओ।',
        target: "Sanam gidra'ko, more dhiri idi'me.",
        spoken: 'सानाम गिड़ाको, मोड़े ढिरी इदिमे।',
      ),
      'बच्चों, आज हम 1 से 10 तक गिनती सीखेंगे।': PhrasebookEntry(
        source: 'बच्चों, आज हम 1 से 10 तक गिनती सीखेंगे।',
        target: "Johar gidra'ko! Ale mit' khon gel dhabic lekha bo.",
        spoken: 'जोहार गिड़ाको! आले मित् खोन गेल धाबिच् लेखा बो।',
      ),
    },
    'sat>hi-IN': <String, PhrasebookEntry>{
      "Horoko, kete aam achhe?": PhrasebookEntry(
        source: 'Horoko, kete aam achhe?',
        target: 'बच्चों, कितने आम हैं?',
        spoken: 'बच्चों, कितने आम हैं?',
      ),
      "Mit', bar, pe.": PhrasebookEntry(
        source: "Mit', bar, pe.",
        target: 'एक, दो, तीन।',
        spoken: 'एक, दो, तीन।',
      ),
      "Gidra'ko, kete ul menaka?": PhrasebookEntry(
        source: "Gidra'ko, kete ul menaka?",
        target: 'बच्चों, कितने आम हैं?',
        spoken: 'बच्चों, कितने आम हैं?',
      ),
    },
  };

  @override
  Future<bool> supportsPair(
    String sourceLanguage,
    String targetLanguage,
  ) async =>
      _book.containsKey('$sourceLanguage>$targetLanguage');

  @override
  Future<TranslationResult> translate(TranslationRequest request) async {
    final String pair =
        '${request.sourceLanguage}>${request.targetLanguage}';
    final Map<String, PhrasebookEntry>? entries = _book[pair];

    if (entries == null) {
      throw TextTranslationFailure(
        TranslationFailureReason.unsupportedPair,
        'Translation between these two languages is not available in this '
            'build yet.',
      );
    }

    final PhrasebookEntry? entry = _lookup(entries, request.sourceText);
    if (entry == null) {
      // Refusing is the point. A guess here would be presented to a class as
      // if it were the teacher's own words.
      throw const TextTranslationFailure(
        TranslationFailureReason.notConfigured,
        "This sentence isn't in the offline phrasebook yet. Connect a "
            'translation model to translate anything the teacher says.',
      );
    }

    return TranslationResult(
      translatedText: entry.target,
      sourceLanguage: request.sourceLanguage,
      targetLanguage: request.targetLanguage,
      modelVersion: modelVersion,
      confidence: null,
      spokenText: entry.spoken,
      reviewedBySpeaker: false,
      source: TranslationSource.phrasebook,
    );
  }

  /// Matches on the sentence with punctuation and case set aside, so a
  /// recogniser that drops a question mark still finds the entry.
  static PhrasebookEntry? _lookup(
    Map<String, PhrasebookEntry> entries,
    String text,
  ) {
    final String wanted = _normalise(text);
    for (final MapEntry<String, PhrasebookEntry> e in entries.entries) {
      if (_normalise(e.key) == wanted) return e.value;
    }
    return null;
  }

  static String _normalise(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[?!।,.\s]+'), ' ')
      .trim();
}
