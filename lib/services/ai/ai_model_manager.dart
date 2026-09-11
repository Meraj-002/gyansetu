// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'package:flutter/foundation.dart';

import '../../core/utils/app_logger.dart';
import '../../core/utils/result.dart';
import '../../models/resource_manifest.dart';
import '../downloads/download_manager.dart';
import '../resources/resource_catalogue_service.dart';

/// Where a model artifact stands in its on-device lifecycle.
enum AiModelState {
  /// Nothing is on disk and nothing is happening.
  notInstalled,

  /// The pack is being transferred (or waiting to be).
  downloading,

  /// On disk, size- and checksum-verified by the download pipeline. Not in
  /// memory.
  ready,

  /// Being read into memory for inference.
  loading,

  /// In memory and ready to answer.
  loaded,

  /// The transfer failed, or the artifact failed verification.
  failed,
}

/// What is on disk for one model, honestly measured.
class AiModelInfo {
  const AiModelInfo({
    required this.id,
    required this.version,
    this.sizeBytes,
    this.sha256,
  });

  final String id;
  final String version;
  final int? sizeBytes;
  final String? sha256;
}

/// Manages AI model artifacts on the device.
///
/// There are no bundled AI weights in this app, so the "model" an on-device
/// translator answers from is a curated language-pack resource fetched through
/// the same verified download pipeline as lessons. The manager stays honest
/// about the difference: a pack is [AiModelState.ready] only after the
/// download pipeline verified its size and checksum, and is never claimed to be
/// an NLP model. A future real on-device model plugs into this same surface
/// without changing the screens above it.
abstract interface class AiModelManager {
  Future<AiModelState> modelState(String packId);

  /// True only when the artifact is actually on disk and verified.
  Future<bool> isModelAvailable(String packId);

  /// Version/size/sha promised by the catalogue, when the pack is known.
  Future<AiModelInfo?> modelInfo(String packId);

  /// Downloads (or resumes) the pack for [packId] through the app's own
  /// DownloadManager. Resolves when it reaches a terminal state.
  Future<void> download(String packId);

  /// Reads the verified pack into memory (marked loaded).
  Future<void> loadModel(String packId);

  /// Drops the in-memory copy; the on-disk pack stays.
  Future<void> unloadModel(String packId);

  /// Removes the pack from disk entirely.
  Future<void> deleteModel(String packId);
}

/// [AiModelManager] over the real download pipeline and resource catalogue.
class ResourceBackedAiModelManager implements AiModelManager {
  ResourceBackedAiModelManager({
    required DownloadManager downloadManager,
    required ResourceCatalogueService catalogue,
  })  : _downloads = downloadManager,
        _catalogue = catalogue;

  final DownloadManager _downloads;
  final ResourceCatalogueService _catalogue;

  final Set<String> _loaded = <String>{};

  @override
  Future<AiModelState> modelState(String packId) async {
    if (_loaded.contains(packId)) return AiModelState.loaded;

    final ResourceDownloadState state = _downloads.stateFor(packId);
    return switch (state) {
      ResourceDownloadState.missing => AiModelState.notInstalled,
      ResourceDownloadState.queued ||
      ResourceDownloadState.downloading ||
      ResourceDownloadState.verifying =>
        AiModelState.downloading,
      ResourceDownloadState.ready => AiModelState.ready,
      ResourceDownloadState.failed => AiModelState.failed,
    };
  }

  @override
  Future<bool> isModelAvailable(String packId) async {
    final AiModelState state = await modelState(packId);
    return state == AiModelState.ready || state == AiModelState.loaded;
  }

  @override
  Future<AiModelInfo?> modelInfo(String packId) async {
    final ResourceDownloadStatus? status = _downloads.statusFor(packId);
    if (status == null) return null;
    final ResourceManifest manifest = status.manifest;
    return AiModelInfo(
      id: manifest.id,
      version: manifest.version,
      sizeBytes: manifest.sizeBytes,
      sha256: manifest.sha256,
    );
  }

  @override
  Future<void> download(String packId) async {
    await _downloads.ensureInitialized();

    final AiModelState state = await modelState(packId);
    if (state == AiModelState.ready || state == AiModelState.loaded) return;

    final ResourceDownloadState current = _downloads.stateFor(packId);
    if (current.isActive) return;

    final Result<ResourceManifest?> found = await _catalogue.byId(packId);
    final ResourceManifest manifest = switch (found) {
      Ok<ResourceManifest?>(:final ResourceManifest? value) when value != null =>
        value,
      _ => throw StateError(
          'The server no longer advertises model pack "$packId".',
        ),
    };

    await _downloads.enqueue(<ResourceManifest>[manifest]);
    await _downloads.waitFor(<String>{packId});
  }

  @override
  Future<void> loadModel(String packId) async {
    if (!await isModelAvailable(packId)) {
      throw StateError('Model pack "$packId" is not installed; load nothing.');
    }
    // Never two large models in memory at once on a 2 GB phone: loading one
    // unloads whatever else was loaded. Unloading is always safe.
    _loaded
      ..clear()
      ..add(packId);
  }

  /// How many model packs are currently held in memory (0 or 1 by design).
  @visibleForTesting
  int get loadedCount => _loaded.length;

  @override
  Future<void> unloadModel(String packId) async {
    _loaded.remove(packId);
  }

  @override
  Future<void> deleteModel(String packId) async {
    _loaded.remove(packId);
    await _downloads.remove(packId);
  }
}

/// Development manager for machines with no backend: a pack whose catalogue
/// lookup cannot succeed never downloads and honestly reports nothing
/// installed. Used by tests to prove the unavailable path stays unavailable.
class HaltWithoutCatalogueAiModelManager implements AiModelManager {
  const HaltWithoutCatalogueAiModelManager();

  @override
  Future<AiModelState> modelState(String packId) async =>
      AiModelState.notInstalled;

  @override
  Future<bool> isModelAvailable(String packId) async => false;

  @override
  Future<AiModelInfo?> modelInfo(String packId) async {
    AppLogger.info('model lookup requested with no catalogue: $packId');
    return null;
  }

  @override
  Future<void> download(String packId) async {
    throw StateError(
      'Model download refused: no backend catalogue is configured for '
      '"$packId".',
    );
  }

  @override
  Future<void> loadModel(String packId) async {
    throw StateError('No model pack is installed; nothing to load.');
  }

  @override
  Future<void> unloadModel(String packId) async {}

  @override
  Future<void> deleteModel(String packId) async {}
}