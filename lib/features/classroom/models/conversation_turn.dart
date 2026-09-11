import '../../setup/models/classroom_setup.dart';
import '../../../services/translation/text_translation_service.dart' show TranslationSource;
import 'classroom_state.dart';
import 'voice_pipeline_metrics.dart';

/// Who produced a line in the conversation.
enum TurnSpeaker {
  teacher(label: 'Teacher'),
  ai(label: 'AI'),
  student(label: 'Student');

  const TurnSpeaker({required this.label});

  final String label;

  static TurnSpeaker byName(String? name) {
    for (final TurnSpeaker v in values) {
      if (v.name == name) return v;
    }
    return TurnSpeaker.teacher;
  }
}

/// How far a turn got.
enum TurnStatus {
  listening,
  recognising,
  translating,
  synthesising,
  ready,
  played,
  failed;

  static TurnStatus byName(String? name) {
    for (final TurnStatus v in values) {
      if (v.name == name) return v;
    }
    return TurnStatus.failed;
  }
}

/// One line of the live conversation.
///
/// Immutable, and rebuilt with [copyWith] as the pipeline advances, so the
/// timeline can never be caught holding a half-written turn.
class ConversationTurn {
  const ConversationTurn({
    required this.id,
    required this.sessionId,
    required this.speaker,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.timestamp,
    required this.status,
    this.sourceText = '',
    this.translatedText,
    this.audioResourceId,
    this.metrics,
    this.confidence,
    this.failureMessage,
    this.translatedSpokenText,
    this.wasOffline = false,
    this.source,
  });

  factory ConversationTurn.fromJson(Map<String, dynamic> json) =>
      ConversationTurn(
        id: json['id'] as String,
        sessionId: json['sessionId'] as String,
        speaker: TurnSpeaker.byName(json['speaker'] as String?),
        sourceLanguage: json['sourceLanguage'] as String,
        targetLanguage: json['targetLanguage'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        status: TurnStatus.byName(json['status'] as String?),
        sourceText: json['sourceText'] as String? ?? '',
        translatedText: json['translatedText'] as String?,
        audioResourceId: json['audioResourceId'] as String?,
        metrics: json['metrics'] == null
            ? null
            : VoicePipelineMetrics.fromJson(
                json['metrics'] as Map<String, dynamic>,
              ),
        confidence: (json['confidence'] as num?)?.toDouble(),
        failureMessage: json['failureMessage'] as String?,
        translatedSpokenText: json['translatedSpokenText'] as String?,
        wasOffline: json['wasOffline'] as bool? ?? false,
        source: TranslationSource.byName(json['source'] as String?),
      );

  final String id;
  final String sessionId;
  final TurnSpeaker speaker;

  /// Locale ids rather than enums: a turn is a record of what happened, and it
  /// must still read correctly if the language list changes later.
  final String sourceLanguage;
  final String targetLanguage;

  final DateTime timestamp;
  final TurnStatus status;

  /// What was heard, as text.
  final String sourceText;

  /// What it became. Null until translation finishes.
  final String? translatedText;

  /// The cached clip for [translatedText], when one exists.
  final String? audioResourceId;

  /// Null until the turn reaches audio-ready.
  final VoicePipelineMetrics? metrics;

  /// 0..1 when the translator reports one. Null means the translator did not
  /// say, which is not the same as high confidence.
  final double? confidence;

  final String? failureMessage;

  /// The translation written in a script a voice can pronounce — Devanagari for
  /// the tribal languages. Stored on the turn rather than held in memory, so a
  /// session reopened tomorrow can still be read aloud and still shows the same
  /// second line under the translation.
  final String? translatedSpokenText;

  /// Whether this turn ran with no connection.
  ///
  /// Recorded per turn, not per session: a lesson that starts on the school
  /// wi-fi and finishes in the yard is partly offline, and the result screen
  /// should say so rather than rounding to one or the other.
  final bool wasOffline;

  /// Where the translated sentence actually came from, preserved so the result
  /// screen can be honest about provenance long after the session ended.
  final TranslationSource? source;

  /// Below this the UI asks the teacher to check the sentence rather than
  /// presenting it as settled.
  static const double lowConfidenceThreshold = 0.7;

  bool get isLowConfidence =>
      confidence != null && confidence! < lowConfidenceThreshold;

  bool get hasAudio => audioResourceId != null;

  ConversationTurn copyWith({
    TurnStatus? status,
    String? sourceText,
    String? translatedText,
    String? audioResourceId,
    VoicePipelineMetrics? metrics,
    double? confidence,
    String? failureMessage,
    String? translatedSpokenText,
    bool? wasOffline,
    TranslationSource? source,
  }) =>
      ConversationTurn(
        id: id,
        sessionId: sessionId,
        speaker: speaker,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        timestamp: timestamp,
        status: status ?? this.status,
        sourceText: sourceText ?? this.sourceText,
        translatedText: translatedText ?? this.translatedText,
        audioResourceId: audioResourceId ?? this.audioResourceId,
        metrics: metrics ?? this.metrics,
        confidence: confidence ?? this.confidence,
        failureMessage: failureMessage ?? this.failureMessage,
        translatedSpokenText:
            translatedSpokenText ?? this.translatedSpokenText,
        wasOffline: wasOffline ?? this.wasOffline,
        source: source ?? this.source,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'sessionId': sessionId,
        'speaker': speaker.name,
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
        'timestamp': timestamp.toIso8601String(),
        'status': status.name,
        'sourceText': sourceText,
        'translatedText': translatedText,
        'audioResourceId': audioResourceId,
        'metrics': metrics?.toJson(),
        'confidence': confidence,
        'failureMessage': failureMessage,
        'translatedSpokenText': translatedSpokenText,
        'wasOffline': wasOffline,
        'source': source?.name,
      };
}

/// The classroom facts a translator needs in order to translate for a
/// classroom rather than in a vacuum.
///
/// Assembled once from [ClassroomSetup] and the lesson, never rebuilt from
/// strings the UI happens to be showing.
class ConversationContext {
  const ConversationContext({
    required this.lessonId,
    required this.lessonTitle,
    required this.learningOutcome,
    required this.classLevel,
    required this.subject,
    required this.teachingMedium,
    required this.targetLanguage,
  });

  final String lessonId;
  final String lessonTitle;
  final String learningOutcome;
  final int classLevel;
  final ClassroomSubject subject;
  final TeachingMedium teachingMedium;
  final TargetLanguage targetLanguage;

  /// 'Hindi ↔ Santali'. The arrow points both ways because the session does.
  String get languagePair =>
      '${teachingMedium.label} ↔ ${targetLanguage.label}';

  String get headline => 'Class $classLevel  •  $languagePair';

  /// The source locale for a given direction.
  String sourceLocaleFor(ConversationDirection direction) =>
      direction == ConversationDirection.teacherToStudent
          ? teachingMedium.localeId
          : targetLanguage.localeId;

  String targetLocaleFor(ConversationDirection direction) =>
      direction == ConversationDirection.teacherToStudent
          ? targetLanguage.localeId
          : teachingMedium.localeId;

  String sourceLabelFor(ConversationDirection direction) =>
      direction == ConversationDirection.teacherToStudent
          ? teachingMedium.label
          : targetLanguage.label;

  String targetLabelFor(ConversationDirection direction) =>
      direction == ConversationDirection.teacherToStudent
          ? targetLanguage.label
          : teachingMedium.label;

  /// What a translation provider is told about the classroom. Sent as
  /// structured fields rather than glued into the sentence, so a model can use
  /// or ignore it without corrupting the text to translate.
  Map<String, dynamic> toRequestContext(ConversationDirection direction) =>
      <String, dynamic>{
        'lesson_id': lessonId,
        'lesson_title': lessonTitle,
        'learning_outcome': learningOutcome,
        'class_level': classLevel,
        'subject': subject.label,
        'speaker_role': direction == ConversationDirection.teacherToStudent
            ? 'teacher'
            : 'student',
        'register': 'primary_classroom',
      };
}
