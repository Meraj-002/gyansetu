import '../features/setup/models/classroom_setup.dart';

/// Where a piece of lesson content actually came from.
///
/// This is metadata, not decoration. The "AI-generated" badge on lesson detail
/// reads this field, so a badge can only appear when the content really was
/// produced or adapted by the AI layer.
enum ContentProvenance {
  /// Written by a curriculum author. No AI involved.
  authored(label: 'Curriculum authored'),

  /// Human-authored, then reworked by the AI layer for this classroom.
  aiAdapted(label: 'AI-adapted'),

  /// Produced by the AI layer from the learning outcome.
  aiGenerated(label: 'AI-generated');

  const ContentProvenance({required this.label});

  final String label;

  /// Whether the AI layer touched this content at all.
  bool get involvesAi => this != ContentProvenance.authored;

  static ContentProvenance byName(String? name) {
    for (final ContentProvenance v in values) {
      if (v.name == name) return v;
    }
    return ContentProvenance.authored;
  }
}

/// A hands-on activity the teacher runs with the class.
class ClassroomActivity {
  const ClassroomActivity({
    required this.id,
    required this.title,
    required this.summary,
    required this.steps,
    this.materials = const <String>[],
    this.minutes = 5,
  });

  factory ClassroomActivity.fromJson(Map<String, dynamic> json) =>
      ClassroomActivity(
        id: json['id'] as String,
        title: json['title'] as String,
        summary: json['summary'] as String,
        steps: _strings(json['steps']),
        materials: _strings(json['materials']),
        minutes: json['minutes'] as int? ?? 5,
      );

  final String id;
  final String title;

  /// The one line shown on the lesson detail card.
  final String summary;

  /// What the teacher does, in order.
  final List<String> steps;

  /// Everyday objects the activity needs. Deliberately things a village
  /// classroom already has.
  final List<String> materials;

  final int minutes;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'summary': summary,
        'steps': steps,
        'materials': materials,
        'minutes': minutes,
      };
}

/// One thing the teacher asks a child to do.
class AssessmentQuestion {
  const AssessmentQuestion({
    required this.id,
    required this.prompt,
    required this.successCriteria,
    this.concept,
  });

  factory AssessmentQuestion.fromJson(Map<String, dynamic> json) =>
      AssessmentQuestion(
        id: json['id'] as String,
        prompt: json['prompt'] as String,
        successCriteria: json['successCriteria'] as String,
        concept: json['concept'] as String?,
      );

  final String id;

  /// What the teacher says to the child.
  final String prompt;

  /// What counts as the child having done it. Written down so two teachers
  /// mark the same child the same way.
  final String successCriteria;

  /// Which of the lesson's concepts this question checks.
  ///
  /// This is the link that lets a failed answer name a concept to reinforce.
  /// Without it an insight could only say how many answers were wrong, never
  /// which idea the class has not got yet.
  final String? concept;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'prompt': prompt,
        'successCriteria': successCriteria,
        'concept': concept,
      };
}

/// A short check the teacher runs at the end of a lesson.
class QuickAssessment {
  const QuickAssessment({
    required this.id,
    required this.title,
    required this.summary,
    required this.questions,
  });

  factory QuickAssessment.fromJson(Map<String, dynamic> json) =>
      QuickAssessment(
        id: json['id'] as String,
        title: json['title'] as String,
        summary: json['summary'] as String,
        questions: <AssessmentQuestion>[
          for (final dynamic q
              in json['questions'] as List<dynamic>? ?? const <dynamic>[])
            AssessmentQuestion.fromJson(q as Map<String, dynamic>),
        ],
      );

  final String id;
  final String title;

  /// The one line shown on the lesson detail card.
  final String summary;

  final List<AssessmentQuestion> questions;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'summary': summary,
        'questions': <Map<String, dynamic>>[
          for (final AssessmentQuestion q in questions) q.toJson(),
        ],
      };
}

/// A teaching suggestion tied to this lesson's outcome.
class TeachingTip {
  const TeachingTip({
    required this.text,
    this.provenance = ContentProvenance.authored,
  });

  factory TeachingTip.fromJson(Map<String, dynamic> json) => TeachingTip(
        text: json['text'] as String,
        provenance: ContentProvenance.byName(json['provenance'] as String?),
      );

  final String text;

  /// Read by the tip card, so it can only call itself AI-written when it is.
  final ContentProvenance provenance;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'text': text,
        'provenance': provenance.name,
      };
}

/// Everything a teacher needs in order to run a lesson.
///
/// Kept apart from [Lesson] on purpose. A `Lesson` is a catalogue entry —
/// small, listable, and one day served from the server's index. A `LessonPlan`
/// is the body: it is what the AI pipeline generates or adapts, it is what gets
/// cached for offline use, and it carries its own provenance and version. The
/// library screen never needs it; only lesson detail does.
class LessonPlan {
  const LessonPlan({
    required this.lessonId,
    required this.scriptMedium,
    required this.teacherScript,
    required this.activity,
    required this.assessment,
    required this.generatedAt,
    this.tip,
    this.provenance = ContentProvenance.authored,
    this.curriculumAligned = true,
    this.flnCompetency,
    this.version = 1,
  });

  factory LessonPlan.fromJson(Map<String, dynamic> json) => LessonPlan(
        lessonId: json['lessonId'] as String,
        scriptMedium: TeachingMedium.byName(json['scriptMedium'] as String?) ??
            TeachingMedium.hindi,
        teacherScript: json['teacherScript'] as String,
        activity: ClassroomActivity.fromJson(
          json['activity'] as Map<String, dynamic>,
        ),
        assessment: QuickAssessment.fromJson(
          json['assessment'] as Map<String, dynamic>,
        ),
        generatedAt: DateTime.parse(json['generatedAt'] as String),
        tip: json['tip'] == null
            ? null
            : TeachingTip.fromJson(json['tip'] as Map<String, dynamic>),
        provenance: ContentProvenance.byName(json['provenance'] as String?),
        curriculumAligned: json['curriculumAligned'] as bool? ?? true,
        flnCompetency: json['flnCompetency'] as String?,
        version: json['version'] as int? ?? 1,
      );

  final String lessonId;

  /// The language the script is written in. It is the classroom's teaching
  /// medium, not a fixed 'Hindi'.
  final TeachingMedium scriptMedium;

  /// The ready-to-read classroom script.
  final String teacherScript;

  final ClassroomActivity activity;
  final QuickAssessment assessment;
  final TeachingTip? tip;

  final ContentProvenance provenance;

  /// Whether this plan is aligned to the NIPUN Bharat / FLN goal named in
  /// [flnCompetency]. The badge on lesson detail reads this.
  final bool curriculumAligned;

  /// The competency code or description the outcome maps to.
  final String? flnCompetency;

  /// Bumped whenever the content behind this plan changes, so a cached copy
  /// can be recognised as stale.
  final int version;

  final DateTime generatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'lessonId': lessonId,
        'scriptMedium': scriptMedium.name,
        'teacherScript': teacherScript,
        'activity': activity.toJson(),
        'assessment': assessment.toJson(),
        'tip': tip?.toJson(),
        'provenance': provenance.name,
        'curriculumAligned': curriculumAligned,
        'flnCompetency': flnCompetency,
        'version': version,
        'generatedAt': generatedAt.toIso8601String(),
      };
}

/// How a child did on one assessment question.
enum AssessmentOutcome {
  /// The child met the success criteria.
  achieved(label: 'Can do'),

  /// Not yet. Recorded plainly rather than as a failure.
  notYet(label: 'Not yet');

  const AssessmentOutcome({required this.label});

  final String label;

  static AssessmentOutcome byName(String? name) =>
      name == AssessmentOutcome.achieved.name
          ? AssessmentOutcome.achieved
          : AssessmentOutcome.notYet;
}

/// A completed quick assessment, recorded on this device.
class AssessmentResult {
  const AssessmentResult({
    required this.lessonId,
    required this.assessmentId,
    required this.outcomes,
    required this.recordedAt,
  });

  factory AssessmentResult.fromJson(Map<String, dynamic> json) =>
      AssessmentResult(
        lessonId: json['lessonId'] as String,
        assessmentId: json['assessmentId'] as String,
        outcomes: <String, AssessmentOutcome>{
          for (final MapEntry<String, dynamic> e
              in (json['outcomes'] as Map<String, dynamic>).entries)
            e.key: AssessmentOutcome.byName(e.value as String?),
        },
        recordedAt: DateTime.parse(json['recordedAt'] as String),
      );

  final String lessonId;
  final String assessmentId;

  /// Question id to outcome.
  final Map<String, AssessmentOutcome> outcomes;

  final DateTime recordedAt;

  int get achievedCount => outcomes.values
      .where((AssessmentOutcome o) => o == AssessmentOutcome.achieved)
      .length;

  int get total => outcomes.length;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'lessonId': lessonId,
        'assessmentId': assessmentId,
        'outcomes': <String, String>{
          for (final MapEntry<String, AssessmentOutcome> e in outcomes.entries)
            e.key: e.value.name,
        },
        'recordedAt': recordedAt.toIso8601String(),
      };
}

List<String> _strings(dynamic value) => <String>[
      for (final dynamic v in value as List<dynamic>? ?? const <dynamic>[])
        v as String,
    ];
