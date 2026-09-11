import '../features/setup/models/classroom_setup.dart';
import 'lesson_plan.dart';

/// A teacher script rendered in the classroom's mother tongue.
///
/// Translation is per lesson *and* per language, so one lesson can hold a
/// Santali, a Mundari and a Ho translation at once without duplicating the
/// lesson itself.
class LessonTranslation {
  const LessonTranslation({
    required this.lessonId,
    required this.sourceMedium,
    required this.targetLanguage,
    required this.text,
    required this.createdAt,
    this.spokenText,
    this.provenance = ContentProvenance.authored,
    this.reviewedBySpeaker = false,
    this.version = 1,
  });

  factory LessonTranslation.fromJson(Map<String, dynamic> json) =>
      LessonTranslation(
        lessonId: json['lessonId'] as String,
        sourceMedium: TeachingMedium.byName(json['sourceMedium'] as String?) ??
            TeachingMedium.hindi,
        targetLanguage:
            TargetLanguage.byName(json['targetLanguage'] as String?) ??
                TargetLanguage.santali,
        text: json['text'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        spokenText: json['spokenText'] as String?,
        provenance: ContentProvenance.byName(json['provenance'] as String?),
        reviewedBySpeaker: json['reviewedBySpeaker'] as bool? ?? false,
        version: json['version'] as int? ?? 1,
      );

  final String lessonId;
  final TeachingMedium sourceMedium;
  final TargetLanguage targetLanguage;

  /// What the teacher reads on screen.
  final String text;

  /// The same words written so an Indic speech engine can pronounce them —
  /// Devanagari for Santali, Mundari and Ho, all of which are also written in
  /// Devanagari in Jharkhand schools.
  ///
  /// Null when no such form exists, in which case the audio layer must not
  /// substitute [text]: a Latin-script string handed to a Hindi voice is read
  /// as English and comes out as nonsense.
  final String? spokenText;

  final ContentProvenance provenance;

  /// True only when a speaker of the language has checked this translation.
  /// The UI says so, because an unreviewed machine translation in a classroom
  /// is a claim the app should not make silently.
  final bool reviewedBySpeaker;

  final int version;
  final DateTime createdAt;

  /// The key this translation is cached under.
  String get cacheKey => cacheKeyFor(lessonId, targetLanguage);

  static String cacheKeyFor(String lessonId, TargetLanguage language) =>
      '$lessonId#${language.localeId}';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'lessonId': lessonId,
        'sourceMedium': sourceMedium.name,
        'targetLanguage': targetLanguage.name,
        'text': text,
        'spokenText': spokenText,
        'provenance': provenance.name,
        'reviewedBySpeaker': reviewedBySpeaker,
        'version': version,
        'createdAt': createdAt.toIso8601String(),
      };
}
