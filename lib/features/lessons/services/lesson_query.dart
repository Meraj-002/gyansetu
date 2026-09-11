import '../../../models/lesson.dart';
import '../../setup/models/classroom_setup.dart';

/// Progress filter.
enum CompletionFilter {
  all('All'),
  notStarted('Not Started'),
  inProgress('In Progress'),
  completed('Completed');

  const CompletionFilter(this.label);

  final String label;
}

/// Offline-availability filter.
enum DownloadFilter {
  all('All'),
  downloaded('Downloaded'),
  notDownloaded('Not Downloaded');

  const DownloadFilter(this.label);

  final String label;
}

/// How the list is ordered.
enum LessonSort {
  newest('Newest'),
  oldest('Oldest'),
  titleAsc('A–Z'),
  titleDesc('Z–A'),
  mostCompleted('Most Completed'),
  leastCompleted('Least Completed'),
  shortest('Shortest'),
  longest('Longest');

  const LessonSort(this.label);

  final String label;
}

/// Everything the library is currently narrowed by.
///
/// A plain value object, kept out of the widgets so the search-and-filter rules
/// can be tested without pumping a screen.
class LessonQuery {
  const LessonQuery({
    this.search = '',
    this.classNumber,
    this.subject,
    this.completion = CompletionFilter.all,
    this.download = DownloadFilter.all,
    this.sort = LessonSort.newest,
  });

  final String search;

  /// Null means every class.
  final int? classNumber;

  /// Null means every subject.
  final ClassroomSubject? subject;

  final CompletionFilter completion;
  final DownloadFilter download;
  final LessonSort sort;

  /// How many filters are narrowing the list. Search is counted separately, so
  /// the Filters button reports only what the filter sheet controls.
  int get activeFilterCount =>
      (classNumber != null ? 1 : 0) +
      (subject != null ? 1 : 0) +
      (completion != CompletionFilter.all ? 1 : 0) +
      (download != DownloadFilter.all ? 1 : 0);

  bool get hasAnyFilter => activeFilterCount > 0;
  bool get hasSearch => search.trim().isNotEmpty;

  LessonQuery copyWith({
    String? search,
    int? classNumber,
    ClassroomSubject? subject,
    CompletionFilter? completion,
    DownloadFilter? download,
    LessonSort? sort,
    bool clearClass = false,
    bool clearSubject = false,
  }) {
    return LessonQuery(
      search: search ?? this.search,
      classNumber: clearClass ? null : (classNumber ?? this.classNumber),
      subject: clearSubject ? null : (subject ?? this.subject),
      completion: completion ?? this.completion,
      download: download ?? this.download,
      sort: sort ?? this.sort,
    );
  }

  /// Clears the filters but keeps the search text and the chosen sort, which
  /// the teacher did not ask to reset.
  LessonQuery cleared() => LessonQuery(search: search, sort: sort);

  /// Applies the search, then the filters, then the sort.
  List<LessonCard> apply(List<LessonCard> cards) {
    final String needle = search.trim().toLowerCase();

    final List<LessonCard> filtered = cards.where((LessonCard card) {
      if (needle.isNotEmpty && !card.lesson.searchIndex.contains(needle)) {
        return false;
      }
      if (classNumber != null && card.lesson.classNumber != classNumber) {
        return false;
      }
      if (subject != null && card.lesson.subject != subject) return false;

      final bool completionOk = switch (completion) {
        CompletionFilter.all => true,
        CompletionFilter.notStarted => card.notStarted,
        CompletionFilter.inProgress => card.inProgress,
        CompletionFilter.completed => card.completed,
      };
      if (!completionOk) return false;

      return switch (download) {
        DownloadFilter.all => true,
        DownloadFilter.downloaded => card.downloaded,
        DownloadFilter.notDownloaded => !card.downloaded,
      };
    }).toList();

    filtered.sort(_comparator);
    return filtered;
  }

  int Function(LessonCard, LessonCard) get _comparator => switch (sort) {
        LessonSort.newest => (LessonCard a, LessonCard b) =>
            b.lesson.createdAt.compareTo(a.lesson.createdAt),
        LessonSort.oldest => (LessonCard a, LessonCard b) =>
            a.lesson.createdAt.compareTo(b.lesson.createdAt),
        LessonSort.titleAsc => (LessonCard a, LessonCard b) => a.lesson.title
            .toLowerCase()
            .compareTo(b.lesson.title.toLowerCase()),
        LessonSort.titleDesc => (LessonCard a, LessonCard b) => b.lesson.title
            .toLowerCase()
            .compareTo(a.lesson.title.toLowerCase()),
        LessonSort.mostCompleted => (LessonCard a, LessonCard b) =>
            b.completionPercentage.compareTo(a.completionPercentage),
        LessonSort.leastCompleted => (LessonCard a, LessonCard b) =>
            a.completionPercentage.compareTo(b.completionPercentage),
        LessonSort.shortest => (LessonCard a, LessonCard b) =>
            a.lesson.durationMinutes.compareTo(b.lesson.durationMinutes),
        LessonSort.longest => (LessonCard a, LessonCard b) =>
            b.lesson.durationMinutes.compareTo(a.lesson.durationMinutes),
      };
}
