import '../../core/utils/result.dart';

/// Transport contract for talking to the FastAPI backend.
///
/// An interface rather than a concrete class so that features depend on the
/// contract, and tests can substitute a fake without a running server.
abstract interface class ApiClient {
  Future<Result<Map<String, dynamic>>> get(
    String path, {
    Map<String, String>? query,
  });

  Future<Result<Map<String, dynamic>>> post(String path, {Object? body});

  /// Uploads one file as `multipart/form-data`, answered as JSON.
  ///
  /// Used by the voice-translation path, which the JSON-only [post] cannot
  /// carry. Returns the same [Result] contract as every other call.
  Future<Result<Map<String, dynamic>>> postMultipart(
    String path, {
    required Map<String, String> fields,
    required String fileField,
    required String filePath,
    String? filename,
  });

  Future<Result<Map<String, dynamic>>> put(String path, {Object? body});

  Future<Result<Map<String, dynamic>>> patch(String path, {Object? body});

  Future<Result<void>> delete(String path);
}
