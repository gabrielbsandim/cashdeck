import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/session/credential_store.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:cashdeck/core/session/server_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

final class _MockStorage extends Mock implements FlutterSecureStorage;

void main() {
  const credentials = ServerCredentials(
    baseUrl: 'https://home.test',
    token: 'token-1234',
  );

  test('normalizes and validates the server address', () {
    expect(normalizeServerUrl(' cashdeck.casa/ '), 'https://cashdeck.casa');
    expect(normalizeServerUrl('http://10.0.0.2:3000'), 'http://10.0.0.2:3000');
    expect(isValidServerUrl('cashdeck.casa'), isTrue);
    expect(isValidServerUrl('ftp://cashdeck.casa'), isFalse);
    expect(isValidServerUrl(''), isFalse);
    expect(isValidServerUrl('http://[::1'), isFalse);
    expect(credentials.host, 'home.test');
    expect(const ServerCredentials(baseUrl: '::', token: 't').host, '::');
  });

  test('keeps credentials in memory', () async {
    final store = InMemoryCredentialStore();
    expect(await store.read(), isNull);
    await store.write(credentials);
    expect(await store.read(), credentials);
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('keeps credentials in the secure storage', () async {
    final storage = _MockStorage();
    final values = <String, String>{};
    when(() => storage.read(key: any(named: 'key')))
        .thenAnswer((call) async => values[call.namedArguments[#key]]);
    when(
      () => storage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((call) async {
      values[call.namedArguments[#key] as String] =
          call.namedArguments[#value] as String;
    });
    when(() => storage.delete(key: any(named: 'key')))
        .thenAnswer((call) async => values.remove(call.namedArguments[#key]));
    final store = SecureCredentialStore(storage);

    expect(await store.read(), isNull);
    await store.write(credentials);
    expect(values[SecureCredentialStore.tokenKey], 'token-1234');
    expect(await store.read(), credentials);
    await store.clear();
    expect(values, isEmpty);
    expect(const SecureCredentialStore(), isA<CredentialStore>());
  });

  test('the fake backend starts signed in, the API signed out', () {
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
      on(Backend.fake).read(serverSessionProvider),
      ServerCredentials.demo,
    );
    expect(on(Backend.api).read(serverSessionProvider), isNull);
  });

  test('signs in and out through the store', () async {
    final store = InMemoryCredentialStore();
    final container = ProviderContainer(
      overrides: [
        credentialStoreProvider.overrideWithValue(store),
        initialCredentialsProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);
    final session = container.read(serverSessionProvider.notifier);

    await session.signIn(credentials);
    expect(container.read(serverSessionProvider), credentials);
    expect(await store.read(), credentials);
    expect(container.read(dioProvider).options.baseUrl, 'https://home.test');

    await session.signOut();
    expect(container.read(serverSessionProvider), isNull);
    expect(await store.read(), isNull);
  });
}
