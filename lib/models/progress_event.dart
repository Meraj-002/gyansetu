/// Something a teacher actually did, with the time it happened.
///
/// The app already stores *state* — how far a lesson got, the latest assessment
/// result, saved classroom sessions. What none of that carries is a timestamp
/// for lesson completion, and without one there is no way to answer "what
/// happened this week". This log fills that gap and nothing more: it is not a
/// second copy of the lesson or assessment stores, and analytics reads both.
enum ProgressEventType {
  lessonStarted(label: 'Lesson started'),
  lessonCompleted(label: 'Lesson completed'),
  assessmentStarted(label: 'Assessment started'),
  assessmentCompleted(label: 'Assessment completed'),
  classroomSessionCompleted(label: 'Live classroom session'),
  flashcardViewed(label: 'Flashcard viewed'),
  flashcardCompleted(label: 'Flashcard deck finished'),
  worksheetGenerated(label: 'Worksheet created'),
  worksheetCompleted(label: 'Worksheet used');

  const ProgressEventType({required this.label});

  final String label;

  /// True for the events that count as a teacher using the app with a class,
  /// which is what engagement is measured from.
  bool get isClassroomActivity => switch (this) {
        ProgressEventType.lessonCompleted ||
        ProgressEventType.assessmentCompleted ||
        ProgressEventType.classroomSessionCompleted ||
        ProgressEventType.flashcardCompleted ||
        ProgressEventType.worksheetCompleted =>
          true,
        _ => false,
      };

  static ProgressEventType? byName(String? name) {
    for (final ProgressEventType v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// One recorded event.
class ProgressEvent {
  const ProgressEvent({
    required this.id,
    required this.type,
    required this.occurredAt,
    this.lessonId,
    this.metadata = const <String, String>{},
  });

  factory ProgressEvent.fromJson(Map<String, dynamic> json) => ProgressEvent(
        id: json['id'] as String,
        type: ProgressEventType.byName(json['type'] as String?) ??
            ProgressEventType.lessonStarted,
        occurredAt: DateTime.tryParse(json['occurredAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        lessonId: json['lessonId'] as String?,
        metadata: <String, String>{
          for (final MapEntry<String, dynamic> e
              in (json['metadata'] as Map<String, dynamic>? ??
                      const <String, dynamic>{})
                  .entries)
            e.key: '${e.value}',
        },
      );

  /// Stable within the log. Built from the type, the lesson and the time, so
  /// recording the same thing twice in the same second cannot double-count it.
  factory ProgressEvent.of({
    required ProgressEventType type,
    required DateTime occurredAt,
    String? lessonId,
    Map<String, String> metadata = const <String, String>{},
  }) =>
      ProgressEvent(
        id: '${type.name}#${lessonId ?? '-'}#'
            '${occurredAt.toIso8601String().split('.').first}',
        type: type,
        occurredAt: occurredAt,
        lessonId: lessonId,
        metadata: metadata,
      );

  final String id;
  final ProgressEventType type;
  final DateTime occurredAt;

  /// The lesson this happened in, when there was one.
  final String? lessonId;

  /// Small extra facts — a score, a category, a session id. Strings only, so
  /// the log stays readable and a schema change cannot corrupt it.
  final Map<String, String> metadata;

  /// Reads a whole number out of [metadata], or null when it is absent or not
  /// a number. Never a default that would be mistaken for a real figure.
  int? intValue(String key) {
    final String? raw = metadata[key];
    return raw == null ? null : int.tryParse(raw);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type.name,
        'occurredAt': occurredAt.toIso8601String(),
        if (lessonId != null) 'lessonId': lessonId,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };
}
