// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:async';

import '../../../core/utils/app_logger.dart';
import '../../../models/resource_manifest.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../../services/downloads/download_manager.dart';
import '../../../services/resources/resource_catalogue_service.dart';
import '../../../models/lesson.dart';
import 'lesson_repository.dart';

/// Why a download could not proceed.
enum DownloadRefusal {
  /// The content has never been on this device and there is no connection.
  needsConnection,

  /// The device does not have room.
  insufficientStorage,

  /// The attempt failed part-way.
  failed,
}

/// Outcome of asking for a lesson's content.
sealed class DownloadOutcome {
  const DownloadOutcome();
}

final class DownloadCompleted extends DownloadOutcome {
  const DownloadCompleted();
}

/// Already present; nothing was fetched.
final class DownloadAlreadyPresent extends DownloadOutcome {
  const DownloadAlreadyPresent();
}

final class DownloadRefused extends DownloadOutcome {
  const DownloadRefused(this.reason, this.message);

  final DownloadRefusal reason;
  final String message;
}

/// Fetches a lesson's content onto the device.
///
/// An interface because the real one will stream packs from FastAPI; nothing
/// above it changes when it does.
abstract interface class LessonDownloadService {
  /// Whether the device has room for [lesson].
  Future<bool> hasRoomFor(Lesson lesson);

  Future<DownloadOutcome> download(Lesson lesson);

  /// Removes the local copy.
  Future<void> remove(Lesson lesson);
}

/// The prototype implementation.
///
/// IMPORTANT: this does not invent a download. No content packs exist and there
/// is no server, so a lesson that is not already marked present is refused with
/// [DownloadRefusal.needsConnection] — which is the truth: it would need a
/// connection and a backend that is not there yet. When online it records the
/// lesson as present so the rest of the flow can be exercised, and it says so
/// in its own name.
///
/// REPLACE WITH: a service that streams the pack from FastAPI, writes it to
/// app storage and registers the resources with `OfflineResourceManager`.
class DevelopmentLessonDownloadService implements LessonDownloadService {
  DevelopmentLessonDownloadService({
    required LessonDownloadRepository downloads,
    required ConnectivityService connectivity,
    this.latency = const Duration(milliseconds: 1200),
    this.availableBytes = 512 * 1024 * 1024,
  })  : _downloads = downloads,
        _connectivity = connectivity;

  final LessonDownloadRepository _downloads;
  final ConnectivityService _connectivity;

  /// Simulated transfer time, so the downloading state is exercised.
  final Duration latency;

  /// Stand-in for a real free-space check, which needs a platform call this
  /// build does not make.
  final int availableBytes;

  /// Rough pack size used only by the storage check.
  static const int estimatedBytesPerLesson = 12 * 1024 * 1024;

  @override
  Future<bool> hasRoomFor(Lesson lesson) async =>
      availableBytes >= estimatedBytesPerLesson;

  @override
  Future<DownloadOutcome> download(Lesson lesson) async {
    if ((await _downloads.downloadedIds()).contains(lesson.id)) {
      return const DownloadAlreadyPresent();
    }

    if (!await hasRoomFor(lesson)) {
      return const DownloadRefused(
        DownloadRefusal.insufficientStorage,
        'Not enough storage available.',
      );
    }

    if (await _connectivity.check() != ConnectionStatus.online) {
      return const DownloadRefused(
        DownloadRefusal.needsConnection,
        'This lesson needs an internet connection for the first download.',
      );
    }

    try {
      await Future<void>.delayed(latency);
      await _downloads.markDownloaded(lesson.id);
      return const DownloadCompleted();
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'lesson download failed',
        error: error,
        stackTrace: stackTrace,
      );
      return const DownloadRefused(
        DownloadRefusal.failed,
        'Download failed. Try again.',
      );
    }
  }

  @override
  Future<void> remove(Lesson lesson) => _downloads.remove(lesson.id);
}

/// The real content download service.
///
/// Streams the lesson's content packs from the FastAPI backend through
/// [DownloadManager], and only ever reports a lesson as downloaded after every
/// pack it needs is verified on disk. Nothing is faked:
///
/// * a device with no writable storage refuses with `insufficientStorage`;
/// * offline on a first download refuses with `needsConnection`;
/// * a pack the catalogue no longer advertises refuses rather than half-downloads;
/// * a transfer that fails verification behaves as failed, never as done.
class ManagedLessonDownloadService implements LessonDownloadService {
  ManagedLessonDownloadService({
    required LessonDownloadRepository downloads,
    required DownloadManager downloadManager,
    required ResourceCatalogueService catalogue,
    required ConnectivityService connectivity,
    this.availableBytes = 512 * 1024 * 1024,
  })  : _downloads = downloads,
        _downloadManager = downloadManager,
        _catalogue = catalogue,
        _connectivity = connectivity;

  final LessonDownloadRepository _downloads;
  final DownloadManager _downloadManager;
  final ResourceCatalogueService _catalogue;
  final ConnectivityService _connectivity;

  /// Free-space estimate the device is willing to reserve for one lesson. The
  /// honest floor is "storage must exist at all": a platform backed by the
  /// unsupported IO reports no content root and is refused.
  final int availableBytes;

  /// Every pack id a lesson names for offline teaching.
  static List<String> _packIdsFor(Lesson lesson) => <String>[
        ...lesson.resourceIds,
        if (lesson.audioResourceId != null) lesson.audioResourceId!,
        if (lesson.worksheetResourceId != null) lesson.worksheetResourceId!,
        if (lesson.flashcardResourceId != null) lesson.flashcardResourceId!,
      ];

  Future<Map<String, ResourceManifest>> _resolve(Lesson lesson) async {
    try {
      return await _catalogue.resolve(_packIdsFor(lesson));
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'lesson pack resolution failed',
        error: error,
        stackTrace: stackTrace,
      );
      return <String, ResourceManifest>{};
    }
  }

  @override
  Future<bool> hasRoomFor(Lesson lesson) async {
    await _downloadManager.init();
    if (_downloadManager.contentRoot == null) return false;
    if ((await _storageReservedFor(lesson)) > availableBytes) return false;
    return true;
  }

  /// The total advertised size of the packs this lesson needs that are not
  /// already on the device.
  Future<int> _storageReservedFor(Lesson lesson) async {
    final Map<String, ResourceManifest> manifests = await _resolve(lesson);
    int total = 0;
    for (final ResourceManifest manifest in manifests.values) {
      if (_downloadManager.stateFor(manifest.id) != ResourceDownloadState.ready) {
        total += manifest.sizeBytes;
      }
    }
    return total;
  }

  @override
  Future<DownloadOutcome> download(Lesson lesson) async {
    await _downloadManager.init();
    if (_downloadManager.contentRoot == null) {
      return const DownloadRefused(
        DownloadRefusal.insufficientStorage,
        'This device has no storage for downloaded content.',
      );
    }

    if ((await _downloads.downloadedIds()).contains(lesson.id) &&
        await _lessonCompletelyReady(lesson)) {
      return const DownloadAlreadyPresent();
    }

    if (!await hasRoomFor(lesson)) {
      return const DownloadRefused(
        DownloadRefusal.insufficientStorage,
        'Not enough storage available.',
      );
    }

    if (await _connectivity.check() != ConnectionStatus.online) {
      return const DownloadRefused(
        DownloadRefusal.needsConnection,
        'This lesson needs an internet connection for the first download.',
      );
    }

    final Map<String, ResourceManifest> manifests = await _resolve(lesson);
    final Set<String> needed = _packIdsFor(lesson).toSet();
    final bool everyNeeded = needed.every(manifests.containsKey);
    if (!everyNeeded) {
      return const DownloadRefused(
        DownloadRefusal.failed,
        'This lesson is missing content packs on the server. Try again later.',
      );
    }

    final List<ResourceManifest> toFetch = <ResourceManifest>[
      for (final ResourceManifest manifest in manifests.values)
        if (_downloadManager.stateFor(manifest.id) !=
            ResourceDownloadState.ready)
          manifest,
    ];
    if (toFetch.isEmpty) {
      await _downloads.markDownloaded(lesson.id);
      return const DownloadCompleted();
    }

    await _downloadManager.enqueue(toFetch);
    final Map<String, bool> settled = await _downloadManager.waitFor(
      needed,
    );

    final bool allReady =
        settled.values.every((bool ok) => ok) && settled.length == needed.length;
    if (!allReady) {
      final ResourceDownloadFailure? reason = <ResourceDownloadFailure?>[
        for (final String id in needed)
          _downloadManager.statusFor(id)?.failure,
      ].firstWhere(
        (ResourceDownloadFailure? r) => r != null && r != ResourceDownloadFailure.cancelled,
        orElse: () => null,
      );
      return DownloadRefused(
        _failureToDownloadRefusal(reason),
        reason == ResourceDownloadFailure.insufficientStorage
            ? 'Not enough storage to keep this lesson on the device.'
            : 'Download failed to verify. Check your connection and try again.',
      );
    }

    try {
      await _downloads.markDownloaded(lesson.id);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'downloaded lesson could not be recorded',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return const DownloadCompleted();
  }

  static DownloadRefusal _failureToDownloadRefusal(
    ResourceDownloadFailure? failure,
  ) {
    return switch (failure) {
      ResourceDownloadFailure.insufficientStorage ||
      ResourceDownloadFailure.storageUnavailable =>
        DownloadRefusal.insufficientStorage,
      ResourceDownloadFailure.network ||
      ResourceDownloadFailure.missing ||
      ResourceDownloadFailure.unknown =>
        DownloadRefusal.failed,
      ResourceDownloadFailure.corrupted ||
      ResourceDownloadFailure.cancelled ||
      null =>
        DownloadRefusal.failed,
    };
  }

  Future<bool> _lessonCompletelyReady(Lesson lesson) async {
    final Map<String, ResourceManifest> manifests = await _resolve(lesson);
    final List<String> needed = _packIdsFor(lesson);
    if (needed.isEmpty) return true;
    final bool haveAll = needed.every(manifests.containsKey);
    if (!haveAll) return false;
    return needed.every(
      (String id) =>
          _downloadManager.stateFor(id) == ResourceDownloadState.ready,
    );
  }

  @override
  Future<void> remove(Lesson lesson) async {
    await _downloadManager.init();
    for (final String id in _packIdsFor(lesson)) {
      await _downloadManager.remove(id);
    }
    await _downloads.remove(lesson.id);
  }
}
