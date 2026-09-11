import '../models/assessment_question.dart';

/// The quiz questions bundled with the app.
///
/// DEVELOPMENT DATA. Ten questions for one lesson, written by hand against the
/// Class 1 numeracy outcome "count objects from 1 to 10". They are here so the
/// feature can be built and tested end to end with no backend; a real catalogue
/// belongs behind `QuizQuestionSource` and would come from FastAPI.
///
/// Two things are deliberately absent.
///
/// * **Mother-tongue wordings.** Every `spokenTranslations` map is empty.
///   Nobody who speaks Santali, Mundari or Ho has written these sentences, and
///   a made-up sentence read aloud to a child is worse than silence. The screen
///   says so and falls back to the teaching medium.
/// * **Pictures drawn for the quiz.** The counting groups reuse the photographs
///   already bundled for the flashcards, so a child meets the same apple in the
///   lesson and in the question.
abstract final class AssessmentQuestionData {
  /// The one lesson this build ships a quiz for.
  static const String countingLessonId = 'c1-num-counting-1-10';

  /// Questions for [lessonId], or an empty list when none were written.
  ///
  /// Returning nothing is a real answer, not a failure: the screen shows "no
  /// assessment for this lesson yet" rather than inventing questions.
  static List<QuizQuestion> forLesson(String lessonId) =>
      switch (lessonId) {
        countingLessonId => countingOneToTen(),
        'python-intro' => pythonIntro(),
        _ => const <QuizQuestion>[],
      };

  static bool hasQuestionsFor(String lessonId) =>
      forLesson(lessonId).isNotEmpty;

  /// Counting 1–10, Class 1, Numeracy.
  static List<QuizQuestion> countingOneToTen() => <QuizQuestion>[
        _counting(
          id: 'q1',
          concept: QuizConcept.numbers1to5,
          visual: const CountableObjects(QuizObject.apple, 3),
          choices: <int>[2, 3, 4, 5],
          answer: 3,
        ),
        _counting(
          id: 'q2',
          concept: QuizConcept.numbers1to5,
          visual: const CountableObjects(QuizObject.leaf, 5),
          choices: <int>[3, 4, 5, 6],
          answer: 5,
        ),
        _counting(
          id: 'q3',
          concept: QuizConcept.countingObjects,
          visual: const CountableObjects(QuizObject.hen, 2),
          choices: <int>[1, 2, 3, 4],
          answer: 2,
        ),
        _counting(
          id: 'q4',
          concept: QuizConcept.numbers6to10,
          visual: const CountableObjects(QuizObject.apple, 7),
          choices: <int>[6, 7, 8, 9],
          answer: 7,
        ),
        _recognition(
          id: 'q5',
          hindiWord: 'आठ',
          choices: <int>[3, 6, 8, 9],
          answer: 8,
        ),
        _counting(
          id: 'q6',
          concept: QuizConcept.countingMixedObjects,
          visual: const MixedObjects(<QuizObjectGroup>[
            QuizObjectGroup(QuizObject.apple, 3),
            QuizObjectGroup(QuizObject.cup, 2),
          ]),
          choices: <int>[4, 5, 6, 7],
          answer: 5,
          prompt: 'Count everything you can see.',
          promptHindi: 'सभी वस्तुओं को गिनकर संख्या बताइए।',
        ),
        _counting(
          id: 'q7',
          concept: QuizConcept.oneToOneCorrespondence,
          visual: const CountableObjects(QuizObject.cup, 4),
          choices: <int>[3, 4, 5, 6],
          answer: 4,
          prompt: 'Each child gets one cup. How many children get a cup?',
          promptHindi: 'हर बच्चे को एक कप मिलता है। कितने बच्चों को कप मिलेगा?',
        ),
        _counting(
          id: 'q8',
          concept: QuizConcept.numbers6to10,
          visual: const CountableObjects(QuizObject.pencil, 9),
          choices: <int>[7, 8, 9, 10],
          answer: 9,
        ),
        _recognition(
          id: 'q9',
          hindiWord: 'छह',
          choices: <int>[4, 6, 7, 10],
          answer: 6,
        ),
        _counting(
          id: 'q10',
          concept: QuizConcept.countingMixedObjects,
          visual: const MixedObjects(<QuizObjectGroup>[
            QuizObjectGroup(QuizObject.goat, 4),
            QuizObjectGroup(QuizObject.hen, 2),
          ]),
          choices: <int>[5, 6, 7, 8],
          answer: 6,
          prompt: 'Count all the animals.',
          promptHindi: 'सभी जानवरों को गिनकर संख्या बताइए।',
        ),
      ];

  /// "Show the number of objects" — a group to count, four numbers to choose.
  static QuizQuestion _counting({
    required String id,
    required QuizConcept concept,
    required QuizVisual visual,
    required List<int> choices,
    required int answer,
    String prompt = 'Show the number of objects.',
    String promptHindi = 'दिए गए वस्तुओं की संख्या बताइए।',
  }) {
    assert(
      visual.total == answer,
      'question $id: the picture shows ${visual.total} objects but the answer '
      'is $answer',
    );
    assert(choices.contains(answer), 'question $id: the answer is not offered');

    return QuizQuestion(
      id: id,
      concept: concept,
      prompt: prompt,
      promptHindi: promptHindi,
      visual: visual,
      options: _numberOptions(choices),
      correctOptionId: 'n$answer',
    );
  }

  /// A number said aloud in the teaching medium, four numerals to choose. No
  /// picture: this question is about hearing a number and finding its digit.
  static QuizQuestion _recognition({
    required String id,
    required String hindiWord,
    required List<int> choices,
    required int answer,
  }) {
    assert(choices.contains(answer), 'question $id: the answer is not offered');

    return QuizQuestion(
      id: id,
      concept: QuizConcept.numberRecognition6to10,
      prompt: 'Which number is “$hindiWord”?',
      promptHindi: '“$hindiWord” कौन-सी संख्या है?',
      options: _numberOptions(choices),
      correctOptionId: 'n$answer',
    );
  }

  static List<QuizOption> _numberOptions(List<int> choices) => <QuizOption>[
        for (final int n in choices) QuizOption(id: 'n$n', label: '$n'        ),
      ];

  static List<QuizQuestion> pythonIntro() => const <QuizQuestion>[
        QuizQuestion(
          id: 'py-q1',
          concept: QuizConcept.pythonBasics,
          prompt: 'What does print() do in Python?',
          promptHindi: 'Python में print() क्या करता है?',
          options: <QuizOption>[
            QuizOption(id: 'py-q1-a', label: 'Displays output on screen'),
            QuizOption(id: 'py-q1-b', label: 'Takes user input'),
            QuizOption(id: 'py-q1-c', label: 'Creates a variable'),
            QuizOption(id: 'py-q1-d', label: 'Deletes text'),
          ],
          correctOptionId: 'py-q1-a',
        ),
        QuizQuestion(
          id: 'py-q2',
          concept: QuizConcept.pythonVariables,
          prompt: 'Which is the correct way to create a variable in Python?',
          promptHindi: 'Python में variable बनाने का सही तरीका क्या है?',
          options: <QuizOption>[
            QuizOption(id: 'py-q2-a', label: 'name = "Meraj"'),
            QuizOption(id: 'py-q2-b', label: 'var name = "Meraj"'),
            QuizOption(id: 'py-q2-c', label: 'let name = "Meraj"'),
            QuizOption(id: 'py-q2-d', label: 'create name = "Meraj"'),
          ],
          correctOptionId: 'py-q2-a',
        ),
        QuizQuestion(
          id: 'py-q3',
          concept: QuizConcept.pythonPrintInput,
          prompt: 'What is the output of: print("Hello")?',
          promptHindi: 'print("Hello") का output क्या होगा?',
          options: <QuizOption>[
            QuizOption(id: 'py-q3-a', label: 'Hello'),
            QuizOption(id: 'py-q3-b', label: '"Hello"'),
            QuizOption(id: 'py-q3-c', label: 'print'),
            QuizOption(id: 'py-q3-d', label: 'Error'),
          ],
          correctOptionId: 'py-q3-a',
        ),
        QuizQuestion(
          id: 'py-q4',
          concept: QuizConcept.pythonDataTypes,
          prompt: 'Which of these is a Python data type?',
          promptHindi: 'इनमें से कौन सा Python data type है?',
          options: <QuizOption>[
            QuizOption(id: 'py-q4-a', label: 'int'),
            QuizOption(id: 'py-q4-b', label: 'num'),
            QuizOption(id: 'py-q4-c', label: 'number'),
            QuizOption(id: 'py-q4-d', label: 'integer'),
          ],
          correctOptionId: 'py-q4-a',
        ),
        QuizQuestion(
          id: 'py-q5',
          concept: QuizConcept.pythonPrintInput,
          prompt: 'Which function takes user input in Python?',
          promptHindi: 'Python में user input लेने के लिए कौन सा function use होता है?',
          options: <QuizOption>[
            QuizOption(id: 'py-q5-a', label: 'input()'),
            QuizOption(id: 'py-q5-b', label: 'get()'),
            QuizOption(id: 'py-q5-c', label: 'read()'),
            QuizOption(id: 'py-q5-d', label: 'scan()'),
          ],
          correctOptionId: 'py-q5-a',
        ),
        QuizQuestion(
          id: 'py-q6',
          concept: QuizConcept.pythonBasics,
          prompt: 'What is a valid Python variable name?',
          promptHindi: 'कौन सा एक सही Python variable name है?',
          options: <QuizOption>[
            QuizOption(id: 'py-q6-a', label: 'my_name'),
            QuizOption(id: 'py-q6-b', label: '2name'),
            QuizOption(id: 'py-q6-c', label: 'my-name'),
            QuizOption(id: 'py-q6-d', label: 'my name'),
          ],
          correctOptionId: 'py-q6-a',
        ),
        QuizQuestion(
          id: 'py-q7',
          concept: QuizConcept.pythonVariables,
          prompt: 'What will be printed: x = 5; print(x)?',
          promptHindi: 'x = 5; print(x) से क्या प्रिंट होगा?',
          options: <QuizOption>[
            QuizOption(id: 'py-q7-a', label: '5'),
            QuizOption(id: 'py-q7-b', label: 'x'),
            QuizOption(id: 'py-q7-c', label: 'x = 5'),
            QuizOption(id: 'py-q7-d', label: 'Error'),
          ],
          correctOptionId: 'py-q7-a',
        ),
        QuizQuestion(
          id: 'py-q8',
          concept: QuizConcept.pythonDataTypes,
          prompt: 'What type is "Hello World" in Python?',
          promptHindi: 'Python में "Hello World" किस type का है?',
          options: <QuizOption>[
            QuizOption(id: 'py-q8-a', label: 'str'),
            QuizOption(id: 'py-q8-b', label: 'int'),
            QuizOption(id: 'py-q8-c', label: 'float'),
            QuizOption(id: 'py-q8-d', label: 'bool'),
          ],
          correctOptionId: 'py-q8-a',
        ),
      ];
}
