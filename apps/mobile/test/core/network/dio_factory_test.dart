import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/network/dio_factory.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/stub_http_adapter.dart';

void main() {
  const config = AppConfig(backend: Backend.api, apiBaseUrl: 'https://x.test');

  test('points at the configured API and sends JSON', () {
    final dio = createApiDio(config);

    expect(dio.options.baseUrl, 'https://x.test');
    expect(dio.options.headers['X-Client'], 'mobile');
    expect(dio.options.headers.containsKey('Authorization'), isFalse);
    expect(dio.options.contentType, contains('application/json'));
  });

  test('a session points at its server and signs requests', () {
    final dio = createApiDio(
      config,
      session: const ServerCredentials(
        baseUrl: 'https://home.test',
        token: 'token-1234',
      ),
    );

    expect(dio.options.baseUrl, 'https://home.test');
    expect(dio.options.headers['Authorization'], 'Bearer token-1234');
  });

  test('a 401 calls back, other errors do not', () async {
    var unauthorized = 0;
    final dio = createApiDio(config, onUnauthorized: () => unauthorized++)
      ..httpClientAdapter = StubHttpAdapter(
        (options) => StubResponse(options.path == '/revoked' ? 401 : 500),
      );

    await expectLater(
      dio.get<Object?>('/revoked'),
      throwsA(isA<DioException>()),
    );
    await expectLater(
      dio.get<Object?>('/broken'),
      throwsA(isA<DioException>()),
    );

    expect(unauthorized, 1);
  });
}
