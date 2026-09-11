// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'package:http/http.dart' as http;

import '../../core/utils/app_logger.dart';
import '../../models/resource_manifest.dart';

/// The streamed body of one pack download.
class PackDownloadStream {
  const PackDownloadStream({
    required this.bytes,
    this.contentLength,
    this.expectedSha256,
  });

  final Stream<List<int>> bytes;

  /// ``Content-Length`` when the server sent one, else null.
  final int? contentLength;

  /// ``X-Checksum-Sha256`` when the server sent one, else null.
  final String? expectedSha256;
}

/// Thrown by a transport that could not fetch bytes.
class DownloadTransportException implements Exception {
  const DownloadTransportException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'DownloadTransportException($statusCode: $message)';
}

/// Fetches a pack's bytes from the server.
///
/// Kept behind an interface so the download manager can stream from FastAPI in
/// production and from a scripted source in tests. Implementations must stream
/// — the promise of the pipeline is that a pack never sits in memory whole.
abstract interface class DownloadTransport {
  Future<PackDownloadStream> fetch(ResourceManifest manifest);
}

/// Streams a resource's content from the FastAPI backend.
class HttpDownloadTransport implements DownloadTransport {
  HttpDownloadTransport({
    required this.baseUrl,
    Future<String?> Function()? accessTokenProvider,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
  })  : _accessTokenProvider = accessTokenProvider,
        _http = httpClient ?? http.Client();

  final String baseUrl;
  final Future<String?> Function()? _accessTokenProvider;
  final http.Client _http;
  final Duration timeout;

  /// The streaming content endpoint mirrors `ApiEndpoints` without importing
  /// it: transport is generic, the path is this backend's contract.
  Uri _uri(String resourceId) =>
      Uri.parse('$baseUrl/api/v1/resources/$resourceId/content');

  @override
  Future<PackDownloadStream> fetch(ResourceManifest manifest) async {
    final String? token = await _accessTokenProvider?.call();
    final http.Request request = http.Request('GET', _uri(manifest.id))
      ..headers['Accept'] = 'application/octet-stream';
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    final http.StreamedResponse response;
    try {
      response = await _http.send(request).timeout(timeout);
    } on Object catch (error) {
      AppLogger.error(
        'content fetch failed for ${manifest.id}',
        error: error,
      );
      throw const DownloadTransportException(
        'Could not reach the server to download the pack.',
      );
    }

    if (response.statusCode != 200) {
      response.stream.drain<void>();
      throw DownloadTransportException(
        'The server did not return the pack content.',
        statusCode: response.statusCode,
      );
    }

    final String? length = response.headers['content-length'];
    return PackDownloadStream(
      bytes: response.stream,
      contentLength: int.tryParse(length ?? ''),
      expectedSha256: response.headers['x-checksum-sha256'],
    );
  }
}