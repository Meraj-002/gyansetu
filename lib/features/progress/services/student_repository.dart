import '../../../models/assessment_question.dart';
import '../../../models/student_progress.dart';

/// Where pupil records come from.
///
/// An interface with, today, only a prototype implementation. When a roster is
/// entered — or a backend serves one — this is the single seam that changes.
abstract interface class StudentRepository {
  /// Whether these records describe real children.
  ///
  /// False for the prototype class. Every screen that shows a pupil count or a
  /// pupil name reads this and says so, so a teacher is never left thinking the
  /// app knows their class when it does not.
  bool get isRealRoster;

  /// The class, or an empty list when there is no roster for it.
  Future<List<StudentProgress>> forClass(int classLevel);

  Future<StudentProgress?> byId(String studentId);

  /// The children needing work on [concept], worst engagement first.
  Future<List<StudentProgress>> needingPracticeWith(
    String concept, {
    required int classLevel,
  });
}

/// A sample Class 1, so the insights screen can be built and judged.
///
/// **PROTOTYPE DATA — these are not real children.** No roster has been
/// entered anywhere in this app and nothing writes pupil records. The names
/// below are invented, the figures are fixed, and the screen labels them as a
/// sample wherever it shows them.
///
/// REPLACE WITH: a pupil table written by an attendance or enrolment feature,
/// or a roster served by the backend.
class DevelopmentStudentRepository implements StudentRepository {
  const DevelopmentStudentRepository({this.classLevel = 1});

  /// The one class this sample describes. A request for any other class
  /// correctly returns nothing rather than pretending.
  final int classLevel;

  @override
  bool get isRealRoster => false;

  /// Invented names, chosen to read naturally for a Jharkhand primary school.
  static const List<String> _names = <String>[
    'Aarti Murmu', 'Bikash Hansda', 'Chandni Tudu', 'Dinesh Soren',
    'Ekta Baskey', 'Farhan Ansari', 'Gita Kisku', 'Hemant Mardi',
    'Ishita Hembrom', 'Jitu Marandi', 'Kavita Besra', 'Lalan Munda',
    'Mamta Purty', 'Nitesh Bodra', 'Omkar Kandulna', 'Pooja Barla',
    'Rahul Topno', 'Sunita Ekka', 'Tarun Lakra', 'Usha Minz',
    'Vikas Kerketta', 'Wasim Khan', 'Yamini Toppo', 'Zubin Gudia',
  ];

  /// Which sample children have not got numbers past five yet.
  ///
  /// Fixed indices rather than anything random, so the screen shows the same
  /// six children on every run and a test can assert on them.
  static const Set<int> _needNumbersBeyondFive = <int>{1, 4, 7, 12, 17, 21};

  /// Which of them are also shaky on counting a mixed group.
  static const Set<int> _needMixedCounting = <int>{4, 12, 21};

  @override
  Future<List<StudentProgress>> forClass(int level) async {
    if (level != classLevel) return const <StudentProgress>[];
    return List<StudentProgress>.unmodifiable(_roster());
  }

  @override
  Future<StudentProgress?> byId(String studentId) async {
    for (final StudentProgress s in _roster()) {
      if (s.studentId == studentId) return s;
    }
    return null;
  }

  @override
  Future<List<StudentProgress>> needingPracticeWith(
    String concept, {
    required int classLevel,
  }) async {
    final List<StudentProgress> matching = <StudentProgress>[
      for (final StudentProgress s in await forClass(classLevel))
        if (s.needsPracticeWith(concept)) s,
    ];
    // The child engaging least is the one to reach first.
    matching.sort(
      (StudentProgress a, StudentProgress b) =>
          a.engagementScore.compareTo(b.engagementScore),
    );
    return List<StudentProgress>.unmodifiable(matching);
  }

  List<StudentProgress> _roster() => <StudentProgress>[
        for (int i = 0; i < _names.length; i++) _student(i),
      ];

  StudentProgress _student(int index) {
    final bool beyondFive = _needNumbersBeyondFive.contains(index);
    final bool mixed = _needMixedCounting.contains(index);

    final List<String> needs = <String>[
      if (beyondFive) QuizConcept.numbers6to10.label,
      if (beyondFive) QuizConcept.numberRecognition6to10.label,
      if (mixed) QuizConcept.countingMixedObjects.label,
    ];

    final List<String> mastered = <String>[
      QuizConcept.numbers1to5.label,
      QuizConcept.countingObjects.label,
      if (!beyondFive) QuizConcept.numbers6to10.label,
      if (!mixed) QuizConcept.countingMixedObjects.label,
    ];

    // Spread deterministically from the index so the sample class has a
    // believable range without anything being random.
    final int base = beyondFive ? 48 : 74;
    final int score = (base + (index * 7) % 22).clamp(0, 100);

    return StudentProgress(
      studentId: 'sample-c$classLevel-${index + 1}',
      name: _names[index],
      classId: 'class-$classLevel',
      lessonsCompleted: beyondFive ? 1 : 2,
      assessmentScores: <String, int>{'c1-num-counting-1-10': score},
      conceptsMastered: mastered,
      conceptsNeedingPractice: needs,
      engagementScore: (score + (beyondFive ? 6 : 12)).clamp(0, 100),
    );
  }
}

/// No roster at all.
///
/// What a device looks like before anybody enters a class. Used by tests, and
/// the honest default the day pupil records become real: an empty roster is
/// reported as "no pupil records yet", never as a class of zero children.
class EmptyStudentRepository implements StudentRepository {
  const EmptyStudentRepository();

  @override
  bool get isRealRoster => true;

  @override
  Future<List<StudentProgress>> forClass(int classLevel) async =>
      const <StudentProgress>[];

  @override
  Future<StudentProgress?> byId(String studentId) async => null;

  @override
  Future<List<StudentProgress>> needingPracticeWith(
    String concept, {
    required int classLevel,
  }) async =>
      const <StudentProgress>[];
}
