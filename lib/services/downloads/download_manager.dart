// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/utils/app_logger.dart';
import '../../models/resource_manifest.dart';
import '../storage/secure_storage_service.dart';
import 'download_transport.dart';
import 'local_content.dart';
import 'offline_pack_source.dart';

/// Where one downloaded pack is in its lifecycle.
enum ResourceDownloadState {
  /// Not known to this device at all.
  missing,

  /// Waiting for the single transfer slot.
  queued,

  /// Bytes are flowing to disk.
  downloading,

  /// Bytes arrived; checking size and checksum.
  verifying,

  /// Verified on disk; safe to use offline.
  ready,

  /// The last attempt ended in a reason the device will not hide.
  failed;

  bool get isActive =>
      this == ResourceDownloadState.queued ||
      this == ResourceDownloadState.downloading ||
      this == ResourceDownloadState.verifying;
}

/// Why a pack is not Ready. The device reports the reason rather than silently
/// retrying forever.
enum ResourceDownloadFailure {
  network,
  storageUnavailable,
  insufficientStorage,
  corrupted,
  missing,
  cancelled,
  unknown,
}

/// One pack's live status. [receivedBytes] carries transfer progress so the UI
/// can show a real progress number, never a guess.
class ResourceDownloadStatus {
  const ResourceDownloadStatus({
    required this.manifest,
    required this.state,
    this.receivedBytes = 0,
    this.failure,
  });

  final ResourceManifest manifest;
  final ResourceDownloadState state;
  final int receivedBytes;
  final ResourceDownloadFailure? failure;

  bool get isReady => state == ResourceDownloadState.ready;

  /// 0..1 progress while downloading; 1 once verified.
  double get progress {
    if (state == ResourceDownloadState.downloading) {
      final int expected = manifest.sizeBytes;
      if (expected <= 0) return 0;
      return (receivedBytes / expected).clamp(0.0, 1.0);
    }
    return isReady ? 1 : 0;
  }

  ResourceDownloadStatus copyWith({
    ResourceDownloadState? state,
    int? receivedBytes,
    ResourceDownloadFailure? failure,
  }) =>
      ResourceDownloadStatus(
        manifest: manifest,
        state: state ?? this.state,
        receivedBytes: receivedBytes ?? this.receivedBytes,
        failure: failure,
      );
}

/// Owns the real offline download pipeline.
///
/// * A **single serial queue**: exactly one pack transfers at a time, which is
///   the standing low-memory rule for a 2 GB device.
/// * **Streaming**: bytes are written to a ``.part`` file as they arrive; a
///   pack is never held in RAM whole.
/// * **Verification before Ready**: the transfer must match the manifest's
///   size and sha256 (and the server's ``X-Checksum-Sha256``), then the
///   ``.part`` file is atomically renamed into place. Ready is only ever
///   claimed for a file that exists and was verified.
/// * **Persisted**: queue and ready inventory live in the secure store, so a
///   restart resumes queued work and never silently forgets what is installed.
class DownloadManager extends ChangeNotifier implements OfflinePackSource {
  DownloadManager({
    required SecureStorageService storage,
    required DownloadTransport transport,
    LocalContentIo? io,
    String? baseDirectory,
  })  : _storage = storage,
        _transport = transport,
        _io = io ?? deviceLocalContentIo,
        _baseDirectory = baseDirectory;

  static const String _inventoryKey = 'downloads.inventory.v1';
  static const Duration _progressNotifyEvery = Duration(milliseconds: 120);

  final SecureStorageService _storage;
  final DownloadTransport _transport;
  final LocalContentIo _io;

  /// Absolute content directory injected by tests; null resolves the
  /// platform's real writable folder at init.
  final String? _baseDirectory;

  String? _root;
  bool _initialized = false;
  Future<void>? _initFuture;
  bool _draining = false;

  final Map<String, ResourceDownloadStatus> _statuses = <String, ResourceDownloadStatus>{};
  final List<String> _queueOrder = <String>[];

  /// Resource ids whose removal was requested mid-transfer.
  final Set<String> _cancelRequested = <String>{};

  DateTime _lastProgressNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// Loads persisted state (queue + verified inventory) and resumes queued
  /// work. Safe to call repeatedly.
  Future<void> init() async {
    if (_initialized) return _initFuture ?? Future<void>.value();
    return _initFuture = _restore();
  }

  Future<void> _restore() async {
    _root = _baseDirectory ?? await _io.resolveContentRoot();
    _initialized = true;

    final String? raw = await _storage.read(_inventoryKey);
    if (raw == null || raw.isEmpty) return;

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;

    final Map<String, ResourceDownloadStatus> restored =
        <String, ResourceDownloadStatus>{};
    final List<String> queue = <String>[];
    for (final MapEntry<String, dynamic> entry in decoded.entries) {
      final Map<String, dynamic>? item = entry.value as Map<String, dynamic>?;
      if (item == null) continue;
      final ResourceManifest? manifest =
          _tryManifest(item['manifest'] as Map<String, dynamic>?);
      if (manifest == null) continue;
      final String state = item['state'] as String? ?? 'missing';

      if (state == 'ready') {
        // Re-verify quickly on boot: Ready must mean a file of the right size
        // is present. Anything else is demoted to missing so a corrupted or
        // wiped file can never masquerade as usable content.
        if (_root != null && await _sizeMatches(manifest)) {
          restored[manifest.id] = ResourceDownloadStatus(
            manifest: manifest,
            state: ResourceDownloadState.ready,
          );
        } else {
          await _removeFile(manifest.id);
        }
      } else if (state == ResourceDownloadState.failed.name ||
          state == ResourceDownloadState.queued.name) {
        restored[manifest.id] = ResourceDownloadStatus(
          manifest: manifest,
          state: state == ResourceDownloadState.failed.name
              ? ResourceDownloadState.failed
              : ResourceDownloadState.queued,
          failure: state == ResourceDownloadState.failed.name
              ? ResourceDownloadFailure.missing
              : null,
        );
        if (state == ResourceDownloadState.queued.name) queue.add(manifest.id);
      }
    }

    if (restored.isNotEmpty) {
      _statuses.addAll(restored);
      _queueOrder.addAll(queue);
      notifyListeners();
    }
    await _persist();

    if (queue.isNotEmpty) unawaited(drain());
  }

  Future<bool> _sizeMatches(ResourceManifest manifest) async {
    final String? root = _root;
    if (root == null) return false;
    return await _io.length(_packPath(root, manifest.id)) == manifest.sizeBytes;
  }

  ResourceManifest? _tryManifest(Map<String, dynamic>? json) {
    if (json == null) return null;
    try {
      return ResourceManifest.fromJson(json);
    } on Object {
      return null;
    }
  }

  Future<void> _persist() async {
    final Map<String, dynamic> body = <String, dynamic>{};
    for (final ResourceDownloadStatus status in _statuses.values) {
      body[status.manifest.id] = <String, dynamic>{
        'manifest': status.manifest.toJson(),
        'state': status.state.name,
      };
    }
    await _storage.write(_inventoryKey, jsonEncode(body));
  }

  Future<void> ensureInitialized() => init();

  // --- surface -------------------------------------------------------------

  Map<String, ResourceDownloadStatus> get statuses =>
      Map<String, ResourceDownloadStatus>.unmodifiable(_statuses);

  ResourceDownloadStatus? statusFor(String id) => _statuses[id];

  Set<String> get readyIds => <String>{
        for (final ResourceDownloadStatus s in _statuses.values)
          if (s.isReady) s.manifest.id,
      };

  List<ResourceManifest> get readyManifests => <ResourceManifest>[
        for (final ResourceDownloadStatus s in _statuses.values)
          if (s.isReady) s.manifest,
      ];

  List<String> get queueOrder => List<String>.unmodifiable(_queueOrder);

  bool get isDownloading =>
      _statuses.values.any((ResourceDownloadStatus s) => s.state.isActive);

  ResourceDownloadState stateFor(String id) =>
      _statuses[id]?.state ?? ResourceDownloadState.missing;

  /// Honest bytes of verified content currently on disk (sum of the ready
  /// packs' manifest sizes — each was size-verified at download and on boot).
  Future<int> downloadedBytes() async {
    final String? root = _root;
    if (root == null) return 0;
    int total = 0;
    for (final ResourceManifest manifest in readyManifests) {
      if (await _sizeMatches(manifest)) total += manifest.sizeBytes;
    }
    return total;
  }

  /// Where content is stored, or null when this platform has no writable
  /// folder.
  String? get contentRoot => _root;

  /// The absolute path a ready pack is kept at, or null when this platform has
  /// no writable folder. `pathForReady` always resolves on the manifest that is
  /// actually on disk, so a caller streams the bytes the ready gate verified.
  @override
  String? pathForReady(String id) {
    final String? root = _root;
    if (root == null) return null;
    return _packPath(root, id);
  }

  /// Orphaned ``.part`` files left by an interrupted transfer.
  Future<int> temporaryPartCount() async {
    final String? root = _root;
    if (root == null) return 0;
    int count = 0;
    for (final ResourceDownloadStatus status in _statuses.values) {
      if (await _io.exists(_partPath(root, status.manifest.id))) count++;
    }
    return count;
  }

  /// Clears orphaned ``.part`` files (interrupted transfers). Ready packs are
  /// never touched.
  Future<int> clearTemporaryFiles() async {
    final String? root = _root;
    if (root == null) return 0;
    int removed = 0;
    for (final ResourceDownloadStatus status in _statuses.values) {
      final String part = _partPath(root, status.manifest.id);
      if (await _io.exists(part)) {
        await _io.delete(part);
        removed++;
      }
    }
    return removed;
  }

  // --- control -------------------------------------------------------------

  /// Adds packs to the queue. Duplicates (already queued, ready or failed) are
  /// ignored. Returns the ids actually queued.
  Future<List<String>> enqueue(Iterable<ResourceManifest> manifests) async {
    await ensureInitialized();
    final List<String> added = <String>[];
    for (final ResourceManifest manifest in manifests) {
      if (_root == null) {
        // Storage is genuinely unavailable here; the caller should refuse
        // rather than queue fake work.
        AppLogger.info('enqueue without storage root: ${manifest.id}');
        continue;
      }
      if (_statuses.containsKey(manifest.id)) continue;
      _statuses[manifest.id] = ResourceDownloadStatus(
        manifest: manifest,
        state: ResourceDownloadState.queued,
      );
      _queueOrder.add(manifest.id);
      added.add(manifest.id);
    }
    if (added.isNotEmpty) {
      notifyListeners();
      await _persist();
      unawaited(drain());
    }
    return added;
  }

  Future<void> retry(String resourceId) async {
    await ensureInitialized();
    final ResourceDownloadStatus? status = _statuses[resourceId];
    if (status == null) return;
    if (status.state.isActive) return;
    _statuses[resourceId] = status.copyWith(
      state: ResourceDownloadState.queued,
      receivedBytes: 0,
      failure: null,
    );
    if (!_queueOrder.contains(resourceId)) _queueOrder.add(resourceId);
    notifyListeners();
    await _persist();
    unawaited(drain());
  }

  Future<void> remove(String resourceId) async {
    await ensureInitialized();
    _cancelRequested.add(resourceId);
    await _removeFile(resourceId);
    _clearKnown(resourceId);
    if (!_statuses.values.any((ResourceDownloadStatus s) => s.state.isActive)) {
      _cancelRequested.clear();
    }
    await _persist();
    notifyListeners();
  }

  Future<void> clearFailed() async {
    await ensureInitialized();
    bool changed = false;
    for (final MapEntry<String, ResourceDownloadStatus> entry
        in _statuses.entries.toList()) {
      if (entry.value.state == ResourceDownloadState.failed) {
        _statuses.remove(entry.key);
        _queueOrder.remove(entry.key);
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      await _persist();
    }
  }

  void _clearKnown(String resourceId) {
    _statuses.remove(resourceId);
    _queueOrder.remove(resourceId);
  }

  /// Resolves after every id in [ids] reaches a terminal state (ready or
  /// failed), or [timeout] elapses. Returns id → ready.
  Future<Map<String, bool>> waitFor(Set<String> ids, {Duration? timeout}) async {
    await ensureInitialized();
    final Completer<Map<String, bool>> completer =
        Completer<Map<String, bool>>();
    late void Function() listener;
    listener = () {
      final Map<String, bool> settled = <String, bool>{};
      for (final String id in ids) {
        final ResourceDownloadState state = stateFor(id);
        if (state == ResourceDownloadState.ready) {
          settled[id] = true;
        } else if (state == ResourceDownloadState.failed ||
            state == ResourceDownloadState.missing) {
          settled[id] = false;
        }
      }
      if (settled.length == ids.length) {
        removeListener(listener);
        if (!completer.isCompleted) completer.complete(settled);
      }
    };
    addListener(listener);
    listener();
    if (!completer.isCompleted) {
      final Duration wait = timeout ?? const Duration(minutes: 10);
      Future<void>.delayed(wait, () {
        removeListener(listener);
        if (!completer.isCompleted) {
          completer.complete(<String, bool>{
            for (final String id in ids)
              id: stateFor(id) == ResourceDownloadState.ready,
          });
        }
      });
    }
    return completer.future;
  }

  // --- the serial worker ---------------------------------------------------

  /// One transfer at a time, in queue order. Items are removed from the queue
  /// as soon as they succeed or fail, so a failure never blocks the rest; the
  /// failed item stays known so the user can retry or remove it.
  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queueOrder.isNotEmpty) {
        final String id = _queueOrder.first;
        _queueOrder.removeAt(0);
        if (_cancelRequested.contains(id)) {
          _cancelRequested.remove(id);
          _clearKnown(id);
          await _persist();
          continue;
        }
        await _process(id);
        if (_cancelRequested.isNotEmpty) {
          _cancelRequested.clear();
        }
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _process(String id) async {
    final ResourceDownloadStatus? status = _statuses[id];
    final String? root = _root;
    if (status == null || root == null) return;

    final ResourceManifest manifest = status.manifest;
    _setStatus(id, status.copyWith(
      state: ResourceDownloadState.downloading,
      receivedBytes: 0,
      failure: null,
    ));

    final String partPath = _partPath(root, id);
    final String finalPath = _packPath(root, id);
    await _io.delete(partPath);

    bool writeSucceeded = false;
    try {
      final PackDownloadStream stream = await _transport.fetch(manifest);
      if (_cancelRequested.contains(id)) return;

      if (stream.expectedSha256 != null &&
          stream.expectedSha256 != manifest.sha256) {
        await _fail(id, ResourceDownloadFailure.corrupted,
            'The server checksum does not match the manifest.');
        return;
      }

      _setStatus(id, status.copyWith(
        state: ResourceDownloadState.downloading,
        receivedBytes: 0,
      ));

      writeSucceeded = await _io.write(partPath, _counted(stream.bytes, id));
    } on DownloadTransportException catch (error) {
      await _fail(id, ResourceDownloadFailure.network, error.message);
      return;
    } on Object catch (error) {
      AppLogger.error('unexpected download failure for $id', error: error);
      await _fail(id, ResourceDownloadFailure.unknown,
          'The download stopped unexpectedly.');
      return;
    }

    if (_cancelRequested.contains(id)) return;
    if (!writeSucceeded) {
      return _fail(id, ResourceDownloadFailure.insufficientStorage,
          'The device could not save the downloaded bytes.');
    }

    _setStatus(id, status.copyWith(
      state: ResourceDownloadState.verifying,
      receivedBytes: manifest.sizeBytes,
    ));

    final int? onDisk = await _io.length(partPath);
    if (_cancelRequested.contains(id)) return;
    if (onDisk != manifest.sizeBytes || onDisk == null) {
      await _io.delete(partPath);
      return _fail(id, ResourceDownloadFailure.corrupted,
          'The downloaded file is the wrong size and was deleted.');
    }

    final String? digest = await _io.sha256(partPath);
    if (_cancelRequested.contains(id)) return;
    if (digest == null || digest.toLowerCase() != manifest.sha256.toLowerCase()) {
      await _io.delete(partPath);
      return _fail(id, ResourceDownloadFailure.corrupted,
          'The downloaded file failed its checksum check and was deleted.');
    }

    final bool renamed = await _io.rename(partPath, finalPath);
    if (_cancelRequested.contains(id)) {
      await _io.delete(finalPath);
      return;
    }
    if (!renamed) {
      return _fail(id, ResourceDownloadFailure.insufficientStorage,
          'The verified file could not be moved into place.');
    }

    _setStatus(id, status.copyWith(
      state: ResourceDownloadState.ready,
      receivedBytes: manifest.sizeBytes,
      failure: null,
    ));
    await _persist();
  }

  Stream<List<int>> _counted(Stream<List<int>> source, String id) async* {
    int total = 0;
    await for (final List<int> chunk in source) {
      total += chunk.length;
      final ResourceDownloadStatus? live = _statuses[id];
      if (live != null) {
        _statuses[id] = live.copyWith(
          state: ResourceDownloadState.downloading,
          receivedBytes: total,
        );
      }
      final DateTime now = DateTime.now();
      if (now.difference(_lastProgressNotify) >= _progressNotifyEvery) {
        _lastProgressNotify = now;
        notifyListeners();
      }
      yield chunk;
    }
  }

  void _setStatus(String id, ResourceDownloadStatus next) {
    _statuses[id] = next;
    notifyListeners();
  }

  Future<void> _fail(String id, ResourceDownloadFailure reason, String message) async {
    final ResourceDownloadStatus? current = _statuses[id];
    if (current == null) return;
    AppLogger.error('$id download failed: $message');
    _statuses[id] = current.copyWith(
      state: ResourceDownloadState.failed,
      failure: reason,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> _removeFile(String id) async {
    final String? root = _root;
    if (root == null) return;
    await _io.delete(_packPath(root, id));
    await _io.delete(_partPath(root, id));
  }

  // --- paths ---------------------------------------------------------------

  static String _packPath(String root, String id) =>
      '$root/${id.replaceAll('.', '_')}.pack';

  static String _partPath(String root, String id) =>
      '${_packPath(root, id)}.part';
}