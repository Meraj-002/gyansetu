// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/result.dart';
import 'api_client.dart';

/// An [ApiClient] that talks to a real FastAPI backend over HTTP/HTTPS.
///
/// Every call returns a [Result]. Transport failures become [NetworkException],
/// rejected credentials become [UnauthorizedException] (401), and any other
/// non-2xx response becomes a [ServerException] carrying the status code and,
/// when the server sent one, its structured `detail.message`.
class HttpApiClient implements ApiClient {
  HttpApiClient({
    required this.baseUrl,
    Future<String?> Function()? accessTokenProvider,
    Future<void> Function()? onUnauthorized,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  }) : _accessTokenProvider = accessTokenProvider,
       _onUnauthorized = onUnauthorized,
       _http = httpClient ?? http.Client();

  final String baseUrl;

  /// Supplies the bearer token for authenticated calls, read lazily per
  /// request so a sign-in or sign-out mid-run is never stale.
  final Future<String?> Function()? _accessTokenProvider;
  final Future<void> Function()? _onUnauthorized;

  final http.Client _http;
  final Duration timeout;

  Uri _uri(String path, {Map<String, String>? query}) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<Map<String, String>> _headers() async {
    final String? token = await _accessTokenProvider?.call();
    return <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  String? _encodeBody(Object? body) => body == null ? null : jsonEncode(body);

  @override
  Future<Result<Map<String, dynamic>>> get(
    String path, {
    Map<String, String>? query,
  }) => _send(() async {
    final Map<String, String> headers = await _headers();
    return _http.get(_uri(path, query: query), headers: headers);
  });

  @override
  Future<Result<Map<String, dynamic>>> post(String path, {Object? body}) =>
      _send(() async {
        final Map<String, String> headers = await _headers();
        return _http.post(
          _uri(path),
          headers: headers,
          body: _encodeBody(body),
        );
      });

  @override
  Future<Result<Map<String, dynamic>>> postMultipart(
    String path, {
    required Map<String, String> fields,
    required String fileField,
    required String filePath,
    String? filename,
  }) async {
    final String? token = await _accessTokenProvider?.call();
    final request = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll(<String, String>{
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty)
          'Authorization': 'Bearer $token',
      })
      ..fields.addAll(fields)
      ..files.add(await http.MultipartFile.fromPath(
        fileField,
        filePath,
        filename: filename,
      ));

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(timeout),
      );
    } on TimeoutException catch (error) {
      return Err<Map<String, dynamic>>(
        NetworkException('The server did not respond in time.', cause: error),
      );
    } on SocketException catch (error) {
      return Err<Map<String, dynamic>>(
        NetworkException('Could not reach the server.', cause: error),
      );
    } on http.ClientException catch (error) {
      return Err<Map<String, dynamic>>(
        NetworkException('Could not reach the server.', cause: error),
      );
    } on FileSystemException catch (error) {
      return Err<Map<String, dynamic>>(
        NetworkException('The recording could not be read.', cause: error),
      );
    }

    final int code = response.statusCode;
    AppLogger.debug('[LIVE] voice speech API HTTP status=$code');
    final String raw = utf8.decode(response.bodyBytes);
    if (code >= 200 && code < 300) return _decodeSuccess(raw);
    if (code == 401) {
      try {
        await _onUnauthorized?.call();
      } on Object {
        // The storage implementation logs its own failure.
      }
    }
    return Err<Map<String, dynamic>>(_decodeFailure(code, raw));
  }

  @override
  Future<Result<Map<String, dynamic>>> put(String path, {Object? body}) =>
      _send(() async {
        final Map<String, String> headers = await _headers();
        return _http.put(_uri(path), headers: headers, body: _encodeBody(body));
      });

  @override
  Future<Result<Map<String, dynamic>>> patch(String path, {Object? body}) =>
      _send(() async {
        final Map<String, String> headers = await _headers();
        return _http.patch(
          _uri(path),
          headers: headers,
          body: _encodeBody(body),
        );
      });

  @override
  Future<Result<void>> delete(String path) async {
    final Map<String, String> headers = await _headers();
    final Result<Map<String, dynamic>> result = await _send(
      () => _http.delete(_uri(path), headers: headers),
    );
    return switch (result) {
      Ok<Map<String, dynamic>>() => const Ok<void>(null),
      Err<Map<String, dynamic>>(:final AppException error) => Err<void>(error),
    };
  }

  Future<Result<Map<String, dynamic>>> _send(
    Future<http.Response> Function() request,
  ) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException catch (error) {
      return Err<Map<String, dynamic>>(
        NetworkException('The server did not respond in time.', cause: error),
      );
    } on SocketException catch (error) {
      return Err<Map<String, dynamic>>(
        NetworkException('Could not reach the server.', cause: error),
      );
    } on http.ClientException catch (error) {
      return Err<Map<String, dynamic>>(
        NetworkException('Could not reach the server.', cause: error),
      );
    } on IOException catch (error) {
      return Err<Map<String, dynamic>>(
        NetworkException('Could not reach the server.', cause: error),
      );
    }

    final int code = response.statusCode;
    final String raw = utf8.decode(response.bodyBytes);
    if (code >= 200 && code < 300) return _decodeSuccess(raw);
    if (code == 401) {
      // Clear a stale credential before the next request. A storage failure is
      // intentionally isolated so the original server error is still returned.
      try {
        await _onUnauthorized?.call();
      } on Object {
        // The storage implementation logs its own failure.
      }
    }
    return Err<Map<String, dynamic>>(_decodeFailure(code, raw));
  }

  Ok<Map<String, dynamic>> _decodeSuccess(String raw) {
    if (raw.isEmpty) return const Ok<Map<String, dynamic>>(<String, dynamic>{});
    try {
      final Object? decoded = jsonDecode(raw);
      return Ok<Map<String, dynamic>>(
        decoded is Map<String, dynamic>
            ? decoded
            : <String, dynamic>{'value': decoded},
      );
    } on FormatException {
      // A 2xx with a non-JSON body: nothing useful to return, but not an error.
      return const Ok<Map<String, dynamic>>(<String, dynamic>{});
    }
  }

  AppException _decodeFailure(int code, String raw) {
    String message = 'The server rejected the request.';
    String? detailCode;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final Object? detail = decoded['detail'];
        if (detail is String && detail.isNotEmpty) {
          message = detail;
        } else if (detail is Map<String, dynamic>) {
          final Object? detailMessage = detail['message'];
          detailCode = detail['code'] as String?;
          if (detailMessage is String && detailMessage.isNotEmpty) {
            message = detailMessage;
          }
        } else if (detail is List<dynamic>) {
          final List<String> validationMessages = <String>[];
          for (final Object? item in detail) {
            if (item is! Map<String, dynamic>) continue;
            final Object? rawMessage = item['msg'];
            if (rawMessage is! String || rawMessage.isEmpty) continue;
            validationMessages.add(
              rawMessage.replaceFirst(RegExp(r'^Value error,?\s*'), ''),
            );
          }
          if (validationMessages.isNotEmpty) {
            message = validationMessages.join(' ');
          }
        }
      }
    } on FormatException {
      // Non-JSON error body: keep the generic message.
    }

    if (code == 401) {
      return UnauthorizedException(detailCode ?? message);
    }
    return ServerException(message, statusCode: code);
  }
}
