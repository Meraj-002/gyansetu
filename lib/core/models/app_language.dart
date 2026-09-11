/// Canonical first-class languages for speech, translation and voice.
///
/// One place that owns how a language is named and coded, so "hindi", "SAT",
/// "santhali" and "sat" never sprawl across unrelated files with subtly
/// different spellings. The classroom's own [TeachingMedium] and [TargetLanguage]
/// stay as the setup-screen vocabulary; they map onto these codes, and
/// everything that actually talks to a model or a voice uses an [AppLanguage]
/// code.
///
/// Codes follow BCP-47, the same shape the platform recogniser and TTS engines
/// already speak (`hi-IN` = Hindi in India, `sat` = Santali, ISO 639-3). New
/// languages (Mundari `unr`, Ho `hoc`, Bengali, English, Odia) extend this enum
/// and are picked up everywhere that switches on it.
enum AppLanguage {
  hindi(
    code: 'hi-IN',
    iso639: 'hi',
    label: 'Hindi',
    nativeName: 'हिन्दी',
    script: 'Devanagari',
    capabilities: LanguageCapabilities(
      hasKnownSpeechRecognition: true,
      hasKnownTtsVoice: true,
      offlinePhrasebookPairs: <String>{'hi-IN>sat', 'sat>hi-IN'},
    ),
  ),
  santali(
    code: 'sat',
    iso639: 'sat',
    label: 'Santali',
    nativeName: 'संताली',
    script: 'Ol Chiki',
    capabilities: LanguageCapabilities(
      // No recogniser or TTS voice for Santali exists on any mainstream device
      // engine. Load-bearing facts from the world, not an enumeration failure:
      // the audio layer must never read Santali with a Hindi voice.
      hasKnownSpeechRecognition: false,
      hasKnownTtsVoice: false,
      offlinePhrasebookPairs: <String>{'hi-IN>sat', 'sat>hi-IN'},
    ),
  ),
  english(
    code: 'en-IN',
    iso639: 'en',
    label: 'English',
    nativeName: 'English',
    script: 'Latin',
    capabilities: LanguageCapabilities(
      hasKnownSpeechRecognition: true,
      hasKnownTtsVoice: true,
    ),
  ),
  bengali(
    code: 'bn-IN',
    iso639: 'bn',
    label: 'Bengali',
    nativeName: 'বাংলা',
    script: 'Bengali',
    capabilities: LanguageCapabilities(
      hasKnownSpeechRecognition: true,
      hasKnownTtsVoice: true,
    ),
  ),
  mundari(
    code: 'unr',
    iso639: 'unr',
    label: 'Mundari',
    nativeName: 'मुंडारी',
    script: 'Devanagari (Bani Hisir)',
    capabilities: LanguageCapabilities(
      hasKnownSpeechRecognition: false,
      hasKnownTtsVoice: false,
    ),
  ),
  ho(
    code: 'hoc',
    iso639: 'hoc',
    label: 'Ho',
    nativeName: 'हो',
    script: 'Devanagari (Warang Citi)',
    capabilities: LanguageCapabilities(
      hasKnownSpeechRecognition: false,
      hasKnownTtsVoice: false,
    ),
  );

  const AppLanguage({
    required this.code,
    required this.iso639,
    required this.label,
    required this.nativeName,
    required this.script,
    required this.capabilities,
  });

  /// The canonical BCP-47 locale id used to ask for a voice or a transcript.
  ///
  /// Always preferred over a caller's own spelling: pass the code around, not a
  /// hand-typed `'sat'`. Lower-case here so [byCode] matches the case a stored
  /// record or engine may hand back.
  final String code;

  /// The base ISO-639 language subtag, for a recogniser or engine that only
  /// understands the language and not the region/script.
  final String iso639;

  final String label;

  /// The language's name in its own script, for teacher-facing choosers.
  final String nativeName;

  /// Conventional name of the script, for display and provenance notes.
  final String script;

  /// What is known about this language before a single service is asked:
  /// whether any recogniser/voice is known to exist and which offline
  /// translation pairs have a phrasebook pack. Device truth is still gathered
  /// from the real services at runtime — this is the documented starting point,
  /// not a substitution.
  final LanguageCapabilities capabilities;

  /// Whether the offline phrasebook covers this exact pair (when it is
  /// installed). Honest against the documented packs; the pack itself must also
  /// be on disk for [supportsPair] to answer true.
  bool knownOfflinePair(String sourceCode, String targetCode) =>
      capabilities.offlinePhrasebookPairs
          .contains('$sourceCode>$targetCode');

  AppLanguage? byCode(String? value) {
    if (value == null) return null;
    return byCodeStatic(value);
  }

  static AppLanguage? byCodeStatic(String value) {
    final String wanted = value.trim().toLowerCase().split('_').join('-');
    if (wanted.isEmpty) return null;
    for (final AppLanguage language in AppLanguage.values) {
      if (language.code.toLowerCase() == wanted) return language;
      if (language.iso639 == wanted) return language;
    }
    return null;
  }

  /// Resolves any of the spellings that appear in real records or arguments —
  /// `'sat'`, `'SAT'`, `'santali'`, `'santhali'`, `'sat-Olck'` — to the enum,
  /// or null when nothing matches. Loose on purpose so stored setup rows that
  /// came from an older build still resolve instead of being rejected.
  static AppLanguage? fromAny(String? value) {
    if (value == null) return null;
    AppLanguage? found = byCodeStatic(value);
    if (found != null) return found;
    final String folded = value.trim().toLowerCase();
    final String language = folded.split('-').first;
    for (final AppLanguage candidate in AppLanguage.values) {
      if (language == candidate.iso639) return candidate;
      if (folded == candidate.label.toLowerCase()) return candidate;
      if (folded == candidate.nativeName.toLowerCase()) return candidate;
      if (folded == candidate.name.toLowerCase()) return candidate;
      if (folded == 'santhali' && candidate == AppLanguage.santali) {
        return candidate;
      }
    }
    return null;
  }
}

/// What is known about a language's capabilities from the world, not queried at
/// runtime.
///
/// These are load-bearing and documented deliberately: Santali, Mundari and Ho
/// have no recogniser and no TTS voice on any mainstream device engine, and
/// claiming either exists would fake a capability. The runtime services still
/// ask the real engine per pair — [LanguageCapabilities] is the starting point
/// a caller trusts before spending a platform call.
class LanguageCapabilities {
  const LanguageCapabilities({
    required this.hasKnownSpeechRecognition,
    required this.hasKnownTtsVoice,
    this.offlinePhrasebookPairs = const <String>{},
  });

  /// Whether any speech recogniser anywhere is known to transcribe this
  /// language. False for the tribal languages, where a microphone must never
  /// be opened for a language nothing can recognise.
  final bool hasKnownSpeechRecognition;

  /// Whether any TTS voice anywhere is known to read this language. False for
  /// the tribal languages, where a Hindi voice reading Latin-script words is
  /// not the mother tongue and must not be presented as it.
  final bool hasKnownTtsVoice;

  /// Locale-id pairs (`source>target`) with an authored offline phrasebook
  /// pack. The pack still has to be installed for [AppLanguage.knownOfflinePair]
  /// to mean anything.
  final Set<String> offlinePhrasebookPairs;
}