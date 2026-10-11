import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/network/dio_factory.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:cashdeck/core/session/server_session.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/safe_mode_support.dart';
import '../../support/stub_http_adapter.dart';

void main() {
  test('builds Dio from the config and the system clock', () {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(backend: Backend.api, apiBaseUrl: 'https://x.test'),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(dioProvider).options.baseUrl, 'https://x.test');
    expect(container.read(clockProvider), isA<SystemClock>());
  });

  test('a signed-in client holds writes back away from a safe zone', () async {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(backend: Backend.api, apiBaseUrl: 'https://x.test'),
        ),
        initialCredentialsProvider.overrideWithValue(
          const ServerCredentials(baseUrl: 'https://x.test', token: 'token'),
        ),
        ...safeModeOverrides(),
      ],
    );
    addTearDown(container.dispose);
    final dio = container.read(dioProvider)
      ..httpClientAdapter = StubHttpAdapter((_) => const StubResponse(200));

    await expectLater(
      dio.post<Object?>('/bills/1/pay'),
      throwsA(
        isA<DioException>().having(
          (error) => error.error,
          'error',
          isA<SafeModeRefusal>(),
        ),
      ),
    );
  });
}
