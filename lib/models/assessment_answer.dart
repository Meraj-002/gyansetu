/// What a child tapped for one question.
///
/// See the naming note at the top of `assessment_question.dart` for why these
/// types are called `Quiz*`.
class QuizAnswer {
  const QuizAnswer({
    required this.questionId,
    required this.selectedOptionId,
    required this.correct,
    required this.answeredAt,
    this.timeTaken,
  });

  factory QuizAnswer.fromJson(Map<String, dynamic> json) => QuizAnswer(
        questionId: json['questionId'] as String,
        selectedOptionId: json['selectedOptionId'] as String,
        correct: json['correct'] as bool? ?? false,
        answeredAt:
            DateTime.tryParse(json['answeredAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
        timeTaken: switch (json['timeTakenMs']) {
          final int ms => Duration(milliseconds: ms),
          _ => null,
        },
      );

  final String questionId;
  final String selectedOptionId;

  /// Marked when the answer was given, against the question it was given for.
  final bool correct;

  final DateTime answeredAt;

  /// How long this question was on screen before it was answered, or null when
  /// it was not measured — which is the case for an answer restored from
  /// storage after the app was closed. Null means unknown, never zero.
  final Duration? timeTaken;

  QuizAnswer copyWith({
    String? selectedOptionId,
    bool? correct,
    DateTime? answeredAt,
    Duration? timeTaken,
  }) =>
      QuizAnswer(
        questionId: questionId,
        selectedOptionId: selectedOptionId ?? this.selectedOptionId,
        correct: correct ?? this.correct,
        answeredAt: answeredAt ?? this.answeredAt,
        timeTaken: timeTaken ?? this.timeTaken,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'questionId': questionId,
        'selectedOptionId': selectedOptionId,
        'correct': correct,
        'answeredAt': answeredAt.toIso8601String(),
        if (timeTaken != null) 'timeTakenMs': timeTaken!.inMilliseconds,
      };
}
