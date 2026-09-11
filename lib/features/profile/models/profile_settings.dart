import 'dart:convert';

/// App-visible text size, offered as a picker in Accessibility.
enum TextSize {
  small(label: 'Small', scale: 0.9),
  defaultSize(label: 'Default', scale: 1.0),
  large(label: 'Large', scale: 1.2),
  extraLarge(label: 'Extra Large', scale: 1.4);

  const TextSize({required this.label, required this.scale});

  final String label;

  /// The `MediaQuery.textScaler` factor applied app-wide while selected.
  final double scale;

  static TextSize byName(String? name) {
    for (final TextSize v in values) {
      if (v.name == name) return v;
    }
    return TextSize.defaultSize;
  }
}

/// How fast synthesised audio reads the sentence.
enum VoiceSpeed {
  slow(label: 'Slow'),
  normal(label: 'Normal'),
  fast(label: 'Fast');

  const VoiceSpeed({required this.label});

  final String label;

  static VoiceSpeed byName(String? name) {
    for (final VoiceSpeed v in values) {
      if (v.name == name) return v;
    }
    return VoiceSpeed.normal;
  }
}

/// How the app should say the translation aloud.
enum PronunciationPreference {
  standard(label: 'Standard'),
  clear(label: 'Clear & Slow');

  const PronunciationPreference({required this.label});

  final String label;

  static PronunciationPreference byName(String? name) {
    for (final PronunciationPreference v in values) {
      if (v.name == name) return v;
    }
    return PronunciationPreference.standard;
  }
}

/// Accessibility and audio preferences for the current teacher, persisted on
/// the device so nothing here needs a network or a backend.
class ProfileSettings {
  const ProfileSettings({
    this.textSize = TextSize.defaultSize,
    this.highContrast = false,
    this.highContrastSet = false,
    this.audioAssistance = true,
    this.audioAssistanceSet = false,
    this.voiceSpeed = VoiceSpeed.normal,
    this.voiceSpeedSet = false,
    this.pronunciation = PronunciationPreference.standard,
    this.pronunciationSet = false,
  });

  final TextSize textSize;
  final bool highContrast;

  /// Whether [highContrast] was ever chosen. A stored `false` carries no
  /// information about a preference, so the toggle only flips once the teacher
  /// picks a side.
  final bool highContrastSet;

  /// Read teaching material aloud instead of requiring silent reading.
  final bool audioAssistance;
  final bool audioAssistanceSet;

  final VoiceSpeed voiceSpeed;
  final bool voiceSpeedSet;

  final PronunciationPreference pronunciation;
  final bool pronunciationSet;

  /// The effective text-scale factor, applied to the whole app.
  double get textScaleFactor => textSize.scale;

  ProfileSettings copyWith({
    TextSize? textSize,
    bool? highContrast,
    bool? audioAssistance,
    VoiceSpeed? voiceSpeed,
    PronunciationPreference? pronunciation,
  }) {
    return ProfileSettings(
      textSize: textSize ?? this.textSize,
      highContrast: highContrast ?? this.highContrast,
      highContrastSet: highContrastSet || highContrast != null,
      audioAssistance: audioAssistance ?? this.audioAssistance,
      audioAssistanceSet: audioAssistanceSet || audioAssistance != null,
      voiceSpeed: voiceSpeed ?? this.voiceSpeed,
      voiceSpeedSet: voiceSpeedSet || voiceSpeed != null,
      pronunciation: pronunciation ?? this.pronunciation,
      pronunciationSet: pronunciationSet || pronunciation != null,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'textSize': textSize.name,
        'highContrast': highContrast,
        'highContrastSet': highContrastSet,
        'audioAssistance': audioAssistance,
        'audioAssistanceSet': audioAssistanceSet,
        'voiceSpeed': voiceSpeed.name,
        'voiceSpeedSet': voiceSpeedSet,
        'pronunciation': pronunciation.name,
        'pronunciationSet': pronunciationSet,
      };

  String encode() => jsonEncode(toJson());

  static ProfileSettings tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return const ProfileSettings();
    try {
      final Map<String, dynamic> json =
          jsonDecode(raw) as Map<String, dynamic>;
      return ProfileSettings(
        textSize: TextSize.byName(json['textSize'] as String?),
        highContrast: json['highContrast'] as bool? ?? false,
        highContrastSet: json['highContrastSet'] as bool? ?? false,
        audioAssistance: json['audioAssistance'] as bool? ?? true,
        audioAssistanceSet: json['audioAssistanceSet'] as bool? ?? false,
        voiceSpeed: VoiceSpeed.byName(json['voiceSpeed'] as String?),
        pronunciation:
            PronunciationPreference.byName(json['pronunciation'] as String?),
      );
    } on FormatException {
      return const ProfileSettings();
    } on TypeError {
      return const ProfileSettings();
    }
  }
}