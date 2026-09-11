import '../../../models/student_progress.dart';
import '../../setup/models/classroom_setup.dart';

/// A period the insights are calculated over.
///
/// Weeks run Monday to Sunday, which is how a school timetable runs.
enum InsightPeriod {
  thisWeek(label: 'This Week'),
  lastWeek(label: 'Last Week'),
  custom(label: 'Custom Range');

  const InsightPeriod({required this.label});

  final String label;

  static InsightPeriod? byName(String? name) {
    for (final InsightPeriod v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// Two dates, inclusive of both ends at day resolution.
class DateRange {
  const DateRange({required this.start, required this.end});

  /// The Monday-to-Sunday week containing [on].
  factory DateRange.weekOf(DateTime on) {
    final DateTime day = DateTime(on.year, on.month, on.day);
    final DateTime monday = day.subtract(Duration(days: day.weekday - 1));
    return DateRange(
      start: monday,
      end: monday.add(const Duration(days: 6)),
    );
  }

  final DateTime start;
  final DateTime end;

  /// The instant after the last moment of [end], so a comparison never has to
  /// worry about the time of day an event was recorded.
  DateTime get exclusiveEnd => DateTime(
        end.year,
        end.month,
        end.day,
      ).add(const Duration(days: 1));

  bool contains(DateTime at) => !at.isBefore(start) && at.isBefore(exclusiveEnd);

  /// The same length of time, immediately before this one. Used for the
  /// "compared with" figures, so an improvement is measured rather than
  /// invented.
  DateRange get previous {
    final int days = end.difference(start).inDays + 1;
    return DateRange(
      start: start.subtract(Duration(days: days)),
      end: start.subtract(const Duration(days: 1)),
    );
  }

  /// "20 – 26 May 2025", collapsing the month and year where they match.
  String get label {
    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final String startMonth = months[start.month - 1];
    final String endMonth = months[end.month - 1];

    if (start.year == end.year && start.month == end.month) {
      return '${start.day} – ${end.day} $endMonth ${end.year}';
    }
    if (start.year == end.year) {
      return '${start.day} $startMonth – ${end.day} $endMonth ${end.year}';
    }
    return '${start.day} $startMonth ${start.year} – '
        '${end.day} $endMonth ${end.year}';
  }

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// A change between this period and the one before it.
///
/// [amount] is null when there is nothing to compare against — the first week
/// a teacher uses the app has no previous week, and saying "0%" would read as
/// "no progress" rather than "not known yet".
class InsightDelta {
  const InsightDelta({required this.amount, required this.unit});

  const InsightDelta.unknown()
      : amount = null,
        unit = '';

  final num? amount;

  /// '%' or '' — what follows the number.
  final String unit;

  bool get known => amount != null;

  bool get isUp => (amount ?? 0) > 0;

  bool get isFlat => amount == 0;

  /// "8% this week", "3 this week", "no change this week", or "first period
  /// recorded" when there is nothing behind it.
  String labelFor(String periodWord) {
    final num? value = amount;
    if (value == null) return 'No earlier $periodWord to compare';
    if (value == 0) return 'No change this $periodWord';
    final String sign = value > 0 ? '' : '−';
    final num size = value.abs();
    return '$sign$size$unit this $periodWord';
  }
}

/// One of the four figures across the top.
class InsightStat {
  const InsightStat({
    required this.kind,
    required this.value,
    required this.delta,
    this.suffix = '',
  });

  final InsightStatKind kind;

  /// Null when nothing has been recorded that could produce this figure. The
  /// card shows a dash, never a zero that looks like a measurement.
  final int? value;

  final InsightDelta delta;
  final String suffix;

  String get display => value == null ? '--' : '$value$suffix';
}

enum InsightStatKind {
  learningProgress(label: 'Learning Progress'),
  lessonsCompleted(label: 'Lessons Completed'),
  assessments(label: 'Assessments'),
  engagement(label: 'Engagement');

  const InsightStatKind({required this.label});

  final String label;
}

/// The three things the overview is broken down by.
enum LearningArea {
  foundationalLiteracy(
    label: 'Foundational Literacy',
    blurb: 'Children can recognise letters and common words.',
  ),
  numeracy(
    label: 'Numeracy',
    blurb: 'Children can count and understand numbers.',
  ),
  languageUnderstanding(
    label: 'Language Understanding',
    blurb: 'Children understand and respond in their language.',
  );

  const LearningArea({required this.label, required this.blurb});

  final String label;
  final String blurb;
}

/// Where the class stands in one learning area.
class LearningAreaInsight {
  const LearningAreaInsight({
    required this.area,
    required this.percentage,
    required this.improvement,
    required this.basis,
  });

  const LearningAreaInsight.noData(this.area, {required this.basis})
      : percentage = null,
        improvement = const InsightDelta.unknown();

  final LearningArea area;

  /// Null when nothing has been recorded for this area. Shown as "No data yet"
  /// rather than 0%.
  final int? percentage;

  final InsightDelta improvement;

  /// One line naming what the figure was worked out from, shown in the
  /// "How is this calculated?" sheet.
  final String basis;

  bool get hasData => percentage != null;

  /// The words on the ring. Deliberately coarse: a percentage from a handful of
  /// lessons does not support finer grading than this.
  String get band => switch (percentage) {
        null => 'No data yet',
        final int p when p >= 80 => 'Proficient',
        final int p when p >= 60 => 'Developing',
        final int p when p >= 40 => 'Emerging',
        _ => 'Needs support',
      };
}

/// A concept the class is struggling with, and who is struggling with it.
class AttentionGroup {
  const AttentionGroup({
    required this.concept,
    required this.students,
    required this.headline,
    required this.detail,
    this.lessonId,
  });

  /// The concept label, matching the assessment's own concept names.
  final String concept;

  /// The children this applies to. Empty when there is no roster, in which
  /// case the group is reported at class level instead of naming anybody.
  final List<StudentProgress> students;

  final String headline;
  final String detail;

  /// The lesson that teaches this concept, when one does.
  final String? lessonId;

  int get count => students.length;
}

/// Everything the Learning Insights screen shows, worked out in one place.
class LearningInsights {
  const LearningInsights({
    required this.range,
    required this.period,
    required this.classroom,
    required this.studentCount,
    required this.stats,
    required this.areas,
    required this.attention,
    required this.eventsInRange,
    required this.usesPrototypeStudents,
  });

  final DateRange range;
  final InsightPeriod period;

  /// Null when the teacher has not finished classroom setup.
  final ClassroomSetup? classroom;

  /// Null when no roster exists. The class selector then says so instead of
  /// showing a made-up number.
  final int? studentCount;

  final List<InsightStat> stats;
  final List<LearningAreaInsight> areas;

  /// The concepts needing work, worst first. Empty when nothing does.
  final List<AttentionGroup> attention;

  /// How many recorded events fall inside [range]. Zero drives the empty state.
  final int eventsInRange;

  /// True while the only pupil records available are the prototype class. The
  /// screen must say so wherever it names or counts children.
  final bool usesPrototypeStudents;

  bool get hasActivityInRange => eventsInRange > 0;

  /// True when something has actually been recorded, which is a different
  /// message from "nothing this week".
  ///
  /// A lesson sitting at 0% is not history: the area has a figure, but nobody
  /// has done anything yet.
  bool get hasAnyHistory =>
      stats.any((InsightStat s) => (s.value ?? 0) > 0) ||
      areas.any((LearningAreaInsight a) => (a.percentage ?? 0) > 0);

  InsightStat statFor(InsightStatKind kind) =>
      stats.firstWhere((InsightStat s) => s.kind == kind);

  LearningAreaInsight? areaFor(LearningArea area) {
    for (final LearningAreaInsight a in areas) {
      if (a.area == area) return a;
    }
    return null;
  }

  /// The concept most in need of work, or null when none is.
  AttentionGroup? get weakest => attention.isEmpty ? null : attention.first;
}
