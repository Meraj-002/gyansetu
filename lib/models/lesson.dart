import 'dart:convert';

import '../features/setup/models/classroom_setup.dart';

/// Whether a lesson's content is present on this device.
enum DownloadState {
  /// Not on the device. Opening it needs a first download.
  notDownloaded,

  /// A download is running.
  downloading,

  /// Present and usable with no connection.
  downloaded,

  /// The last attempt failed; it can be retried.
  failed;

  String get label => switch (this) {
        DownloadState.notDownloaded => 'Not downloaded',
        DownloadState.downloading => 'Downloading…',
        DownloadState.downloaded => 'Downloaded',
        DownloadState.failed => 'Download failed',
      };
}

/// A teachable lesson.
///
/// One definition shared by the library, the dashboard and lesson detail, so
/// the same lesson can never disagree with itself across screens.
class Lesson {
  const Lesson({
    required this.id,
    required this.title,
    required this.description,
    required this.subject,
    required this.classNumber,
    required this.learningOutcome,
    required this.durationMinutes,
    required this.lessonOrder,
    required this.createdAt,
    required this.updatedAt,
    this.thumbnailAsset,
    this.resourceIds = const <String>[],
    this.concepts = const <String>[],
    this.audioResourceId,
    this.worksheetResourceId,
    this.flashcardResourceId,
  });

  factory Lesson.fromJson(Map<String, dynamic> json) => Lesson(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        subject: ClassroomSubject.byName(json['subject'] as String?) ??
            ClassroomSubject.foundationalLiteracy,
        classNumber: json['classNumber'] as int,
        learningOutcome: json['learningOutcome'] as String,
        durationMinutes: json['durationMinutes'] as int,
        lessonOrder: json['lessonOrder'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        thumbnailAsset: json['thumbnailAsset'] as String?,
        resourceIds: <String>[
          for (final dynamic r in json['resourceIds'] as List<dynamic>? ??
              const <dynamic>[])
            r as String,
        ],
        concepts: <String>[
          for (final dynamic c
              in json['concepts'] as List<dynamic>? ?? const <dynamic>[])
            c as String,
        ],
        audioResourceId: json['audioResourceId'] as String?,
        worksheetResourceId: json['worksheetResourceId'] as String?,
        flashcardResourceId: json['flashcardResourceId'] as String?,
      );

  final String id;
  final String title;
  final String description;
  final ClassroomSubject subject;
  final int classNumber;
  final String learningOutcome;
  final int durationMinutes;

  /// Position within its class and subject, used by the Oldest/Newest sorts as
  /// a stable tie-break.
  final int lessonOrder;

  final DateTime createdAt;
  final DateTime updatedAt;
  final String? thumbnailAsset;

  /// The offline resource packs this lesson needs.
  final List<String> resourceIds;

  /// What this lesson actually teaches, named so a session can report which
  /// ideas came up and which need more work. Catalogue metadata, not derived
  /// text: an insight that names a concept must be able to point at one.
  final List<String> concepts;

  /// Pointers to the generated materials that belong to this lesson. They name
  /// a resource rather than embedding it, so the catalogue entry stays small
  /// and the material itself is fetched and cached on demand.
  ///
  /// The audio id is per lesson, not per language: the language comes from the
  /// classroom, and the audio store keys a clip by both.
  final String? audioResourceId;
  final String? worksheetResourceId;
  final String? flashcardResourceId;

  /// Content provenance — whether this lesson was authored, adapted or
  /// generated — deliberately does NOT live here. It belongs to the lesson's
  /// content, which is [LessonPlan], so the "AI-generated" badge can only ever
  /// describe text that actually exists rather than a catalogue flag that
  /// might disagree with it.

  /// The language pair is NOT stored on the lesson: it comes from the
  /// teacher's classroom, so one lesson serves every language pairing rather
  /// than being duplicated per language.
  String languagePairFor(ClassroomSetup? classroom) => classroom == null
      ? ''
      : '${classroom.teachingMedium.label} → ${classroom.targetLanguage.label}';

  /// Everything the search box looks at.
  String get searchIndex => <String>[
        title,
        description,
        learningOutcome,
        subject.label,
        subject.shortLabel,
        'class $classNumber',
      ].join(' ').toLowerCase();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'description': description,
        'subject': subject.name,
        'classNumber': classNumber,
        'learningOutcome': learningOutcome,
        'durationMinutes': durationMinutes,
        'lessonOrder': lessonOrder,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'thumbnailAsset': thumbnailAsset,
        'resourceIds': resourceIds,
        'concepts': concepts,
        'audioResourceId': audioResourceId,
        'worksheetResourceId': worksheetResourceId,
        'flashcardResourceId': flashcardResourceId,
      };

  String encode() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) => other is Lesson && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Lesson($id, $title)';
}

/// A lesson plus the per-device state the library renders around it.
///
/// Progress and download state live apart from [Lesson] on purpose: the lesson
/// is catalogue data that will one day come from the server, while these two
/// belong to this device and this teacher.
class LessonCard {
  const LessonCard({
    required this.lesson,
    required this.completionPercentage,
    required this.download,
    this.recommended = false,
  });

  final Lesson lesson;

  /// 0..100.
  final int completionPercentage;

  final DownloadState download;
  final bool recommended;

  bool get completed => completionPercentage >= 100;
  bool get inProgress =>
      completionPercentage > 0 && completionPercentage < 100;
  bool get notStarted => completionPercentage <= 0;
  bool get downloaded => download == DownloadState.downloaded;

  /// Start, Continue or Review, decided by progress rather than by the caller.
  String get actionLabel {
    if (completed) return 'Review';
    if (inProgress) return 'Continue';
    return 'Start';
  }

  LessonCard copyWith({int? completionPercentage, DownloadState? download}) =>
      LessonCard(
        lesson: lesson,
        completionPercentage: completionPercentage ?? this.completionPercentage,
        download: download ?? this.download,
        recommended: recommended,
      );
}
