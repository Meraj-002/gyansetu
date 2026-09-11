import 'package:flutter/services.dart' show rootBundle;

import '../models/classroom_setup.dart';
import '../models/offline_resource_status.dart';

/// Works out what a classroom needs in order to run without a connection, and
/// reports honestly what is actually on the device.
///
/// It does not download anything, and it does not pretend to. No resource
/// package exists yet, so every category below reports itself missing and the
/// UI says the resources still need synchronising. When packs start shipping —
/// bundled as assets or pulled from FastAPI — only [_isBundled] changes.
abstract interface class OfflineResourceManager {
  /// Categories this classroom needs.
  List<OfflineResourceKind> requiredFor(ResourceProfile profile);

  /// Checks what is present. Never mutates anything.
  Future<OfflineResourceStatus> check(ResourceProfile profile);

  /// Prepares what can be prepared locally, then re-checks.
  Future<OfflineResourceStatus> prepare(ResourceProfile profile);
}

/// Checks for resource packs bundled in the app.
class BundledOfflineResourceManager implements OfflineResourceManager {
  const BundledOfflineResourceManager();

  /// Where a pack would live once one exists, keyed by language, class and
  /// subject so switching any of them marks the new set as needing preparation.
  static String packPath(ResourceProfile profile, OfflineResourceKind kind) =>
      'assets/packs/${profile.targetLanguage.localeId}/'
      'class-${profile.classLevel}/${kind.name}.json';

  @override
  List<OfflineResourceKind> requiredFor(ResourceProfile profile) {
    return <OfflineResourceKind>[
      OfflineResourceKind.curriculum,
      OfflineResourceKind.lessons,
      OfflineResourceKind.vocabulary,
      OfflineResourceKind.audio,
      OfflineResourceKind.languageModel,
      if (profile.subjects.contains(ClassroomSubject.foundationalLiteracy))
        OfflineResourceKind.flashcards,
      if (profile.subjects.isNotEmpty) OfflineResourceKind.worksheets,
      if (profile.subjects.isNotEmpty) OfflineResourceKind.assessments,
    ];
  }

  @override
  Future<OfflineResourceStatus> check(ResourceProfile profile) async {
    final List<OfflineResource> resources = <OfflineResource>[
      for (final OfflineResourceKind kind in requiredFor(profile))
        OfflineResource(
          kind: kind,
          available: await _isBundled(packPath(profile, kind)),
          detail: 'Not bundled with this build',
        ),
    ];

    final bool allPresent =
        resources.isNotEmpty && resources.every((OfflineResource r) => r.available);

    return OfflineResourceStatus(
      readiness:
          allPresent ? OfflineReadiness.ready : OfflineReadiness.needsSync,
      resources: resources,
      message: allPresent
          ? 'Everything this classroom needs is on this device.'
          : 'Offline resources will be available after synchronisation.',
    );
  }

  @override
  Future<OfflineResourceStatus> prepare(ResourceProfile profile) async {
    // There is nothing to prepare locally yet: preparation means copying a
    // downloaded pack into place, and no pack can be downloaded. Re-checking is
    // the honest implementation, and it becomes real work unchanged once packs
    // exist.
    return check(profile);
  }

  /// True only if the asset is genuinely in the bundle.
  Future<bool> _isBundled(String assetPath) async {
    try {
      await rootBundle.load(assetPath);
      return true;
    } on Object {
      return false;
    }
  }
}

/// Reports a fixed status. For tests and previews.
class StaticOfflineResourceManager implements OfflineResourceManager {
  const StaticOfflineResourceManager(this._status, {this.throwOnPrepare = false});

  final OfflineResourceStatus _status;

  /// Exercises the "setup saved but resources failed" branch.
  final bool throwOnPrepare;

  @override
  List<OfflineResourceKind> requiredFor(ResourceProfile profile) =>
      <OfflineResourceKind>[OfflineResourceKind.lessons];

  @override
  Future<OfflineResourceStatus> check(ResourceProfile profile) async => _status;

  @override
  Future<OfflineResourceStatus> prepare(ResourceProfile profile) async {
    if (throwOnPrepare) throw StateError('resource preparation failed');
    return _status;
  }
}
