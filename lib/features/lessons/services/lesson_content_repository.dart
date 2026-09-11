// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:convert';

import '../../../core/utils/app_logger.dart';
import '../../../models/lesson.dart';
import '../../../models/lesson_plan.dart';
import '../../../services/storage/secure_storage_service.dart';
import '../../setup/models/classroom_setup.dart';
import 'ai_content_service.dart';

/// Why a lesson plan could not be produced.
enum PlanUnavailableReason { noContent, needsConnection, failed }

/// The body of a lesson: script, activity, assessment and tip.
///
/// Separate from [LessonRepository] because a plan and a catalogue entry have
/// different lifetimes. The catalogue is an index; the plan is generated or
/// authored content that is cached per device and versioned on its own.
abstract interface class LessonContentRepository {
  /// The plan for a lesson, or a reason there is none.
  Future<PlanResult> planFor(Lesson lesson, ClassroomSetup classroom);

  /// The cached plan only. Never reaches for a provider, so it is safe to call
  /// while offline and safe to call on first paint.
  Future<LessonPlan?> cachedPlan(String lessonId);
}

/// Outcome of asking for a plan.
sealed class PlanResult {
  const PlanResult();
}

final class PlanLoaded extends PlanResult {
  const PlanLoaded(this.plan, {this.fromCache = false});

  final LessonPlan plan;

  /// True when it came off the device rather than from the provider.
  final bool fromCache;
}

final class PlanUnavailable extends PlanResult {
  const PlanUnavailable(this.reason, this.message);

  final PlanUnavailableReason reason;
  final String message;
}

/// Cache first, provider second, and write back whatever the provider returns.
///
/// This ordering is what makes lesson detail work offline: once a plan has been
/// read even once, it is on the device and no connection is needed again.
class LocalLessonContentRepository implements LessonContentRepository {
  LocalLessonContentRepository({
    required AiContentService ai,
    required SecureStorageService storage,
  })  : _ai = ai,
        _storage = storage;

  static const String _keyPrefix = 'lessons.plan.';

  final AiContentService _ai;
  final SecureStorageService _storage;

  final Map<String, LessonPlan> _memory = <String, LessonPlan>{};

  @override
  Future<LessonPlan?> cachedPlan(String lessonId) async {
    final LessonPlan? held = _memory[lessonId];
    if (held != null) return held;

    final String? raw = await _storage.read('$_keyPrefix$lessonId');
    if (raw == null || raw.isEmpty) return null;
    try {
      final LessonPlan plan =
          LessonPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      return _memory[lessonId] = plan;
    } on Object catch (error) {
      // A cache that cannot be parsed is a cache miss, not a crash. It is
      // dropped so the next read replaces it cleanly.
      AppLogger.error('cached lesson plan could not be read', error: error);
      await _storage.delete('$_keyPrefix$lessonId');
      return null;
    }
  }

  @override
  Future<PlanResult> planFor(Lesson lesson, ClassroomSetup classroom) async {
    final LessonPlan? cached = await cachedPlan(lesson.id);
    if (cached != null) return PlanLoaded(cached, fromCache: true);

    final AiContentResult<LessonPlan> result =
        await _ai.generateLesson(lesson: lesson, classroom: classroom);

    return switch (result) {
      AiContent<LessonPlan>(:final LessonPlan value) => await _store(value),
      AiContentUnavailable<LessonPlan>(:final AiUnavailableReason reason) =>
        PlanUnavailable(_map(reason), _explain(reason)),
    };
  }

  Future<PlanResult> _store(LessonPlan plan) async {
    _memory[plan.lessonId] = plan;
    await _storage.write(
      '$_keyPrefix${plan.lessonId}',
      jsonEncode(plan.toJson()),
    );
    return PlanLoaded(plan);
  }

  static PlanUnavailableReason _map(AiUnavailableReason reason) =>
      switch (reason) {
        AiUnavailableReason.needsConnection =>
          PlanUnavailableReason.needsConnection,
        AiUnavailableReason.failed => PlanUnavailableReason.failed,
        AiUnavailableReason.notConfigured ||
        AiUnavailableReason.noContent =>
          PlanUnavailableReason.noContent,
      };

  /// Says what the teacher can do about it. Deliberately does not forward the
  /// service's own wording, which describes a provider rather than a classroom.
  static String _explain(AiUnavailableReason reason) =>
      switch (reason) {
        AiUnavailableReason.needsConnection =>
          'This lesson has not been prepared on this device yet. Connect once '
              'to download it.',
        AiUnavailableReason.failed => "Couldn't open this lesson right now.",
        AiUnavailableReason.notConfigured ||
        AiUnavailableReason.noContent =>
          "Lesson content isn't available for this lesson yet.",
      };
}
