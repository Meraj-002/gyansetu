/// The kinds of question a worksheet can carry.
///
/// A typed set rather than strings compared around the app: a misspelt
/// "fill_in_blanks" would otherwise be a silent empty worksheet instead of a
/// compile error.
enum QuestionType {
  countingObjects(
    label: 'Counting objects',
    description: 'Count and write the number',
  ),
  matchNumbers(
    label: 'Match numbers',
    description: 'Match number to correct set',
  ),
  fillInTheBlanks(
    label: 'Fill in the blanks',
    description: 'Complete the number sequence',
  ),
  visualIdentification(
    label: 'Visual identification',
    description: 'Identify the correct number',
  );

  const QuestionType({required this.label, required this.description});

  final String label;
  final String description;

  static QuestionType? byName(String? name) {
    for (final QuestionType v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// One question on a worksheet.
///
/// Plain data: no widgets, no colours, no layout. The preview decides how a
/// counting question looks; this only says what it asks.
class WorksheetQuestion {
  const WorksheetQuestion({
    required this.id,
    required this.type,
    required this.questionText,
    required this.correctAnswer,
    required this.order,
    this.translatedQuestionText,
    this.options = const <String>[],
    this.explanation,
    this.visualAsset,
    this.visualCount = 0,
    this.concept,
  });

  factory WorksheetQuestion.fromJson(Map<String, dynamic> json) =>
      WorksheetQuestion(
        id: json['id'] as String,
        type: QuestionType.byName(json['type'] as String?) ??
            QuestionType.countingObjects,
        questionText: json['questionText'] as String,
        correctAnswer: json['correctAnswer'] as String,
        order: json['order'] as int,
        translatedQuestionText: json['translatedQuestionText'] as String?,
        options: <String>[
          for (final dynamic o
              in json['options'] as List<dynamic>? ?? const <dynamic>[])
            o as String,
        ],
        explanation: json['explanation'] as String?,
        visualAsset: json['visualAsset'] as String?,
        visualCount: json['visualCount'] as int? ?? 0,
        concept: json['concept'] as String?,
      );

  final String id;
  final QuestionType type;

  /// The question in the classroom's teaching medium.
  final String questionText;

  /// The same question in the mother tongue.
  ///
  /// Null when no translation exists for it. The preview then shows one
  /// language and says so, rather than printing an invented second line onto a
  /// sheet that goes home with a child.
  final String? translatedQuestionText;

  final List<String> options;
  final String correctAnswer;

  /// A note for the teacher's answer key.
  final String? explanation;

  /// Which everyday object this question draws, as a token the preview
  /// resolves. Not a URL: a worksheet has to print with no connection.
  final String? visualAsset;

  /// How many of that object to draw.
  final int visualCount;

  /// The lesson concept this question practises.
  final String? concept;

  final int order;

  bool get isBilingual => (translatedQuestionText ?? '').trim().isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type.name,
        'questionText': questionText,
        'translatedQuestionText': translatedQuestionText,
        'options': options,
        'correctAnswer': correctAnswer,
        'explanation': explanation,
        'visualAsset': visualAsset,
        'visualCount': visualCount,
        'concept': concept,
        'order': order,
      };
}
