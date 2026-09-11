// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/result.dart';
import '../../models/resource_manifest.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';

/// Reads the downloadable pack catalogue from the FastAPI backend.
///
/// The list endpoint returns a bare JSON array, which [HttpApiClient] wraps
/// under `{"value": [...]}` — that box is unwrapped here, never passed up.
/// Pagination walks every page so [all] reflects the whole catalogue, which is
/// what Update Packs compares against.
class ResourceCatalogueService {
  ResourceCatalogueService({required ApiClient api, this.pageSize = 100})
      : _api = api;

  final ApiClient _api;
  final int pageSize;

  /// The whole catalogue, pulled page by page. An empty list means the server
  /// reported no packs; an error is surfaced as [Err].
  Future<Result<List<ResourceManifest>>> all() async {
    final List<ResourceManifest> manifests = <ResourceManifest>[];
    int offset = 0;
    while (true) {
      final Result<Map<String, dynamic>> page = await _api.get(
        ApiEndpoints.resources,
        query: <String, String>{
          'limit': '$pageSize',
          'offset': '$offset',
        },
      );
      switch (page) {
        case Err<Map<String, dynamic>>(:final AppException error):
          AppLogger.error('resource catalogue page failed', error: error);
          return Err<List<ResourceManifest>>(error);
        case Ok<Map<String, dynamic>>(:final Map<String, dynamic> value):
          final List<dynamic>? items = value['value'] as List<dynamic>?;
          if (items == null || items.isEmpty) {
            return Ok<List<ResourceManifest>>(manifests);
          }
          for (final Object? raw in items) {
            if (raw is! Map<String, dynamic>) continue;
            final ResourceManifest? manifest = _tryManifest(raw);
            if (manifest != null) manifests.add(manifest);
          }
          if (items.length < pageSize) return Ok<List<ResourceManifest>>(manifests);
          offset += items.length;
      }
    }
  }

  /// One pack by id. Returns null when the server has no such pack (it may
  /// have been unpublished between a lesson listing and the download).
  Future<Result<ResourceManifest?>> byId(String resourceId) async {
    final Result<Map<String, dynamic>> result =
        await _api.get('${ApiEndpoints.resources}/$resourceId');
    return switch (result) {
      Err<Map<String, dynamic>>(:final AppException error) => Err(error),
      Ok<Map<String, dynamic>>(:final Map<String, dynamic> value) when value.isEmpty =>
        const Ok<ResourceManifest?>(null),
      Ok<Map<String, dynamic>>(:final Map<String, dynamic> value) =>
        Ok<ResourceManifest?>(_tryManifest(value)),
    };
  }

  /// Resolves the ids a lesson needs into the manifest the server advertises.
  /// Ids with no manifest are reported back so the caller can refuse kindly
  /// instead of downloading half a lesson.
  Future<Map<String, ResourceManifest>> resolve(Iterable<String> ids) async {
    final Map<String, ResourceManifest> resolved = <String, ResourceManifest>{};
    for (final String id in ids) {
      if (resolved.containsKey(id)) continue;
      final Result<ResourceManifest?> found = await byId(id);
      switch (found) {
        case Ok<ResourceManifest?>(:final ResourceManifest? value)
            when value != null:
          resolved[id] = value;
        default:
          break;
      }
    }
    return resolved;
  }

  /// Packs on the server whose version differs from what a device already
  /// holds. Returns (id → manifest) needing an update plus the manifests that
  /// are not yet installed at all. Name kept deliberately concrete: it is the
  /// data behind the Offline Centre's "Update Packs" tool.
  Future<Result<Map<String, ResourceManifest>>> diffWith(
    Map<String, String> localVersions,
  ) async {
    final Result<List<ResourceManifest>> all = await this.all();
    return switch (all) {
      Err<List<ResourceManifest>>(:final AppException error) =>
        Err<Map<String, ResourceManifest>>(error),
      Ok<List<ResourceManifest>>(:final List<ResourceManifest> value) =>
        Ok<Map<String, ResourceManifest>>(<String, ResourceManifest>{
          for (final ResourceManifest manifest in value)
            if (localVersions[manifest.id] != manifest.version)
              manifest.id: manifest,
        }),
    };
  }

  static ResourceManifest? _tryManifest(Map<String, dynamic> json) {
    try {
      return ResourceManifest.fromJson(json);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'unreadable resource manifest skipped',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}