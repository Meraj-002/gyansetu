import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/core/config/api_config.dart';
import 'package:gyan_setu_ai/core/errors/app_exception.dart';
import 'package:gyan_setu_ai/core/utils/result.dart';
import 'package:gyan_setu_ai/services/api/api_endpoints.dart';
import 'package:gyan_setu_ai/services/api/http_api_client.dart';

/// End-to-end smoke test against the real FastAPI backend.
///
/// Deliberately not part of the normal suite: it needs uvicorn running on the
/// base URL in [ApiConfig]. Run it with:
///
///     flutter test --dart-define=LIVE_BACKEND=true \
///       test/live_backend_test.dart
const bool live = bool.fromEnvironment('LIVE_BACKEND');

void main() {
  if (!live) {
    test(
      'live backend smoke test is skipped unless LIVE_BACKEND is set',
      () {},
      skip: 'not a live run',
    );
    return;
  }

  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('real register -> login -> authenticated sync round-trip', () async {
    final HttpApiClient api = HttpApiClient(baseUrl: ApiConfig.baseUrl);
    final String mobile =
        '7000${(DateTime.now().millisecondsSinceEpoch % 1000000).toString().padLeft(6, '0')}';
    const String pin = '1234';

    final Result<Map<String, dynamic>> register = await api.post(
      ApiEndpoints.register,
      body: <String, dynamic>{
        'displayName': 'Smoke Test Teacher',
        'mobile': mobile,
        'password': pin,
      },
    );
    expect(
      register,
      isA<Ok<Map<String, dynamic>>>(),
      reason: 'register failed: ${_describe(register)}',
    );

    final String token =
        (register as Ok<Map<String, dynamic>>).value['accessToken'] as String;
    expect(token, isNotEmpty);

    final Result<Map<String, dynamic>> login = await api.post(
      ApiEndpoints.login,
      body: <String, dynamic>{'identifier': mobile, 'password': pin},
    );
    expect(login, isA<Ok<Map<String, dynamic>>>(), reason: 'login failed');
    expect(
      (login as Ok<Map<String, dynamic>>).value['account'],
      isA<Map<String, dynamic>>(),
    );

    final HttpApiClient authed = HttpApiClient(
      baseUrl: ApiConfig.baseUrl,
      accessTokenProvider: () async => token,
    );
    final Result<Map<String, dynamic>> status = await authed.get(
      ApiEndpoints.syncStatus,
    );
    expect(status, isA<Ok<Map<String, dynamic>>>(), reason: 'status failed');

    final Result<Map<String, dynamic>> push = await authed.post(
      ApiEndpoints.syncPush,
      body: <String, dynamic>{'deviceId': 'smoke-device', 'documents': <Object>[]},
    );
    expect(
      push,
      isA<Ok<Map<String, dynamic>>>(),
      reason: 'push failed: ${_describe(push)}',
    );
    expect(
      (push as Ok<Map<String, dynamic>>).value['serverNow'],
      isA<String>(),
    );
  });
}

String _describe(Result<Map<String, dynamic>> result) => switch (result) {
      Ok<Map<String, dynamic>>() => 'unexpected success',
      Err<Map<String, dynamic>>(:final AppException error) => error.toString(),
    };