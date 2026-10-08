import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:cashdeck/features/auth/application/sign_in.dart';
import 'package:cashdeck/features/auth/auth_providers.dart';
import 'package:cashdeck/features/auth/data/api_server_access_repository.dart';
import 'package:cashdeck/features/auth/data/fake_server_access_repository.dart';
import 'package:cashdeck/features/auth/domain/server_access.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/stub_http_adapter.dart';

void main() {
  test('flags an invalid address and an empty token', () {
    expect(signInErrorsOf(serverUrl: 'cashdeck.casa', token: 't'), isEmpty);
    expect(signInErrorsOf(serverUrl: 'ftp://x.casa', token: ' '), {
      SignInField.serverUrl,
      SignInField.token,
    });
  });

  group('SignIn', () {
    final fake = FakeServerAccessRepository(latency: Duration.zero);
    final signIn = SignIn(fake);

    test('refuses an invalid form without calling the server', () async {
      final result = await signIn(serverUrl: '', token: '');

      expect(
        result,
        const Err<ServerCredentials>(ValidationFailure('serverUrl, token')),
      );
    });

    test('normalizes the address and trims the token', () async {
      final result = await signIn(
        serverUrl: 'cashdeck.casa/',
        token: ' token-1234 ',
      );

      expect(
        result,
        const Ok(
          ServerCredentials(
            baseUrl: 'https://cashdeck.casa',
            token: 'token-1234',
          ),
        ),
      );
    });

    test('passes on what the server says', () async {
      final result = await signIn(serverUrl: 'cashdeck.casa', token: 'short');

      expect(result, const Err<ServerCredentials>(UnauthorizedFailure()));
    });
  });

  group('ApiServerAccessRepository', () {
    const credentials = ServerCredentials(
      baseUrl: 'https://home.test',
      token: 'token-1234',
    );

    test('asks the given server with the given token', () async {
      final dio = stubDio(
        (_) => const StubResponse(200, {
          'data': {'ok': true},
        }),
      );

      final result = await ApiServerAccessRepository(dio).check(credentials);

      expect(result, isA<Ok<void>>());
      final request = adapterOf(dio).requests.single;
      expect(request.uri.toString(), 'https://home.test/api/v1/auth/check');
      expect(request.headers['Authorization'], 'Bearer token-1234');
    });

    test('maps a refused token', () async {
      final dio = stubDio((_) => const StubResponse(401));

      final result = await ApiServerAccessRepository(dio).check(credentials);

      expect(result, const Err<void>(UnauthorizedFailure()));
    });
  });

  test('picks the repository for the backend', () {
    ProviderContainer on(Backend backend) {
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(
            AppConfig(backend: backend, apiBaseUrl: 'https://x.test'),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    expect(
      on(Backend.fake).read(serverAccessRepositoryProvider),
      isA<FakeServerAccessRepository>(),
    );
    expect(on(Backend.api).read(signInProvider), isA<SignIn>());
    expect(
      on(Backend.api).read(serverAccessRepositoryProvider),
      isA<ApiServerAccessRepository>(),
    );
  });
}
