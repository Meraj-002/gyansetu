import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/core/errors/app_exception.dart';
import 'package:gyan_setu_ai/core/utils/result.dart';
import 'package:gyan_setu_ai/services/api/http_api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('HttpApiClient', () {
    test('attaches the bearer token when one is available', () async {
      String? authorization;
      final http.Client mock = MockClient((http.Request request) async {
        authorization = request.headers['Authorization'];
        return http.Response('{"ok":true}', 200);
      });
      final HttpApiClient api = HttpApiClient(
        baseUrl: 'http://example.test',
        accessTokenProvider: () async => 'secret-token',
        httpClient: mock,
      );

      final Result<Map<String, dynamic>> result = await api.get('/me');

      expect(result, isA<Ok<Map<String, dynamic>>>());
      expect(authorization, 'Bearer secret-token');
    });

    test('omits the header when there is no token', () async {
      String? authorization;
      final http.Client mock = MockClient((http.Request request) async {
        authorization = request.headers['Authorization'];
        return http.Response('{}', 200);
      });
      final HttpApiClient api = HttpApiClient(
        baseUrl: 'http://example.test',
        httpClient: mock,
      );

      await api.get('/me');

      expect(authorization, isNull);
    });

    test('appends query parameters on GET', () async {
      Uri? seen;
      final http.Client mock = MockClient((http.Request request) async {
        seen = request.url;
        return http.Response('{}', 200);
      });
      final HttpApiClient api = HttpApiClient(
        baseUrl: 'http://example.test',
        httpClient: mock,
      );

      await api.get('/lessons', query: <String, String>{'q': 'math', 'n': '4'});

      expect(seen!.path, '/lessons');
      expect(seen!.queryParameters['q'], 'math');
      expect(seen!.queryParameters['n'], '4');
    });

    test('posts a JSON body and content type', () async {
      Object? body;
      String? contentType;
      final http.Client mock = MockClient((http.Request request) async {
        body = request.body;
        contentType = request.headers['Content-Type'];
        return http.Response('{}', 200);
      });
      final HttpApiClient api = HttpApiClient(
        baseUrl: 'http://example.test',
        httpClient: mock,
      );

      await api.post('/x', body: <String, dynamic>{'a': 1});

      expect(contentType, 'application/json');
      expect(jsonDecode(body! as String), <String, dynamic>{'a': 1});
    });

    test(
      '401 maps to UnauthorizedException carrying the detail code',
      () async {
        final http.Client mock = MockClient((http.Request request) async {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'detail': <String, dynamic>{
                'code': 'invalid_credentials',
                'message': 'Bad PIN',
              },
            }),
            401,
          );
        });
        final HttpApiClient api = HttpApiClient(
          baseUrl: 'http://example.test',
          httpClient: mock,
        );

        final Result<Map<String, dynamic>> result = await api.post('/login');

        final Err<Map<String, dynamic>> err =
            result as Err<Map<String, dynamic>>;
        expect(err.error, isA<UnauthorizedException>());
        expect(err.error.message, 'invalid_credentials');
      },
    );

    test('401 clears the stored credential through the callback', () async {
      bool cleared = false;
      final http.Client mock = MockClient((http.Request request) async {
        return http.Response('{}', 401);
      });
      final HttpApiClient api = HttpApiClient(
        baseUrl: 'http://example.test',
        onUnauthorized: () async => cleared = true,
        httpClient: mock,
      );

      await api.get('/me');

      expect(cleared, isTrue);
    });

    test(
      'other non-2xx statuses map to ServerException with the code',
      () async {
        final http.Client mock = MockClient((http.Request request) async {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'detail': <String, dynamic>{'message': 'service busy'},
            }),
            503,
          );
        });
        final HttpApiClient api = HttpApiClient(
          baseUrl: 'http://example.test',
          httpClient: mock,
        );

        final Result<Map<String, dynamic>> result = await api.get('/x');

        final Err<Map<String, dynamic>> err =
            result as Err<Map<String, dynamic>>;
        expect(err.error, isA<ServerException>());
        expect((err.error as ServerException).statusCode, 503);
        expect(err.error.message, 'service busy');
      },
    );

    test('422 surfaces FastAPI validation details', () async {
      final http.Client mock = MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'detail': <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'value_error',
                'loc': <String>['body'],
                'msg': 'Value error, this language pair is not supported yet',
              },
            ],
          }),
          422,
        );
      });
      final HttpApiClient api = HttpApiClient(
        baseUrl: 'http://example.test',
        httpClient: mock,
      );

      final Result<Map<String, dynamic>> result = await api.post('/translate');

      final Err<Map<String, dynamic>> err = result as Err<Map<String, dynamic>>;
      expect(err.error, isA<ServerException>());
      expect(err.error.message, 'this language pair is not supported yet');
      expect((err.error as ServerException).statusCode, 422);
    });

    test('a request that times out becomes a NetworkException', () async {
      final http.Client mock = MockClient((http.Request request) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response('{}', 200);
      });
      final HttpApiClient api = HttpApiClient(
        baseUrl: 'http://example.test',
        httpClient: mock,
        timeout: const Duration(milliseconds: 10),
      );

      final Result<Map<String, dynamic>> result = await api.get('/x');

      expect(result, isA<Err<Map<String, dynamic>>>());
      expect(
        (result as Err<Map<String, dynamic>>).error,
        isA<NetworkException>(),
      );
    });

    test('a 2xx with an empty or non-JSON body is success', () async {
      final http.Client mock = MockClient(
        (http.Request request) async => http.Response(
          'not json',
          204,
          headers: <String, String>{'content-type': 'text/plain'},
        ),
      );
      final HttpApiClient api = HttpApiClient(
        baseUrl: 'http://example.test',
        httpClient: mock,
      );

      final Result<void> result = await api.delete('/x');

      expect(result, isA<Ok<void>>());
    });
  });
}
