// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:convert';

import '../../../core/utils/app_logger.dart';
import '../../../models/lesson.dart';
import '../../../models/lesson_plan.dart';
import '../../../services/storage/secure_storage_service.dart';
import '../models/classroom_insights.dart';
import '../models/classroom_session.dart';

/// Turns a finished session into something a teacher can act on.
///
/// An interface because the useful version of this is a model reasoning over
/// the conversation, the lesson and the assessment. What ships today is a set
/// of deterministic rules, and it says so: [ClassroomInsights.fromRules] is
/// true, and nothing in the UI calls the output AI.
abstract interface class ClassroomInsightService {
  /// Insights for a session. Computed once and cached, because recomputing on
  /// every rebuild is wasted work on a 2 GB phone.
  Future<ClassroomInsights> generateInsights({
    required ClassroomSession session,
    Lesson? lesson,
    QuickAssessment? assessment,
    AssessmentResult? result,
  });

  /// What was worked out before, if anything.
  Future<ClassroomInsights?> cached(String sessionId);
}

/// Local rules over what the session actually recorded.
///
/// NOT AI. Every number below is counted or looked up:
///
///   interactions        = turns that reached audio
///   engagement          = how many pupil turns there were against teacher turns
///   concepts            = the lesson's own concept list
///   needs reinforcement = concepts behind assessment questions marked "not yet"
///
/// Where the evidence is missing the field stays null. A session with no
/// assessment reports `null` reinforcement concepts, not zero, because "nobody
/// checked" and "nothing needs work" are different things to tell a teacher.
class LocalRuleBasedInsightService implements ClassroomInsightService {
  LocalRuleBasedInsightService(this._storage);

  static const String _keyPrefix = 'classroom.insights.';

  final SecureStorageService _storage;

  final Map<String, ClassroomInsights> _memory =
      <String, ClassroomInsights>{};

  @override
  Future<ClassroomInsights?> cached(String sessionId) async {
    final ClassroomInsights? held = _memory[sessionId];
    if (held != null) return held;

    final String? raw = await _storage.read('$_keyPrefix$sessionId');
    if (raw == null || raw.isEmpty) return null;
    try {
      final ClassroomInsights value = ClassroomInsights.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      return _memory[sessionId] = value;
    } on Object catch (error) {
      AppLogger.error('cached insights could not be read', error: error);
      await _storage.delete('$_keyPrefix$sessionId');
      return null;
    }
  }

  @override
  Future<ClassroomInsights> generateInsights({
    required ClassroomSession session,
    Lesson? lesson,
    QuickAssessment? assessment,
    AssessmentResult? result,
  }) async {
    final ClassroomInsights? saved = await cached(session.sessionId);
    // A cached answer is only reused while the evidence behind it has not
    // grown: running the assessment after the session must change the insights.
    if (saved != null &&
        saved.interactionsCompleted == session.interactionsCompleted &&
        saved.assessedQuestionCount == (result?.total ?? 0)) {
      return saved;
    }

    final ClassroomInsights insights = _compute(
      session: session,
      lesson: lesson,
      assessment: assessment,
      result: result,
    );
    _memory[session.sessionId] = insights;
    try {
      await _storage.write(
        '$_keyPrefix${session.sessionId}',
        jsonEncode(insights.toJson()),
      );
    } on Object catch (error) {
      // Insights are cheap to recompute; failing to cache them is not worth
      // interrupting the teacher over.
      AppLogger.error('insights could not be cached', error: error);
    }
    return insights;
  }

  ClassroomInsights _compute({
    required ClassroomSession session,
    Lesson? lesson,
    QuickAssessment? assessment,
    AssessmentResult? result,
  }) {
    final EngagementLevel engagement = _engagement(session);
    final List<ConceptOutcome> concepts = _concepts(
      lesson: lesson,
      assessment: assessment,
      result: result,
    );

    final int? needing = result == null
        ? null
        : concepts
            .where(
              (ConceptOutcome c) =>
                  c.status == ConceptStatus.needsReinforcement,
            )
            .length;

    return ClassroomInsights(
      interactionsCompleted: session.interactionsCompleted,
      engagement: engagement,
      concepts: concepts,
      conceptsNeedingReinforcement: needing,
      recommendation: _recommendation(
        session: session,
        engagement: engagement,
        needing: needing,
      ),
      assessedQuestionCount: result?.total ?? 0,
      generatedAt: DateTime.now(),
    );
  }

  /// Read from pupil turns against teacher turns. A class where nobody was
  /// asked to speak is reported as unknown, not as quiet.
  static EngagementLevel _engagement(ClassroomSession session) {
    if (session.turns.isEmpty) return EngagementLevel.unknown;

    final int students = session.studentTurns;
    final int teachers = session.teacherTurns;
    if (teachers == 0 && students == 0) return EngagementLevel.unknown;
    if (students == 0) return EngagementLevel.quiet;

    // A pupil answering most of what the teacher asked is active
    // participation; a couple of answers across many prompts is some.
    final double ratio = teachers == 0 ? 1 : students / teachers;
    return ratio >= 0.5 ? EngagementLevel.active : EngagementLevel.some;
  }

  /// The lesson's own concepts, with the status the evidence supports.
  static List<ConceptOutcome> _concepts({
    Lesson? lesson,
    QuickAssessment? assessment,
    AssessmentResult? result,
  }) {
    final List<String> named = lesson?.concepts ?? const <String>[];
    if (named.isEmpty) return const <ConceptOutcome>[];

    if (assessment == null || result == null) {
      // Nothing has checked these, so they are only "discussed".
      return <ConceptOutcome>[
        for (final String concept in named)
          ConceptOutcome(concept: concept, status: ConceptStatus.discussed),
      ];
    }

    final Set<String> failed = <String>{};
    final Set<String> passed = <String>{};
    for (final AssessmentQuestion question in assessment.questions) {
      final String? concept = question.concept;
      if (concept == null) continue;
      final AssessmentOutcome? outcome = result.outcomes[question.id];
      if (outcome == null) continue;
      if (outcome == AssessmentOutcome.achieved) {
        passed.add(concept);
      } else {
        failed.add(concept);
      }
    }

    return <ConceptOutcome>[
      for (final String concept in named)
        ConceptOutcome(
          concept: concept,
          // A concept that failed anywhere needs work, even if it also passed
          // elsewhere: the safer reading is the one that gets it retaught.
          status: failed.contains(concept)
              ? ConceptStatus.needsReinforcement
              : (passed.contains(concept)
                  ? ConceptStatus.completed
                  : ConceptStatus.discussed),
        ),
    ];
  }

  /// One short next step, only where the evidence supports one.
  static String? _recommendation({
    required ClassroomSession session,
    required EngagementLevel engagement,
    int? needing,
  }) {
    if (session.interactionsCompleted == 0) return null;
    if (needing != null && needing > 0) {
      return 'Run the activity again for the concepts marked for '
          'reinforcement.';
    }
    if (needing == null) {
      return 'Run the quick assessment to see which concepts need more work.';
    }
    if (engagement == EngagementLevel.quiet) {
      return 'Try inviting two or three children to answer aloud next time.';
    }
    return null;
  }
}
