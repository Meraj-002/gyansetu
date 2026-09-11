import 'package:gyan_setu_ai/core/errors/app_exception.dart';
import 'package:gyan_setu_ai/core/utils/result.dart';
import 'package:gyan_setu_ai/services/api/api_client.dart';

/// Returns a canned [Result] for a call, or null to mean "not scripted".
typedef ScriptedResult<M> = Result<M> Function();

/// An [ApiClient] whose behaviour the test scripts.
///
/// Replies come from handler functions so a test can decide the outcome by
/// path and by call count. Every call is recorded for later assertions.
class ScriptedApiClient implements ApiClient {
  /// Called for each GET. Default: an unscripted-server error.
  ScriptedResult<Map<String, dynamic>>? onGet;

  /// Called for each POST. Default: an unscripted-server error.
  ScriptedResult<Map<String, dynamic>>? onPost;

  /// Called for each PUT. Default: an unscripted-server error.
  ScriptedResult<Map<String, dynamic>>? onPut;

  /// Called for each PATCH. Default: an unscripted-server error.
  ScriptedResult<Map<String, dynamic>>? onPatch;

  final List<String> getPaths = <String>[];
  final List<String> postPaths = <String>[];
  final List<Object?> postBodies = <Object?>[];
  final List<String> putPaths = <String>[];
  final List<String> patchPaths = <String>[];
  final List<Object?> patchBodies = <Object?>[];

  /// The query map of the most recent GET, for scripts that page.
  Map<String, String>? lastQuery;

  int get postCount => postPaths.length;

  /// Paths posted to the given [path], most recent first.
  List<Map<String, Object?>> postCallsFor(String path) =>
      <Map<String, Object?>>[
        for (int i = postPaths.length - 1; i >= 0; i--)
          if (postPaths[i] == path)
            <String, Object?>{'path': postPaths[i], 'body': postBodies[i]},
      ];

  /// Paths patched, most recent first.
  List<String> get patchPathsReversed => patchPaths.reversed.toList();

  @override
  Future<Result<Map<String, dynamic>>> get(
    String path, {
    Map<String, String>? query,
  }) async {
    getPaths.add(path);
    lastQuery = query;
    final ScriptedResult<Map<String, dynamic>>? handler = onGet;
    if (handler == null) {
      return Err<Map<String, dynamic>>(
        ServerException('no GET handler scripted for $path', statusCode: 500),
      );
    }
    return handler();
  }

  @override
  Future<Result<Map<String, dynamic>>> post(String path, {Object? body}) async {
    postPaths.add(path);
    postBodies.add(body);
    final ScriptedResult<Map<String, dynamic>>? handler = onPost;
    if (handler == null) {
      return Err<Map<String, dynamic>>(
        ServerException('no POST handler scripted for $path', statusCode: 500),
      );
    }
    return handler();
  }

  @override
  Future<Result<Map<String, dynamic>>> postMultipart(
    String path, {
    required Map<String, String> fields,
    required String fileField,
    required String filePath,
    String? filename,
  }) async {
    postPaths.add(path);
    return Err<Map<String, dynamic>>(
      ServerException('no multipart POST handler scripted for $path',
          statusCode: 500),
    );
  }

  @override
  Future<Result<Map<String, dynamic>>> put(String path, {Object? body}) async {
    putPaths.add(path);
    final ScriptedResult<Map<String, dynamic>>? handler = onPut;
    if (handler == null) {
      return Err<Map<String, dynamic>>(
        ServerException('no PUT handler scripted for $path', statusCode: 500),
      );
    }
    return handler();
  }

  @override
  Future<Result<Map<String, dynamic>>> patch(
    String path, {
    Object? body,
  }) async {
    patchPaths.add(path);
    patchBodies.add(body);
    final ScriptedResult<Map<String, dynamic>>? handler = onPatch;
    if (handler == null) {
      return Err<Map<String, dynamic>>(
        ServerException('no PATCH handler scripted for $path', statusCode: 500),
      );
    }
    return handler();
  }

  @override
  Future<Result<void>> delete(String path) async =>
      const Ok<void>(null);
}