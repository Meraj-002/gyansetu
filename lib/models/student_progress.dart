/// One child's standing in a class.
///
/// **There is no pupil roster in this app yet.** Nothing writes these records:
/// the only source today is the prototype class in
/// `DevelopmentStudentRepository`, and every screen showing them says so. The
/// model exists now so that the day a roster is entered — or a backend serves
/// one — the analytics and the screens above it do not change.
class StudentProgress {
  const StudentProgress({
    required this.studentId,
    required this.name,
    required this.classId,
    required this.lessonsCompleted,
    required this.conceptsMastered,
    required this.conceptsNeedingPractice,
    required this.engagementScore,
    this.assessmentScores = const <String, int>{},
  });

  factory StudentProgress.fromJson(Map<String, dynamic> json) =>
      StudentProgress(
        studentId: json['studentId'] as String,
        name: json['name'] as String,
        classId: json['classId'] as String,
        lessonsCompleted: json['lessonsCompleted'] as int? ?? 0,
        conceptsMastered: <String>[
          for (final dynamic c in (json['conceptsMastered'] as List<dynamic>? ??
              const <dynamic>[]))
            '$c',
        ],
        conceptsNeedingPractice: <String>[
          for (final dynamic c
              in (json['conceptsNeedingPractice'] as List<dynamic>? ??
                  const <dynamic>[]))
            '$c',
        ],
        engagementScore: json['engagementScore'] as int? ?? 0,
        assessmentScores: <String, int>{
          for (final MapEntry<String, dynamic> e
              in (json['assessmentScores'] as Map<String, dynamic>? ??
                      const <String, dynamic>{})
                  .entries)
            e.key: e.value as int? ?? 0,
        },
      );

  final String studentId;
  final String name;

  /// Matches the class level in the teacher's classroom setup, as 'class-1'.
  final String classId;

  final int lessonsCompleted;

  /// Percentage per lesson id. Empty when this child has not been assessed.
  final Map<String, int> assessmentScores;

  /// Concept labels, matching [QuizConcept.label] where the concept came from
  /// an assessment, so the two never drift apart.
  final List<String> conceptsMastered;
  final List<String> conceptsNeedingPractice;

  /// 0..100.
  final int engagementScore;

  /// The two letters shown in this child's avatar. No photographs of children
  /// are stored or displayed anywhere in this app.
  String get initials {
    final List<String> parts =
        name.trim().split(RegExp(r'\s+')).where((String p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.takeUpper(2);
    }
    return '${parts.first.takeUpper(1)}${parts.last.takeUpper(1)}';
  }

  bool needsPracticeWith(String concept) =>
      conceptsNeedingPractice.any(
        (String c) => c.toLowerCase() == concept.toLowerCase(),
      );

  /// The average of every assessment this child has sat, or null when they
  /// have sat none. Null means unknown, never zero.
  int? get averageScore {
    if (assessmentScores.isEmpty) return null;
    final int total = assessmentScores.values.reduce((int a, int b) => a + b);
    return (total / assessmentScores.length).round();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'studentId': studentId,
        'name': name,
        'classId': classId,
        'lessonsCompleted': lessonsCompleted,
        'assessmentScores': assessmentScores,
        'conceptsMastered': conceptsMastered,
        'conceptsNeedingPractice': conceptsNeedingPractice,
        'engagementScore': engagementScore,
      };
}

extension on String {
  /// The first [count] characters, upper-cased. Safe on short names.
  String takeUpper(int count) =>
      substring(0, length < count ? length : count).toUpperCase();
}
