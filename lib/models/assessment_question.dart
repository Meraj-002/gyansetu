import '../features/setup/models/classroom_setup.dart';

/// A naming note, because two things in this app are called "assessment".
///
/// * The *quick assessment* on a lesson (`lib/models/lesson_plan.dart`) is
///   marked by the teacher: they watch a child and tap "Can do" or "Not yet".
/// * The *quiz* described in this file is answered on screen, one multiple
///   choice question at a time, and marked by the app.
///
/// They are different features with different data, so the types here are named
/// `Quiz*` rather than shadowing `AssessmentQuestion` and `AssessmentResult`,
/// which already mean the teacher-marked check. The file names follow the
/// feature ("assessment"), the class names follow the thing ("quiz").

/// A skill one question checks.
///
/// A closed set rather than free text: the result screen groups questions by
/// concept, and two spellings of the same idea would split a group in half.
enum QuizConcept {
  numbers1to5(label: 'Numbers 1–5'),
  numbers6to10(label: 'Numbers 6–10'),
  countingObjects(label: 'Counting Objects'),
  oneToOneCorrespondence(label: 'One-to-One Correspondence'),
  countingMixedObjects(label: 'Counting Mixed Objects'),
  numberRecognition6to10(label: 'Number Recognition (6–10)'),
  pythonBasics(label: 'Python Basics'),
  pythonVariables(label: 'Python Variables'),
  pythonPrintInput(label: 'Python print() & input()'),
  pythonDataTypes(label: 'Python Data Types');

  const QuizConcept({required this.label});

  final String label;

  static QuizConcept? byName(String? name) {
    for (final QuizConcept v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// One picture that can be repeated to make a countable group.
///
/// Every entry is a file bundled with the app. There is no URL here, and there
/// is no code path that fetches one: a child answering these questions is
/// sitting in a classroom with no signal.
enum QuizObject {
  apple(label: 'apple', hindiLabel: 'सेब', asset: 'assets/flashcards/objects/apple.jpg'),
  cup(label: 'cup', hindiLabel: 'कप', asset: 'assets/flashcards/objects/cup.jpg'),
  pencil(label: 'pencil', hindiLabel: 'पेंसिल', asset: 'assets/flashcards/objects/pencil.jpg'),
  leaf(label: 'leaf', hindiLabel: 'पत्ता', asset: 'assets/flashcards/nature/leaf.jpg'),
  hen(label: 'hen', hindiLabel: 'मुर्गी', asset: 'assets/flashcards/animals/hen.jpg'),
  goat(label: 'goat', hindiLabel: 'बकरी', asset: 'assets/flashcards/animals/goat.jpg');

  const QuizObject({
    required this.label,
    required this.hindiLabel,
    required this.asset,
  });

  final String label;
  final String hindiLabel;

  /// A bundled asset path. Never a remote address.
  final String asset;
}

/// A group of one kind of object, drawn [count] times.
class QuizObjectGroup {
  const QuizObjectGroup(this.object, this.count)
      : assert(count > 0, 'a group with nothing in it is not countable');

  final QuizObject object;
  final int count;
}

/// What is shown above the options, if anything.
///
/// Some questions are purely spoken ("which number is आठ?") and deliberately
/// have no picture, so this is nullable on the question rather than having an
/// empty variant.
sealed class QuizVisual {
  const QuizVisual();

  /// Every object drawn, in reading order.
  List<QuizObject> get objects;

  int get total;
}

/// One kind of object, repeated. The plain counting question.
final class CountableObjects extends QuizVisual {
  const CountableObjects(this.object, this.count);

  final QuizObject object;
  final int count;

  @override
  List<QuizObject> get objects =>
      List<QuizObject>.filled(count, object, growable: false);

  @override
  int get total => count;
}

/// Two or more kinds of object in one group, which is a harder count: the child
/// has to stop sorting and count everything.
final class MixedObjects extends QuizVisual {
  const MixedObjects(this.groups);

  final List<QuizObjectGroup> groups;

  @override
  List<QuizObject> get objects => <QuizObject>[
        for (final QuizObjectGroup g in groups)
          for (int i = 0; i < g.count; i++) g.object,
      ];

  @override
  int get total {
    int sum = 0;
    for (final QuizObjectGroup g in groups) {
      sum += g.count;
    }
    return sum;
  }
}

/// One answer a child can tap.
class QuizOption {
  const QuizOption({required this.id, required this.label});

  /// Stable within a question. Answers are stored by id, so re-ordering the
  /// options on screen could never silently change what a child answered.
  final String id;

  /// What the tile shows. A numeral for the counting questions.
  final String label;
}

/// One question in a quiz.
class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.concept,
    required this.prompt,
    required this.promptHindi,
    required this.options,
    required this.correctOptionId,
    this.visual,
    this.spokenTranslations = const <String, String>{},
  });

  final String id;
  final QuizConcept concept;

  /// English wording, for the teacher reading over a shoulder.
  final String prompt;

  /// The wording the class actually hears, in the teaching medium.
  final String promptHindi;

  final QuizVisual? visual;
  final List<QuizOption> options;
  final String correctOptionId;

  /// Mother-tongue wordings of this question, keyed by [TargetLanguage.name].
  ///
  /// Empty for every question today: nobody who speaks Santali, Mundari or Ho
  /// has written and checked these sentences, and inventing them would put made
  /// up language in front of children. The map exists so that adding a reviewed
  /// translation is a data change, and [spokenTextFor] answers null until then
  /// rather than pretending.
  final Map<String, String> spokenTranslations;

  bool isCorrect(String? optionId) => optionId == correctOptionId;

  QuizOption? optionById(String? id) {
    for (final QuizOption o in options) {
      if (o.id == id) return o;
    }
    return null;
  }

  QuizOption get correctOption => optionById(correctOptionId)!;

  /// The mother-tongue reading of this question, or null when there is none.
  String? spokenTextFor(TargetLanguage language) =>
      spokenTranslations[language.name];

  /// Letters shown on the option tiles: A, B, C, D.
  static String letterFor(int index) =>
      String.fromCharCode('A'.codeUnitAt(0) + index);
}
