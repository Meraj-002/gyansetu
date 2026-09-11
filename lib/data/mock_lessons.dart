import '../features/setup/models/classroom_setup.dart';
import '../models/lesson.dart';

/// The prototype lesson catalogue.
///
/// DEVELOPMENT DATA. No lesson bodies ship with this build and there is no
/// backend, so this is the whole catalogue: metadata only, enough to exercise
/// search, every filter, every sort and both empty states. Thumbnails are real
/// bundled assets; the lesson content behind them is not.
///
/// REPLACE WITH: `RemoteLessonRepository` reading the FastAPI catalogue, cached
/// into the local database. Nothing above `LessonRepository` changes when it
/// does.
abstract final class MockLessons {
  static const String _art = 'assets/images/lessons';

  /// Fixed dates so ordering is deterministic in tests and in the UI.
  static final DateTime _base = DateTime(2026, 6, 1);

  static List<Lesson> all() => <Lesson>[
        // --- Class 1 --------------------------------------------------------
        _lesson(
          id: 'c1-num-counting-1-10',
          title: 'Counting 1–10',
          description: 'Count everyday objects aloud from one to ten.',
          subject: ClassroomSubject.numeracy,
          classNumber: 1,
          outcome: 'Count objects from 1 to 10.',
          minutes: 10,
          order: 1,
          concepts: <String>[
            'Counting 1–10',
            'Number Sequence',
            'After, Before, Between',
          ],
          daysAfterBase: 60,
          thumbnail: '$_art/counting_1_10.png',
        ),
        _lesson(
          id: 'c1-lit-swar-a-aa-i',
          title: 'Swar: A, AA, I',
          description: 'The first three vowels, by sound and by shape.',
          subject: ClassroomSubject.foundationalLiteracy,
          classNumber: 1,
          outcome: 'Identify and read basic swar letters.',
          minutes: 12,
          order: 2,
          concepts: <String>[
            'Vowel sounds',
            'Letter shapes',
          ],
          daysAfterBase: 52,
          thumbnail: '$_art/swar_a_aa_i.png',
        ),
        _lesson(
          id: 'c1-num-shapes',
          title: 'Shapes Around Us',
          description: 'Find circles, squares and triangles in the classroom.',
          subject: ClassroomSubject.numeracy,
          classNumber: 1,
          outcome: 'Identify and name common shapes.',
          minutes: 15,
          order: 3,
          concepts: <String>[
            'Circle, square, triangle',
            'Shapes around us',
          ],
          daysAfterBase: 44,
          thumbnail: '$_art/shapes_around_us.png',
        ),
        _lesson(
          id: 'c1-lit-story-horen',
          title: 'Story: Horen and the Mango Tree',
          description: 'A short story to listen to and retell together.',
          subject: ClassroomSubject.foundationalLiteracy,
          classNumber: 1,
          outcome: 'Listen and understand the story.',
          minutes: 18,
          order: 4,
          concepts: <String>[
            'Listening',
            'Retelling a story',
          ],
          daysAfterBase: 36,
          thumbnail: '$_art/story_horen_mango.png',
        ),
        _lesson(
          id: 'c1-num-counting-1-20',
          title: 'Counting 1–20',
          description: 'Extend counting beyond ten, in groups.',
          subject: ClassroomSubject.numeracy,
          classNumber: 1,
          outcome: 'Count objects from 1 to 20.',
          minutes: 14,
          order: 5,
          concepts: <String>[
            'Counting 1–20',
            'Groups of ten',
          ],
          daysAfterBase: 28,
          thumbnail: '$_art/counting_1_20.png',
        ),
        _lesson(
          id: 'c1-lit-my-family',
          title: 'My Family Words',
          description: 'Name family members in the mother tongue.',
          subject: ClassroomSubject.foundationalLiteracy,
          classNumber: 1,
          outcome: 'Name five family members aloud.',
          minutes: 9,
          order: 6,
          concepts: <String>[
            'Family words',
            'Speaking aloud',
          ],
          daysAfterBase: 20,
        ),

        // --- Class 2 --------------------------------------------------------
        _lesson(
          id: 'c2-num-addition-10',
          title: 'Adding Within 10',
          description: 'Join two small groups and count the total.',
          subject: ClassroomSubject.numeracy,
          classNumber: 2,
          outcome: 'Add two numbers with a total up to 10.',
          minutes: 16,
          order: 1,
          concepts: <String>[
            'Joining two groups',
            'Sums up to 10',
          ],
          daysAfterBase: 48,
        ),
        _lesson(
          id: 'c2-lit-matra',
          title: 'Matra: Aa and I',
          description: 'Reading words once the vowel signs appear.',
          subject: ClassroomSubject.foundationalLiteracy,
          classNumber: 2,
          outcome: 'Read simple words with aa and i matra.',
          minutes: 20,
          order: 2,
          concepts: <String>[
            'Aa matra',
            'I matra',
            'Reading words',
          ],
          daysAfterBase: 40,
        ),

        // --- Class 3 --------------------------------------------------------
        _lesson(
          id: 'c3-num-place-value',
          title: 'Tens and Ones',
          description: 'Break two-digit numbers into tens and ones.',
          subject: ClassroomSubject.numeracy,
          classNumber: 3,
          outcome: 'Explain the place value of a two-digit number.',
          minutes: 22,
          order: 1,
          daysAfterBase: 32,
        ),
        _lesson(
          id: 'c3-lit-village-story',
          title: 'A Day in Our Village',
          description: 'A reading passage rooted in daily village life.',
          subject: ClassroomSubject.foundationalLiteracy,
          classNumber: 3,
          outcome: 'Read a short passage and answer questions about it.',
          minutes: 25,
          order: 2,
          daysAfterBase: 24,
        ),

        // --- Class 4 and 5 --------------------------------------------------
        _lesson(
          id: 'c4-num-multiplication',
          title: 'Groups and Multiplication',
          description: 'Repeated addition, and why it becomes multiplication.',
          subject: ClassroomSubject.numeracy,
          classNumber: 4,
          outcome: 'Solve simple multiplication using equal groups.',
          minutes: 28,
          order: 1,
          daysAfterBase: 16,
        ),
        _lesson(
          id: 'c5-lit-letter-writing',
          title: 'Writing a Short Letter',
          description: 'Structure a simple letter to a friend.',
          subject: ClassroomSubject.foundationalLiteracy,
          classNumber: 5,
          outcome: 'Write a short letter with a greeting and a closing.',
          minutes: 30,
          order: 1,
          daysAfterBase: 8,
        ),

        // --- Python (SIH Demo) -----------------------------------------------
        _lesson(
          id: 'python-intro',
          title: 'Python',
          description:
              'Introduction to Python programming — variables, print, input, and basic concepts.',
          subject: ClassroomSubject.numeracy,
          classNumber: 5,
          outcome:
              'Understand what Python is, write basic Python code with variables, print(), and input().',
          minutes: 25,
          order: 1,
          daysAfterBase: 1,
          concepts: <String>[
            'Python basics',
            'Variables',
            'print()',
            'input()',
            'Data types',
            'Hello World',
          ],
        ),
      ];

  /// Progress recorded on this device, keyed by lesson id.
  ///
  /// DEVELOPMENT DATA. Nothing writes progress yet — lesson detail is not
  /// built — so the library is seeded with a spread that covers not-started,
  /// in-progress and completed.
  static Map<String, int> seedProgress() => <String, int>{
        'c1-num-counting-1-10': 80,
        'c1-lit-swar-a-aa-i': 60,
        'c1-num-shapes': 75,
        'c1-lit-story-horen': 40,
        'c1-num-counting-1-20': 0,
        'c1-lit-my-family': 100,
        'c2-num-addition-10': 100,
        'c2-lit-matra': 30,
        'c3-num-place-value': 0,
        'python-intro': 0,
      };

  /// Which lessons this device already holds content for.
  ///
  /// DEVELOPMENT DATA. No real packs exist; this seeds a mix so the Downloaded
  /// filter and the offline messages are both reachable.
  static Set<String> seedDownloaded() => <String>{
        'c1-num-counting-1-10',
        'c1-lit-swar-a-aa-i',
        'c1-num-shapes',
        'c1-num-counting-1-20',
        'c2-num-addition-10',
        'c1-lit-my-family',
        'python-intro',
      };

  static Lesson _lesson({
    required String id,
    required String title,
    required String description,
    required ClassroomSubject subject,
    required int classNumber,
    required String outcome,
    required int minutes,
    required int order,
    required int daysAfterBase,
    String? thumbnail,
    List<String> concepts = const <String>[],
  }) {
    final DateTime created = _base.add(Duration(days: daysAfterBase));
    return Lesson(
      id: id,
      title: title,
      description: description,
      subject: subject,
      classNumber: classNumber,
      learningOutcome: outcome,
      durationMinutes: minutes,
      concepts: concepts,
      lessonOrder: order,
      createdAt: created,
      updatedAt: created,
      thumbnailAsset: thumbnail,
      resourceIds: <String>['$id.content', '$id.audio'],
    );
  }
}
