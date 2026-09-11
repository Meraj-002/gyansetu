// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:convert';

import '../../../core/utils/app_logger.dart';
import '../../../models/lesson.dart';
import '../../../models/lesson_plan.dart';
import '../../../models/lesson_translation.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../../services/storage/secure_storage_service.dart';
import '../../setup/models/classroom_setup.dart';
import 'ai_content_service.dart';

/// Outcome of asking for a lesson in the classroom's mother tongue.
sealed class TranslationOutcome {
  const TranslationOutcome();
}

final class TranslationReady extends TranslationOutcome {
  const TranslationReady(this.translation, {this.fromCache = false});

  final LessonTranslation translation;

  /// True when it was already on the device, which is what makes the offline
  /// path indistinguishable from the online one for the teacher.
  final bool fromCache;
}

/// Offline, and nothing saved for this lesson in this language.
final class TranslationNeedsConnection extends TranslationOutcome {
  const TranslationNeedsConnection(this.message);

  final String message;
}

/// Online, but no translation exists for this lesson in this language.
final class TranslationMissing extends TranslationOutcome {
  const TranslationMissing(this.message);

  final String message;
}

/// The attempt itself failed.
final class TranslationFailed extends TranslationOutcome {
  const TranslationFailed(this.message);

  final String message;
}

/// Turns a teacher script into the classroom's mother tongue.
///
/// The screen holds one of these and knows nothing about where the words come
/// from. Today they are curated strings on the device; tomorrow they are a
/// FastAPI call or an on-device model, and the screen is unchanged.
abstract interface class TranslationService {
  /// What is already saved, without asking any provider. Safe offline.
  Future<LessonTranslation?> cached(String lessonId, TargetLanguage target);

  Future<TranslationOutcome> translate({
    required Lesson lesson,
    required LessonPlan plan,
    required TargetLanguage target,
  });

  /// Removes a saved translation, e.g. when the teacher clears offline content.
  Future<void> forget(String lessonId, TargetLanguage target);
}

/// Cache-first translation over an [AiContentService].
///
/// The order matters and is the whole offline story:
///
///   saved on device  ->  return it, no connection needed
///   not saved        ->  ask the provider
///   provider says no ->  say so plainly, never invent a translation
///
/// A result from the provider is written to the device before it is returned,
/// so the second time a teacher opens the lesson it needs no network at all.
class AiTranslationService implements TranslationService {
  AiTranslationService({
    required AiContentService ai,
    required SecureStorageService storage,
    required ConnectivityService connectivity,
  })  : _ai = ai,
        _storage = storage,
        _connectivity = connectivity;

  static const String _keyPrefix = 'lessons.translation.';

  final AiContentService _ai;
  final SecureStorageService _storage;
  final ConnectivityService _connectivity;

  final Map<String, LessonTranslation> _memory = <String, LessonTranslation>{};

  @override
  Future<LessonTranslation?> cached(
    String lessonId,
    TargetLanguage target,
  ) async {
    final String key = LessonTranslation.cacheKeyFor(lessonId, target);
    final LessonTranslation? held = _memory[key];
    if (held != null) return held;

    final String? raw = await _storage.read('$_keyPrefix$key');
    if (raw == null || raw.isEmpty) return null;
    try {
      final LessonTranslation value = LessonTranslation.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      return _memory[key] = value;
    } on Object catch (error) {
      AppLogger.error('cached translation could not be read', error: error);
      await _storage.delete('$_keyPrefix$key');
      return null;
    }
  }

  @override
  Future<TranslationOutcome> translate({
    required Lesson lesson,
    required LessonPlan plan,
    required TargetLanguage target,
  }) async {
    final LessonTranslation? saved = await cached(lesson.id, target);
    if (saved != null) {
      return TranslationReady(saved, fromCache: true);
    }

    // Only a provider that actually lives on the network can be blocked by
    // being offline. The development adapter is on the device, so refusing
    // here would be a lie in the other direction.
    if (_ai.hasProvider && _connectivity.status == ConnectionStatus.offline) {
      return const TranslationNeedsConnection(
        "This translation isn't available offline yet.",
      );
    }

    try {
      final AiContentResult<LessonTranslation> result = await _ai
          .translateLesson(lesson: lesson, plan: plan, target: target);

      return switch (result) {
        AiContent<LessonTranslation>(:final LessonTranslation value) =>
          TranslationReady(await _save(value)),
        AiContentUnavailable<LessonTranslation>(
          :final AiUnavailableReason reason,
          :final String message,
        ) =>
          _explain(reason, message),
      };
    } on Object catch (error) {
      // The teacher sees a sentence, never the exception. The exception goes to
      // the log, where it is useful.
      AppLogger.error('translation failed', error: error);
      return const TranslationFailed(
        "Couldn't translate this lesson right now.",
      );
    }
  }

  @override
  Future<void> forget(String lessonId, TargetLanguage target) async {
    final String key = LessonTranslation.cacheKeyFor(lessonId, target);
    _memory.remove(key);
    await _storage.delete('$_keyPrefix$key');
  }

  Future<LessonTranslation> _save(LessonTranslation value) async {
    _memory[value.cacheKey] = value;
    await _storage.write(
      '$_keyPrefix${value.cacheKey}',
      jsonEncode(value.toJson()),
    );
    return value;
  }

  static TranslationOutcome _explain(
    AiUnavailableReason reason,
    String message,
  ) =>
      switch (reason) {
        AiUnavailableReason.needsConnection =>
          const TranslationNeedsConnection(
            "This translation isn't available offline yet.",
          ),
        // The service's own wording is used here because it names the language,
        // which is exactly what the teacher needs to know.
        AiUnavailableReason.noContent ||
        AiUnavailableReason.notConfigured =>
          TranslationMissing(message),
        AiUnavailableReason.failed => const TranslationFailed(
            "Couldn't translate this lesson right now.",
          ),
      };
}
