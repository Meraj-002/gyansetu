import 'assessment_answer.dart';
import 'assessment_question.dart';

/// How one concept was answered.
///
/// A concept counts as understood only when every question testing it was
/// right. Half-right is reported as needing reinforcement, because a child who
/// counted one group correctly and another wrongly has not got it yet.
class ConceptPerformance {
  const ConceptPerformance({
    required this.concept,
    required this.correct,
    required this.total,
  });

  factory ConceptPerformance.fromJson(Map<String, dynamic> json) =>
      ConceptPerformance(
        concept: QuizConcept.byName(json['concept'] as String?) ??
            QuizConcept.countingObjects,
        correct: json['correct'] as int? ?? 0,
        total: json['total'] as int? ?? 0,
      );

  final QuizConcept concept;
  final int correct;
  final int total;

  bool get understood => total > 0 && correct == total;

  bool get needsReinforcement => total > 0 && correct < total;

  /// 0..100. Zero when nothing tested this concept, which cannot happen for a
  /// concept that is in the list at all.
  int get percentage => total == 0 ? 0 : ((correct / total) * 100).round();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'concept': concept.name,
        'correct': correct,
        'total': total,
      };
}

/// How a child did overall.
///
/// Every number is counted from the answers that were actually given. There is
/// no default score and no placeholder duration: an assessment that was not
/// finished does not produce one of these.
class QuizResult {
  const QuizResult({
    required this.lessonId,
    required this.score,
    required this.total,
    required this.concepts,
    required this.startedAt,
    required this.finishedAt,
    required this.answers,
  });

  /// Marks [answers] against [questions] and counts everything up.
  ///
  /// The marking is redone here rather than trusting the stored `correct` flag,
  /// so an answer restored from an older build cannot report a score that its
  /// own question disagrees with.
  factory QuizResult.from({
    required String lessonId,
    required List<QuizQuestion> questions,
    required Map<String, QuizAnswer> answers,
    required DateTime startedAt,
    required DateTime finishedAt,
  }) {
    int score = 0;
    final Map<QuizConcept, int> correctByConcept = <QuizConcept, int>{};
    final Map<QuizConcept, int> totalByConcept = <QuizConcept, int>{};

    for (final QuizQuestion q in questions) {
      final QuizAnswer? answer = answers[q.id];
      final bool right =
          answer != null && q.isCorrect(answer.selectedOptionId);
      if (right) score++;

      totalByConcept[q.concept] = (totalByConcept[q.concept] ?? 0) + 1;
      correctByConcept[q.concept] =
          (correctByConcept[q.concept] ?? 0) + (right ? 1 : 0);
    }

    return QuizResult(
      lessonId: lessonId,
      score: score,
      total: questions.length,
      // Listed in the order the enum declares, so two runs of the same
      // assessment read the same way down the page.
      concepts: <ConceptPerformance>[
        for (final QuizConcept c in QuizConcept.values)
          if (totalByConcept.containsKey(c))
            ConceptPerformance(
              concept: c,
              correct: correctByConcept[c] ?? 0,
              total: totalByConcept[c]!,
            ),
      ],
      startedAt: startedAt,
      finishedAt: finishedAt,
      answers: Map<String, QuizAnswer>.unmodifiable(answers),
    );
  }

  factory QuizResult.fromJson(Map<String, dynamic> json) => QuizResult(
        lessonId: json['lessonId'] as String,
        score: json['score'] as int? ?? 0,
        total: json['total'] as int? ?? 0,
        concepts: <ConceptPerformance>[
          for (final dynamic c
              in (json['concepts'] as List<dynamic>? ?? const <dynamic>[]))
            ConceptPerformance.fromJson(c as Map<String, dynamic>),
        ],
        startedAt: DateTime.tryParse(json['startedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        finishedAt: DateTime.tryParse(json['finishedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        answers: <String, QuizAnswer>{
          for (final MapEntry<String, dynamic> e
              in (json['answers'] as Map<String, dynamic>? ??
                      const <String, dynamic>{})
                  .entries)
            e.key: QuizAnswer.fromJson(e.value as Map<String, dynamic>),
        },
      );

  final String lessonId;
  final int score;
  final int total;
  final List<ConceptPerformance> concepts;
  final DateTime startedAt;
  final DateTime finishedAt;
  final Map<String, QuizAnswer> answers;

  int get percentage => total == 0 ? 0 : ((score / total) * 100).round();

  Duration get duration => finishedAt.difference(startedAt);

  /// "4 min 12 sec", or "48 sec" under a minute.
  String get durationLabel {
    final Duration d = duration;
    if (d.inSeconds <= 0) return '--';
    if (d.inMinutes < 1) return '${d.inSeconds} sec';
    final int seconds = d.inSeconds % 60;
    return seconds == 0
        ? '${d.inMinutes} min'
        : '${d.inMinutes} min $seconds sec';
  }

  List<ConceptPerformance> get understood => <ConceptPerformance>[
        for (final ConceptPerformance c in concepts)
          if (c.understood) c,
      ];

  List<ConceptPerformance> get needsReinforcement => <ConceptPerformance>[
        for (final ConceptPerformance c in concepts)
          if (c.needsReinforcement) c,
      ];

  /// One line of encouragement, chosen from the score alone.
  ///
  /// Deliberately plain, and never says a child did well when they did not.
  String get encouragement => switch (percentage) {
        >= 90 => 'Excellent! Keep up the good work.',
        >= 70 => 'Well done. A little more practice and this is solid.',
        >= 40 => 'A good start. Some of this needs another go.',
        _ => 'This one needs more practice together.',
      };

  Map<String, dynamic> toJson() => <String, dynamic>{
        'lessonId': lessonId,
        'score': score,
        'total': total,
        'concepts': <Map<String, dynamic>>[
          for (final ConceptPerformance c in concepts) c.toJson(),
        ],
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt.toIso8601String(),
        'answers': <String, dynamic>{
          for (final MapEntry<String, QuizAnswer> e in answers.entries)
            e.key: e.value.toJson(),
        },
      };
}
