import '../../setup/models/classroom_setup.dart';
import 'conversation_turn.dart';
import 'voice_pipeline_metrics.dart';

/// Where a saved session has got to on its way to the server.
enum SessionSyncStatus {
  /// On this device and nowhere else. Perfectly usable.
  localOnly(label: 'Saved offline'),

  /// Saved and waiting for the next sync run.
  pendingSync(label: 'Waiting to sync'),

  synced(label: 'Synced'),

  syncFailed(label: 'Sync failed');

  const SessionSyncStatus({required this.label});

  final String label;

  static SessionSyncStatus byName(String? name) {
    for (final SessionSyncStatus v in values) {
      if (v.name == name) return v;
    }
    return SessionSyncStatus.localOnly;
  }
}

/// How much of a session ran with no connection.
enum SessionConnectivity {
  /// Every turn ran offline.
  offline(label: 'Active'),

  /// Some turns offline, some not.
  partial(label: 'Partial'),

  /// Every turn had a connection.
  online(label: 'Online'),

  /// Nothing was recorded, so nothing can be claimed.
  unknown(label: 'Unavailable');

  const SessionConnectivity({required this.label});

  final String label;
}

/// One live teaching session, from opening the screen to ending it.
class ClassroomSession {
  const ClassroomSession({
    required this.sessionId,
    required this.lessonId,
    required this.classNumber,
    required this.teachingLanguage,
    required this.targetLanguage,
    required this.startedAt,
    this.teacherId,
    this.lessonTitle = '',
    this.subject = ClassroomSubject.numeracy,
    this.turns = const <ConversationTurn>[],
    this.endedAt,
    this.completed = false,
    this.savedAt,
    this.syncStatus = SessionSyncStatus.localOnly,
  });

  factory ClassroomSession.fromJson(Map<String, dynamic> json) =>
      ClassroomSession(
        sessionId: json['sessionId'] as String,
        lessonId: json['lessonId'] as String,
        classNumber: json['classNumber'] as int,
        teachingLanguage: json['teachingLanguage'] as String,
        targetLanguage: json['targetLanguage'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        teacherId: json['teacherId'] as String?,
        lessonTitle: json['lessonTitle'] as String? ?? '',
        subject: ClassroomSubject.byName(json['subject'] as String?) ??
            ClassroomSubject.numeracy,
        turns: <ConversationTurn>[
          for (final dynamic t
              in json['turns'] as List<dynamic>? ?? const <dynamic>[])
            ConversationTurn.fromJson(t as Map<String, dynamic>),
        ],
        endedAt: json['endedAt'] == null
            ? null
            : DateTime.parse(json['endedAt'] as String),
        completed: json['completed'] as bool? ?? false,
        savedAt: json['savedAt'] == null
            ? null
            : DateTime.parse(json['savedAt'] as String),
        syncStatus: SessionSyncStatus.byName(json['syncStatus'] as String?),
      );

  final String sessionId;
  final String lessonId;
  final String lessonTitle;

  /// Null when the device has no signed-in teacher; the session is still valid.
  final String? teacherId;

  final int classNumber;

  /// Part of the classroom context, and part of what an insight is allowed to
  /// reason about.
  final ClassroomSubject subject;

  /// Locale ids, so a saved session still reads correctly if the language list
  /// changes.
  final String teachingLanguage;
  final String targetLanguage;

  final DateTime startedAt;
  final DateTime? endedAt;
  final List<ConversationTurn> turns;

  /// True once the session was ended deliberately rather than abandoned.
  final bool completed;

  /// When the teacher explicitly saved it. Null means the session was only
  /// written automatically as it ran, which is still on the device.
  final DateTime? savedAt;

  final SessionSyncStatus syncStatus;

  bool get isSaved => savedAt != null;

  int get totalTurns => turns.length;

  /// Turns that got all the way to audio. This is what "interactions" counts:
  /// a turn that failed at translation was not an interaction with the class.
  List<ConversationTurn> get completedTurns => turns
      .where(
        (ConversationTurn t) =>
            t.status == TurnStatus.ready || t.status == TurnStatus.played,
      )
      .toList(growable: false);

  int get interactionsCompleted => completedTurns.length;

  int get studentTurns =>
      turns.where((ConversationTurn t) => t.speaker == TurnSpeaker.student).length;

  int get teacherTurns =>
      turns.where((ConversationTurn t) => t.speaker == TurnSpeaker.teacher).length;

  /// What share of turns ran with no connection, 0..100. Null when there is
  /// nothing to measure.
  int? get offlinePercentage {
    if (turns.isEmpty) return null;
    final int offline =
        turns.where((ConversationTurn t) => t.wasOffline).length;
    return ((offline / turns.length) * 100).round();
  }

  SessionConnectivity get connectivity {
    final int? percentage = offlinePercentage;
    if (percentage == null) return SessionConnectivity.unknown;
    if (percentage >= 100) return SessionConnectivity.offline;
    if (percentage <= 0) return SessionConnectivity.online;
    return SessionConnectivity.partial;
  }

  /// Turns that reached audio, and so have a measured pipeline latency.
  List<ConversationTurn> get measuredTurns => turns
      .where((ConversationTurn t) => t.metrics != null)
      .toList(growable: false);

  int get translationCount => turns
      .where((ConversationTurn t) => (t.translatedText ?? '').isNotEmpty)
      .length;

  int get errorCount =>
      turns.where((ConversationTurn t) => t.status == TurnStatus.failed).length;

  /// Null when nothing has been measured. Never zero-as-unknown: a session
  /// with no completed turn has no average, and the UI says so.
  Duration? get averageLatency {
    final List<ConversationTurn> measured = measuredTurns;
    if (measured.isEmpty) return null;
    final int total = measured.fold<int>(
      0,
      (int sum, ConversationTurn t) => sum + t.metrics!.totalDuration.inMilliseconds,
    );
    return Duration(milliseconds: total ~/ measured.length);
  }

  Duration? get fastestLatency => _extreme(fastest: true);

  Duration? get slowestLatency => _extreme(fastest: false);

  Duration? _extreme({required bool fastest}) {
    final List<ConversationTurn> measured = measuredTurns;
    if (measured.isEmpty) return null;
    Duration best = measured.first.metrics!.totalDuration;
    for (final ConversationTurn turn in measured.skip(1)) {
      final Duration value = turn.metrics!.totalDuration;
      if (fastest ? value < best : value > best) best = value;
    }
    return best;
  }

  /// True when any measured turn was served by a development adapter, so the
  /// summary can say the figures are not a real model's.
  bool get usedMocks =>
      measuredTurns.any((ConversationTurn t) => t.metrics!.measuredWithMocks);

  int get turnsWithinTarget => measuredTurns
      .where((ConversationTurn t) => t.metrics!.withinTarget)
      .length;

  Duration get duration =>
      (endedAt ?? DateTime.now()).difference(startedAt);

  /// mm:ss for a short session, hh:mm:ss once it passes an hour.
  String get durationLabel {
    final Duration value = duration;
    final String minutes =
        value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final String seconds =
        value.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (value.inHours > 0) return '${value.inHours}:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  /// The documented session id format: CLS-ddMMyy-HHmm.
  static String idFor(DateTime startedAt) {
    String two(int value) => value.toString().padLeft(2, '0');
    final String date =
        '${two(startedAt.day)}${two(startedAt.month)}${two(startedAt.year % 100)}';
    return 'CLS-$date-${two(startedAt.hour)}${two(startedAt.minute)}';
  }

  ClassroomSession copyWith({
    List<ConversationTurn>? turns,
    DateTime? endedAt,
    bool? completed,
    DateTime? savedAt,
    SessionSyncStatus? syncStatus,
  }) =>
      ClassroomSession(
        sessionId: sessionId,
        lessonId: lessonId,
        lessonTitle: lessonTitle,
        teacherId: teacherId,
        classNumber: classNumber,
        teachingLanguage: teachingLanguage,
        targetLanguage: targetLanguage,
        subject: subject,
        startedAt: startedAt,
        turns: turns ?? this.turns,
        endedAt: endedAt ?? this.endedAt,
        completed: completed ?? this.completed,
        savedAt: savedAt ?? this.savedAt,
        syncStatus: syncStatus ?? this.syncStatus,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'sessionId': sessionId,
        'lessonId': lessonId,
        'lessonTitle': lessonTitle,
        'teacherId': teacherId,
        'classNumber': classNumber,
        'subject': subject.name,
        'teachingLanguage': teachingLanguage,
        'targetLanguage': targetLanguage,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'completed': completed,
        'savedAt': savedAt?.toIso8601String(),
        'syncStatus': syncStatus.name,
        'turns': <Map<String, dynamic>>[
          for (final ConversationTurn t in turns) t.toJson(),
        ],
      };
}

/// What the result screen is handed when a session ends.
class SessionSummary {
  const SessionSummary({
    required this.sessionId,
    required this.lessonId,
    required this.lessonTitle,
    required this.targetLanguage,
    required this.totalTurns,
    required this.translationCount,
    required this.errorCount,
    required this.turnsWithinTarget,
    required this.measuredCount,
    required this.duration,
    this.averageLatency,
    this.fastestLatency,
    this.slowestLatency,
    this.usedMocks = false,
  });

  factory SessionSummary.of(ClassroomSession session) => SessionSummary(
        sessionId: session.sessionId,
        lessonId: session.lessonId,
        lessonTitle: session.lessonTitle,
        targetLanguage: session.targetLanguage,
        totalTurns: session.totalTurns,
        translationCount: session.translationCount,
        errorCount: session.errorCount,
        turnsWithinTarget: session.turnsWithinTarget,
        measuredCount: session.measuredTurns.length,
        duration: session.duration,
        averageLatency: session.averageLatency,
        fastestLatency: session.fastestLatency,
        slowestLatency: session.slowestLatency,
        usedMocks: session.usedMocks,
      );

  final String sessionId;
  final String lessonId;
  final String lessonTitle;
  final String targetLanguage;
  final int totalTurns;
  final int translationCount;
  final int errorCount;

  /// How many measured turns came in under [VoicePipelineMetrics.target].
  final int turnsWithinTarget;

  final int measuredCount;
  final Duration duration;
  final Duration? averageLatency;
  final Duration? fastestLatency;
  final Duration? slowestLatency;
  final bool usedMocks;

  static String format(Duration? value) => value == null
      ? '—'
      : '${(value.inMilliseconds / 1000).toStringAsFixed(1)} sec';
}
