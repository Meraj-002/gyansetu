import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/data/mock_lessons.dart';
import 'package:gyan_setu_ai/features/lessons/services/lesson_query.dart';
import 'package:gyan_setu_ai/features/lessons/services/recommendation_repository.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/models/lesson.dart';

import 'lesson_test_doubles.dart';

void main() {
  /// A small catalogue covering every axis the query engine filters on.
  final List<LessonCard> cards = <LessonCard>[
    LessonCard(
      lesson: testLesson(
        id: 'a',
        title: 'Counting 1–10',
        outcome: 'Count objects from 1 to 10.',
        minutes: 10,
        daysOld: 0,
      ),
      completionPercentage: 80,
      download: DownloadState.downloaded,
    ),
    LessonCard(
      lesson: testLesson(
        id: 'b',
        title: 'Swar: A, AA, I',
        subject: ClassroomSubject.foundationalLiteracy,
        outcome: 'Identify and read basic swar letters.',
        minutes: 12,
        daysOld: 10,
      ),
      completionPercentage: 100,
      download: DownloadState.downloaded,
    ),
    LessonCard(
      lesson: testLesson(
        id: 'c',
        title: 'Adding Within 10',
        classNumber: 2,
        outcome: 'Add two numbers.',
        minutes: 20,
        daysOld: 20,
      ),
      completionPercentage: 0,
      download: DownloadState.notDownloaded,
    ),
    LessonCard(
      lesson: testLesson(
        id: 'd',
        title: 'Zebra Story',
        subject: ClassroomSubject.foundationalLiteracy,
        outcome: 'Retell a short story.',
        minutes: 6,
        daysOld: 30,
      ),
      completionPercentage: 45,
      download: DownloadState.notDownloaded,
    ),
  ];

  List<String> idsOf(List<LessonCard> result) =>
      result.map((LessonCard c) => c.lesson.id).toList();

  group('search', () {
    test('matches the title', () {
      const LessonQuery q = LessonQuery(search: 'counting');
      expect(idsOf(q.apply(cards)), <String>['a']);
    });

    test('is case insensitive and whitespace tolerant', () {
      const LessonQuery q = LessonQuery(search: '   COUNT   ');
      expect(idsOf(q.apply(cards)), <String>['a']);
    });

    test('matches the learning outcome and the subject', () {
      expect(
        idsOf(const LessonQuery(search: 'retell').apply(cards)),
        <String>['d'],
      );
      expect(
        idsOf(const LessonQuery(search: 'literacy').apply(cards)).toSet(),
        <String>{'b', 'd'},
      );
    });

    test('an empty search returns everything', () {
      expect(const LessonQuery().apply(cards).length, cards.length);
      expect(const LessonQuery(search: '   ').apply(cards).length, cards.length);
    });

    test('no match returns nothing', () {
      expect(const LessonQuery(search: 'astrophysics').apply(cards), isEmpty);
    });
  });

  group('filters', () {
    test('by class', () {
      expect(
        idsOf(const LessonQuery(classNumber: 2).apply(cards)),
        <String>['c'],
      );
    });

    test('by literacy and by numeracy', () {
      expect(
        idsOf(const LessonQuery(
          subject: ClassroomSubject.foundationalLiteracy,
        ).apply(cards)).toSet(),
        <String>{'b', 'd'},
      );
      expect(
        idsOf(const LessonQuery(subject: ClassroomSubject.numeracy)
            .apply(cards)).toSet(),
        <String>{'a', 'c'},
      );
    });

    test('by completion state', () {
      expect(
        idsOf(const LessonQuery(completion: CompletionFilter.completed)
            .apply(cards)),
        <String>['b'],
      );
      expect(
        idsOf(const LessonQuery(completion: CompletionFilter.notStarted)
            .apply(cards)),
        <String>['c'],
      );
      expect(
        idsOf(const LessonQuery(completion: CompletionFilter.inProgress)
            .apply(cards)).toSet(),
        <String>{'a', 'd'},
      );
    });

    test('by downloaded state', () {
      expect(
        idsOf(const LessonQuery(download: DownloadFilter.downloaded)
            .apply(cards)).toSet(),
        <String>{'a', 'b'},
      );
      expect(
        idsOf(const LessonQuery(download: DownloadFilter.notDownloaded)
            .apply(cards)).toSet(),
        <String>{'c', 'd'},
      );
    });

    test('filters combine, and combine with search', () {
      const LessonQuery q = LessonQuery(
        classNumber: 1,
        subject: ClassroomSubject.numeracy,
        download: DownloadFilter.downloaded,
      );
      expect(idsOf(q.apply(cards)), <String>['a']);

      expect(
        idsOf(q.copyWith(search: 'count').apply(cards)),
        <String>['a'],
      );
      expect(q.copyWith(search: 'swar').apply(cards), isEmpty);
    });

    test('counts the active filters, ignoring search', () {
      const LessonQuery q = LessonQuery(
        search: 'count',
        classNumber: 1,
        subject: ClassroomSubject.numeracy,
      );
      expect(q.activeFilterCount, 2);
      expect(q.hasSearch, isTrue);
    });

    test('clearing keeps the search and the sort', () {
      const LessonQuery q = LessonQuery(
        search: 'count',
        classNumber: 2,
        subject: ClassroomSubject.numeracy,
        completion: CompletionFilter.completed,
        download: DownloadFilter.downloaded,
        sort: LessonSort.titleAsc,
      );
      final LessonQuery cleared = q.cleared();

      expect(cleared.activeFilterCount, 0);
      expect(cleared.search, 'count');
      expect(cleared.sort, LessonSort.titleAsc);
    });
  });

  group('sorting', () {
    test('newest and oldest', () {
      expect(
        idsOf(const LessonQuery(sort: LessonSort.newest).apply(cards)),
        <String>['a', 'b', 'c', 'd'],
      );
      expect(
        idsOf(const LessonQuery(sort: LessonSort.oldest).apply(cards)),
        <String>['d', 'c', 'b', 'a'],
      );
    });

    test('A–Z and Z–A', () {
      expect(
        idsOf(const LessonQuery(sort: LessonSort.titleAsc).apply(cards)),
        <String>['c', 'a', 'b', 'd'],
      );
      expect(
        idsOf(const LessonQuery(sort: LessonSort.titleDesc).apply(cards)),
        <String>['d', 'b', 'a', 'c'],
      );
    });

    test('most and least completed', () {
      expect(
        idsOf(const LessonQuery(sort: LessonSort.mostCompleted).apply(cards)),
        <String>['b', 'a', 'd', 'c'],
      );
      expect(
        idsOf(const LessonQuery(sort: LessonSort.leastCompleted).apply(cards)),
        <String>['c', 'd', 'a', 'b'],
      );
    });

    test('shortest and longest', () {
      expect(
        idsOf(const LessonQuery(sort: LessonSort.shortest).apply(cards)),
        <String>['d', 'a', 'b', 'c'],
      );
      expect(
        idsOf(const LessonQuery(sort: LessonSort.longest).apply(cards)),
        <String>['c', 'b', 'a', 'd'],
      );
    });
  });

  group('Lesson model', () {
    test('round-trips through JSON', () {
      final Lesson lesson = testLesson(id: 'x', title: 'Shapes');
      final Lesson decoded = Lesson.fromJson(lesson.toJson());

      expect(decoded.id, lesson.id);
      expect(decoded.title, lesson.title);
      expect(decoded.subject, lesson.subject);
      expect(decoded.createdAt, lesson.createdAt);
    });

    test('the language pair comes from the classroom, not the lesson', () {
      final Lesson lesson = testLesson(id: 'x', title: 'Shapes');
      expect(
        lesson.languagePairFor(testClassroom()),
        'Hindi → Santali',
      );
      expect(
        lesson.languagePairFor(
          testClassroom(
            medium: TeachingMedium.english,
            target: TargetLanguage.mundari,
          ),
        ),
        'English → Mundari',
      );
      expect(lesson.languagePairFor(null), '');
    });

    test('the action label follows progress', () {
      LessonCard card(int percent) => LessonCard(
            lesson: testLesson(id: 'x', title: 'X'),
            completionPercentage: percent,
            download: DownloadState.downloaded,
          );

      expect(card(0).actionLabel, 'Start');
      expect(card(1).actionLabel, 'Continue');
      expect(card(60).actionLabel, 'Continue');
      expect(card(100).actionLabel, 'Review');
    });
  });

  group('recommendations', () {
    test('rank the teacher\'s own class and unfinished work first', () async {
      const RuleBasedRecommendationRepository ranker =
          RuleBasedRecommendationRepository();

      final List<LessonCard> result = await ranker.recommend(
        catalogue: cards,
        classroom: testClassroom(),
      );

      expect(result, isNotEmpty);
      expect(result.first.lesson.classNumber, 1);
      expect(result.every((LessonCard c) => c.recommended), isTrue);
      // A finished lesson is never recommended.
      expect(result.any((LessonCard c) => c.completed), isFalse);
    });

    test('follow the classroom when the class changes', () async {
      const RuleBasedRecommendationRepository ranker =
          RuleBasedRecommendationRepository();

      final List<LessonCard> result = await ranker.recommend(
        catalogue: cards,
        classroom: testClassroom(classLevel: 2),
      );
      expect(result.first.lesson.classNumber, 2);
    });
  });

  group('bundled catalogue', () {
    test('covers every state the library has to render', () {
      final List<Lesson> lessons = MockLessons.all();
      final Map<String, int> progress = MockLessons.seedProgress();
      final Set<String> downloaded = MockLessons.seedDownloaded();

      expect(lessons.length, greaterThanOrEqualTo(10));
      expect(
        lessons.map((Lesson l) => l.classNumber).toSet().length,
        greaterThanOrEqualTo(4),
      );
      expect(
        lessons.map((Lesson l) => l.subject).toSet(),
        ClassroomSubject.values.toSet(),
      );
      expect(progress.values.any((int p) => p == 0), isTrue);
      expect(progress.values.any((int p) => p == 100), isTrue);
      expect(progress.values.any((int p) => p > 0 && p < 100), isTrue);
      expect(downloaded, isNotEmpty);
      expect(
        lessons.any((Lesson l) => !downloaded.contains(l.id)),
        isTrue,
        reason: 'the Not Downloaded filter needs something to find',
      );
      // Ids are unique, or Home and the library could disagree.
      expect(lessons.map((Lesson l) => l.id).toSet().length, lessons.length);
    });
  });
}
