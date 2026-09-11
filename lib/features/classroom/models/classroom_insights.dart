/// Where a concept stands at the end of a session.
enum ConceptStatus {
  /// Assessed and the child could do it.
  completed(label: 'Completed'),

  /// Assessed and not yet.
  needsReinforcement(label: 'Needs reinforcement'),

  /// It came up in the lesson, but nothing has checked whether it landed.
  discussed(label: 'Discussed');

  const ConceptStatus({required this.label});

  final String label;

  static ConceptStatus byName(String? name) {
    for (final ConceptStatus v in values) {
      if (v.name == name) return v;
    }
    return ConceptStatus.discussed;
  }
}

/// One idea the lesson teaches, and how it went.
class ConceptOutcome {
  const ConceptOutcome({required this.concept, required this.status});

  factory ConceptOutcome.fromJson(Map<String, dynamic> json) => ConceptOutcome(
        concept: json['concept'] as String,
        status: ConceptStatus.byName(json['status'] as String?),
      );

  final String concept;
  final ConceptStatus status;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'concept': concept,
        'status': status.name,
      };
}

/// How much the class took part.
///
/// [unknown] is a real answer, not a placeholder: a session where no child ever
/// spoke tells you nothing about engagement, and saying so is more useful than
/// a cheerful number nobody measured.
enum EngagementLevel {
  active(label: 'Students responded actively'),
  some(label: 'Some students responded'),
  quiet(label: 'No student responses recorded'),
  unknown(label: 'Engagement data unavailable');

  const EngagementLevel({required this.label});

  final String label;

  static EngagementLevel byName(String? name) {
    for (final EngagementLevel v in values) {
      if (v.name == name) return v;
    }
    return EngagementLevel.unknown;
  }
}

/// What can be said about a session once it has ended.
///
/// Everything here is derived from what was actually recorded. Where the
/// evidence does not exist — no assessment was run, no child spoke — the field
/// is null or [EngagementLevel.unknown] and the screen says so rather than
/// filling the gap.
class ClassroomInsights {
  const ClassroomInsights({
    required this.interactionsCompleted,
    required this.engagement,
    required this.concepts,
    required this.generatedAt,
    this.conceptsNeedingReinforcement,
    this.recommendation,
    this.assessedQuestionCount = 0,
    this.fromRules = true,
  });

  factory ClassroomInsights.fromJson(Map<String, dynamic> json) =>
      ClassroomInsights(
        interactionsCompleted: json['interactionsCompleted'] as int,
        engagement: EngagementLevel.byName(json['engagement'] as String?),
        concepts: <ConceptOutcome>[
          for (final dynamic c
              in json['concepts'] as List<dynamic>? ?? const <dynamic>[])
            ConceptOutcome.fromJson(c as Map<String, dynamic>),
        ],
        generatedAt: DateTime.parse(json['generatedAt'] as String),
        conceptsNeedingReinforcement:
            json['conceptsNeedingReinforcement'] as int?,
        recommendation: json['recommendation'] as String?,
        assessedQuestionCount: json['assessedQuestionCount'] as int? ?? 0,
        fromRules: json['fromRules'] as bool? ?? true,
      );

  /// Turns that got all the way to audio.
  final int interactionsCompleted;

  final EngagementLevel engagement;

  /// The lesson's concepts with the status the evidence supports.
  final List<ConceptOutcome> concepts;

  /// Null when nothing has assessed this class, which is different from zero
  /// concepts needing work.
  final int? conceptsNeedingReinforcement;

  /// A short next step, when the evidence supports one.
  final String? recommendation;

  /// How many assessment questions fed these insights.
  final int assessedQuestionCount;

  /// True when these came from the local deterministic rules rather than a
  /// model. The screen must not call rule output "AI".
  final bool fromRules;

  final DateTime generatedAt;

  bool get hasAssessment => assessedQuestionCount > 0;

  List<ConceptOutcome> get reinforcementConcepts => concepts
      .where((ConceptOutcome c) => c.status == ConceptStatus.needsReinforcement)
      .toList(growable: false);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'interactionsCompleted': interactionsCompleted,
        'engagement': engagement.name,
        'concepts': <Map<String, dynamic>>[
          for (final ConceptOutcome c in concepts) c.toJson(),
        ],
        'conceptsNeedingReinforcement': conceptsNeedingReinforcement,
        'recommendation': recommendation,
        'assessedQuestionCount': assessedQuestionCount,
        'fromRules': fromRules,
        'generatedAt': generatedAt.toIso8601String(),
      };
}
