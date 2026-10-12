import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/push/push_messaging.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/session/credential_store.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/alerts/application/register_push_device.dart';
import 'package:cashdeck/features/alerts/data/fake_alerts_repository.dart';
import 'package:cashdeck/features/auth/application/device_sessions_use_cases.dart';
import 'package:cashdeck/features/auth/application/restore_session.dart';
import 'package:cashdeck/features/auth/application/sign_in.dart';
import 'package:cashdeck/features/auth/application/sign_out.dart';
import 'package:cashdeck/features/auth/auth_providers.dart';
import 'package:cashdeck/features/auth/data/api_device_sessions_repository.dart';
import 'package:cashdeck/features/auth/data/api_server_access_repository.dart';
import 'package:cashdeck/features/auth/data/device_identity.dart';
import 'package:cashdeck/features/auth/data/device_session_dtos.dart';
import 'package:cashdeck/features/auth/data/fake_device_sessions_repository.dart';
import 'package:cashdeck/features/auth/data/fake_server_access_repository.dart';
import 'package:cashdeck/features/auth/domain/device_session.dart';
import 'package:cashdeck/features/auth/domain/server_access.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/builders.dart';
import '../../support/stub_http_adapter.dart';

final class _TokenPush implements PushMessaging {
  const new();

  @override
  Future<bool> start() async => true;

  @override
  Future<String?> token() async => 'tok';

  @override
  Stream<String> tokenRefreshes() => const Stream.empty();

  @override
  Stream<PushMessage> foreground() => const Stream.empty();

  @override
  Stream<PushMessage> opened() => const Stream.empty();

  @override
  Future<PushMessage?> launchedBy() async => null;
}

/// Answers each exchange with the next scripted result.
final class _ScriptedAccess implements ServerAccessRepository {
  new(this.answer);

  Result<ServerCredentials> answer;
  final List<ServerCredentials> exchanged = [];

  @override
  Future<Result<ServerCredentials>> exchange(
    ServerCredentials staticToken,
    DeviceIdentity device,
  ) async {
    exchanged.add(staticToken);
    return answer;
  }
}

const _phone = DeviceIdentity(
  name: 'Android',
  platform: SessionPlatform.android,
);

const _legacy = ServerCredentials(
  baseUrl: 'https://home.test',
  token: 'static-token',
);

const _session = ServerCredentials(
  baseUrl: 'https://home.test',
  token: 'session-token',
);

DeviceSession _device(String id, {bool current = false, int daysAgo = 0}) =>
    DeviceSession(
      id: id,
      deviceName: id,
      platform: SessionPlatform.android,
      createdAt: testNow.subtract(const Duration(days: 30)),
      lastUsedAt: testNow.subtract(Duration(days: daysAgo)),
      current: current,
    );

Map<String, Object?> _sessionJson(String id, {bool current = false}) => {
  'id': id,
  'deviceName': 'Pixel',
  'platform': 'ANDROID',
  'createdAt': '2026-10-01T12:00:00.000Z',
  'lastUsedAt': '2026-10-10T12:00:00.000Z',
  'expiresAt': '2026-11-09T12:00:00.000Z',
  'current': current,
};

void main() {
  test('flags an invalid address and an empty token', () {
    expect(signInErrorsOf(serverUrl: 'cashdeck.casa', token: 't'), isEmpty);
    expect(signInErrorsOf(serverUrl: 'ftp://x.casa', token: ' '), {
      SignInField.serverUrl,
      SignInField.token,
    });
  });

  test('names this phone by its platform', () {
    expect(
      deviceIdentityFor('ios'),
      const DeviceIdentity(name: 'iPhone', platform: SessionPlatform.ios),
    );
    expect(deviceIdentityFor('android'), _phone);
    expect(deviceIdentityFor('linux'), _phone);
  });

  test('devices and sessions compare by value', () {
    final name = ['Android'].join();
    expect(
      DeviceIdentity(name: name, platform: SessionPlatform.android),
      _phone,
    );
    expect(_device('a'), _device('a'));
    expect(_device('a'), isNot(_device('a', current: true)));
    expect(
      [for (final p in SessionPlatform.values) sessionPlatformToJson(p)],
      ['ANDROID', 'IOS', 'WEB'],
    );
  });

  test('orders this phone first, then by last use', () {
    final ordered = orderDeviceSessions([
      _device('old', daysAgo: 9),
      _device('recent', daysAgo: 1),
      _device('here', current: true, daysAgo: 3),
    ]);
    expect(
      [for (final session in ordered) session.id],
      ['here', 'recent', 'old'],
    );
  });

  group('SignOut', () {
    test('forgets the push token and the server session first', () async {
      final alerts = FakeAlertsRepository(
        FixedClock(testNow),
        latency: Duration.zero,
      );
      await alerts.registerDevice('tok', 'ANDROID', locale: 'pt');
      final sessions = FakeDeviceSessionsRepository(
        now: testNow,
        latency: Duration.zero,
      );
      final seen = <List<String>>[];
      final signOut = SignOut(
        UnregisterPushDevice(alerts, const _TokenPush()),
        () async => seen.add([...alerts.devices, 'ended ${sessions.ended}']),
        () async => seen.add(['stopped']),
        sessions,
      );

      await signOut();

      expect(seen, [
        ['stopped'],
        ['ended true'],
      ]);
    });

    test('still leaves without a server session to end', () async {
      final alerts = FakeAlertsRepository(
        FixedClock(testNow),
        latency: Duration.zero,
      );
      var cleared = false;
      await SignOut(
        UnregisterPushDevice(alerts, const _TokenPush()),
        () async => cleared = true,
      )();
      expect(cleared, isTrue);
    });
  });

  group('SignIn', () {
    final fake = FakeServerAccessRepository(latency: Duration.zero);
    final signIn = SignIn(fake, _phone);

    test('refuses an invalid form without calling the server', () async {
      final result = await signIn(serverUrl: '', token: '');

      expect(
        result,
        const Err<ServerCredentials>(ValidationFailure('serverUrl, token')),
      );
      expect(fake.exchanged, isEmpty);
    });

    test('trades the trimmed static token for a session', () async {
      final result = await signIn(
        serverUrl: 'cashdeck.casa/',
        token: ' token-1234 ',
      );

      expect(
        result,
        const Ok(
          ServerCredentials(
            baseUrl: 'https://cashdeck.casa',
            token: 'session-token-1234',
          ),
        ),
      );
      expect(fake.exchanged.last, (
        const ServerCredentials(
          baseUrl: 'https://cashdeck.casa',
          token: 'token-1234',
        ),
        _phone,
      ));
    });

    test('passes on what the server says', () async {
      final result = await signIn(serverUrl: 'cashdeck.casa', token: 'short');

      expect(result, const Err<ServerCredentials>(UnauthorizedFailure()));
    });
  });

  group('RestoreSession', () {
    test('keeps a session and drops any leftover static token', () async {
      final store = InMemoryCredentialStore(_session, _legacy);
      final access = _ScriptedAccess(const Ok(_session));

      expect(await RestoreSession(store, access, _phone)(), _session);
      expect(await store.readLegacy(), isNull);
      expect(access.exchanged, isEmpty);
    });

    test('starts signed out with nothing stored', () async {
      final access = _ScriptedAccess(const Ok(_session));

      expect(
        await RestoreSession(InMemoryCredentialStore(), access, _phone)(),
        isNull,
      );
      expect(access.exchanged, isEmpty);
    });

    test('exchanges a legacy static token once and deletes it', () async {
      final store = InMemoryCredentialStore(null, _legacy);
      final access = _ScriptedAccess(const Ok(_session));

      expect(await RestoreSession(store, access, _phone)(), _session);
      expect(access.exchanged, [_legacy]);
      expect(await store.read(), _session);
      expect(await store.readLegacy(), isNull);
    });

    test('deletes a refused static token and signs out', () async {
      final store = InMemoryCredentialStore(null, _legacy);
      final access = _ScriptedAccess(const Err(UnauthorizedFailure()));

      expect(await RestoreSession(store, access, _phone)(), isNull);
      expect(await store.readLegacy(), isNull);
      expect(await store.read(), isNull);
    });

    test('keeps the static token when offline, to try again', () async {
      final store = InMemoryCredentialStore(null, _legacy);
      final access = _ScriptedAccess(const Err(NetworkFailure()));

      expect(await RestoreSession(store, access, _phone)(), isNull);
      expect(await store.readLegacy(), _legacy);
    });
  });

  group('ApiServerAccessRepository', () {
    test(
      'posts the device to the given server with the static token',
      () async {
        final dio = stubDio(
          (_) => const StubResponse(201, {
            'data': {
              'token': 'session-abc',
              'expiresAt': '2026-11-10T12:00:00.000Z',
              'session': <String, Object?>{},
            },
          }),
        );

        final result = await ApiServerAccessRepository(dio)
            .exchange(_legacy, _phone);

        expect(result, const Ok(_session2));
        final request = adapterOf(dio).requests.single;
        expect(request.uri.toString(), 'https://home.test/api/v1/sessions');
        expect(request.method, 'POST');
        expect(request.headers['Authorization'], 'Bearer static-token');
        expect(request.data, {'deviceName': 'Android', 'platform': 'ANDROID'});
      },
    );

    test('maps a refused token', () async {
      final dio = stubDio((_) => const StubResponse(401));

      final result = await ApiServerAccessRepository(dio)
          .exchange(_legacy, _phone);

      expect(result, const Err<ServerCredentials>(UnauthorizedFailure()));
    });
  });

  group('ApiDeviceSessionsRepository', () {
    test('lists, revokes and ends the current session', () async {
      final dio = stubDio(
        (options) => switch (options.method) {
          'GET' => StubResponse(200, {
            'data': [_sessionJson('s1', current: true), _sessionJson('s2')],
          }),
          _ => const StubResponse(200, {
            'data': {'id': 'x'},
          }),
        },
      );
      final repository = ApiDeviceSessionsRepository(dio);

      final listed = await repository.list();
      expect(listed, isA<Ok<List<DeviceSession>>>());
      final sessions = (listed as Ok<List<DeviceSession>>).value;
      expect(sessions.first, isA<DeviceSession>());
      expect(sessions.first.current, isTrue);
      expect(sessions.first.platform, SessionPlatform.android);
      expect(sessions.first.lastUsedAt, DateTime.utc(2026, 10, 10, 12));

      expect(await repository.revoke('a/b'), isA<Ok<void>>());
      expect(await repository.endCurrent(), isA<Ok<void>>());
      expect(
        [for (final r in adapterOf(dio).requests) r.uri.path],
        [
          '/api/v1/sessions',
          '/api/v1/sessions/a%2Fb',
          '/api/v1/sessions/current',
        ],
      );
    });

    test('maps a platform it does not know to a failure', () async {
      final dio = stubDio(
        (_) => StubResponse(200, {
          'data': [
            {..._sessionJson('s1'), 'platform': 'PALM'},
          ],
        }),
      );

      expect(
        await ApiDeviceSessionsRepository(dio).list(),
        const Err<List<DeviceSession>>(UnexpectedFailure()),
      );
    });
  });

  group('device session use cases', () {
    test('list this phone first and revoke another device', () async {
      final fake = FakeDeviceSessionsRepository(
        now: testNow,
        latency: Duration.zero,
      );

      final listed = await ListDeviceSessions(fake)();
      final sessions = (listed as Ok<List<DeviceSession>>).value;
      expect(sessions.first.current, isTrue);
      expect(sessions, hasLength(2));

      expect(
        await RevokeDeviceSession(fake)('session-tablet'),
        isA<Ok<void>>(),
      );
      expect(
        await RevokeDeviceSession(fake)('session-tablet'),
        const Err<void>(NotFoundFailure()),
      );
      expect(
        ((await ListDeviceSessions(fake)()) as Ok<List<DeviceSession>>).value,
        hasLength(1),
      );
    });

    test('pass a failure on', () async {
      final dio = stubDio((_) => const StubResponse(500));

      expect(
        await ListDeviceSessions(ApiDeviceSessionsRepository(dio))(),
        const Err<List<DeviceSession>>(ServerFailure()),
      );
    });
  });

  test('picks the repositories for the backend', () {
    ProviderContainer on(Backend backend) {
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(
            AppConfig(backend: backend, apiBaseUrl: 'https://x.test'),
          ),
          clockProvider.overrideWithValue(FixedClock(testNow)),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    expect(
      on(Backend.fake).read(serverAccessRepositoryProvider),
      isA<FakeServerAccessRepository>(),
    );
    expect(
      on(Backend.fake).read(deviceSessionsRepositoryProvider),
      isA<FakeDeviceSessionsRepository>(),
    );
    expect(on(Backend.api).read(signInProvider), isA<SignIn>());
    expect(
      on(Backend.api).read(serverAccessRepositoryProvider),
      isA<ApiServerAccessRepository>(),
    );
    expect(
      on(Backend.api).read(deviceSessionsRepositoryProvider),
      isA<ApiDeviceSessionsRepository>(),
    );
    expect(on(Backend.api).read(deviceIdentityProvider), isA<DeviceIdentity>());
  });
}

const _session2 = ServerCredentials(
  baseUrl: 'https://home.test',
  token: 'session-abc',
);
