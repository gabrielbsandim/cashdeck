import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/push/push_messaging.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/alerts/alerts_providers.dart';
import 'package:cashdeck/features/alerts/application/register_push_device.dart';
import 'package:cashdeck/features/alerts/data/api_alerts_repository.dart';
import 'package:cashdeck/features/alerts/data/fake_alerts_repository.dart';
import 'package:cashdeck/features/alerts/domain/app_alert.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/builders.dart';
import '../../support/stub_http_adapter.dart';

final class MockAlertsRepository extends Mock implements AlertsRepository;

final class TokenPush implements PushMessaging {
  const new(this.value);

  final String? value;

  @override
  Future<bool> start() async => true;

  @override
  Future<String?> token() async => value;

  @override
  Stream<String> tokenRefreshes() => const Stream.empty();

  @override
  Stream<PushMessage> foreground() => const Stream.empty();

  @override
  Stream<PushMessage> opened() => const Stream.empty();

  @override
  Future<PushMessage?> launchedBy() async => null;
}

Map<String, Object?> alertJson(String id, {String type = 'PAYMENT_PAID'}) => {
  'id': id,
  'type': type,
  'entityId': 'personal',
  'billId': 'bill-1',
  'invoiceId': null,
  'title': 'Conta paga',
  'body': 'Supplier',
  'data': {'hasPixCode': 'true'},
  'createdAt': '2026-10-08T15:00:00.000Z',
  'readAt': null,
};

Dio _api(Map<String, Object?> routes) => stubDio((options) {
  final key = '${options.method} ${options.path}';
  final body = routes[key];
  if (body == null) return const StubResponse(404);
  if (body is StubResponse) return body;
  return StubResponse(200, {'data': body});
});

void main() {
  test('alert kinds read unknown wire values as other', () {
    expect(AlertKind.fromWire('LOW_BALANCE'), AlertKind.lowBalance);
    expect(AlertKind.fromWire('SOMETHING_NEW'), AlertKind.other);
    expect(AlertKind.mutable, isNot(contains(AlertKind.other)));
  });

  test('an alert keeps its first read time and knows about Pix', () {
    final alert = AppAlert(
      id: 'a',
      kind: AlertKind.paymentAssisted,
      title: 't',
      body: 'b',
      createdAt: testNow,
      data: const {'hasPixCode': 'true'},
    );
    final read = alert.read(testNow);
    expect(alert.unread, isTrue);
    expect(read.unread, isFalse);
    expect(read.read(testNow.add(const Duration(days: 1))).readAt, testNow);
    expect(alert.hasPixCode, isTrue);
    expect(alert.read(testNow), read);
  });

  test('registering a device needs a token and a server answer', () async {
    final repository = MockAlertsRepository();
    when(() => repository.registerDevice(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    expect(
      await RegisterPushDevice(repository, const DisabledPushMessaging())(
        platform: 'ANDROID',
      ),
      isFalse,
    );
    expect(
      await RegisterPushDevice(repository, const TokenPush('tok'))(
        platform: 'ANDROID',
      ),
      isTrue,
    );
    verify(() => repository.registerDevice('tok', 'ANDROID')).called(1);
    when(() => repository.registerDevice(any(), any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    expect(
      await RegisterPushDevice(repository, const DisabledPushMessaging())(
        platform: 'IOS',
        token: 'fresh',
      ),
      isFalse,
    );
  });

  test('the fake inbox reads, mutes and registers', () async {
    final repository = FakeAlertsRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    );
    final page = (await repository.list() as Ok<AlertPage>).value;
    expect(page.items, hasLength(3));
    expect(page.nextCursor, isNull);
    expect(await repository.unreadCount(), const Ok(2));
    final read = await repository.markRead('alert-due');
    expect((read as Ok<AppAlert>).value.readAt, testNow);
    expect(
      await repository.markRead('nope'),
      const Err<AppAlert>(NotFoundFailure()),
    );
    expect(await repository.markAllRead(), const Ok(1));
    expect(await repository.unreadCount(), const Ok(0));
    final muted = await repository.setMuted(AlertKind.paymentPaid, muted: true);
    expect(
      (muted as Ok<Map<AlertKind, bool>>).value[AlertKind.paymentPaid],
      isTrue,
    );
    await repository.setMuted(AlertKind.paymentPaid, muted: false);
    final settings = await repository.settings();
    expect(
      (settings as Ok<Map<AlertKind, bool>>).value.values,
      everyElement(isFalse),
    );
    await repository.registerDevice('tok', 'ANDROID');
    expect(repository.devices, ['ANDROID:tok']);
    await repository.removeDevice('tok');
    expect(repository.devices, isEmpty);
  });

  test('unregistering a device needs a token and a server answer', () async {
    final repository = MockAlertsRepository();
    when(() => repository.removeDevice(any()))
        .thenAnswer((_) async => const Ok(null));
    expect(
      await UnregisterPushDevice(repository, const DisabledPushMessaging())(),
      isFalse,
    );
    expect(
      await UnregisterPushDevice(repository, const TokenPush('tok'))(),
      isTrue,
    );
    verify(() => repository.removeDevice('tok')).called(1);
    when(() => repository.removeDevice(any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    expect(
      await UnregisterPushDevice(repository, const TokenPush('tok'))(),
      isFalse,
    );
  });

  test('the API inbox pages, reads and mutes', () async {
    final dio = _api({
      'GET /api/v1/alerts': StubResponse(200, {
        'data': [alertJson('a1'), alertJson('a2', type: 'NEW_TYPE')],
        'nextCursor': '2',
      }),
      'GET /api/v1/alerts/unread-count': {'unread': 4},
      'POST /api/v1/alerts/a%2F1/read': {
        ...alertJson('a/1'),
        'readAt': '2026-10-08T16:00:00.000Z',
        'data': null,
      },
      'POST /api/v1/alerts/read-all': {'updated': 3},
      'GET /api/v1/alerts/settings': {
        'types': [
          {'type': 'PAYMENT_PAID', 'muted': true},
          {'type': 'NEW_TYPE', 'muted': false},
        ],
      },
      'PATCH /api/v1/alerts/settings': {
        'types': [
          {'type': 'BILL_DUE_SOON', 'muted': true},
        ],
      },
      'POST /api/v1/devices': const StubResponse(201, {
        'data': {'token': 'tok'},
      }),
      'DELETE /api/v1/devices/a%3Ab': {'removed': true},
    });
    final repository = ApiAlertsRepository(dio);

    final page = (await repository.list(cursor: 'c1') as Ok<AlertPage>).value;
    expect(page.items.map((alert) => alert.kind), [
      AlertKind.paymentPaid,
      AlertKind.other,
    ]);
    expect(page.items.first.hasPixCode, isTrue);
    expect(page.nextCursor, '2');
    expect(adapterOf(dio).requests.first.queryParameters, {
      'cursor': 'c1',
      'limit': 30,
    });
    await repository.list();
    expect(adapterOf(dio).requests[1].queryParameters, {'limit': 30});
    expect(await repository.unreadCount(), const Ok(4));
    final read = (await repository.markRead('a/1') as Ok<AppAlert>).value;
    expect(read.data, isEmpty);
    expect(read.readAt, DateTime.utc(2026, 10, 8, 16));
    expect(await repository.markAllRead(), const Ok(3));
    expect(
      await repository.settings(),
      const Ok({AlertKind.paymentPaid: true}),
    );
    expect(
      await repository.setMuted(AlertKind.billDueSoon, muted: true),
      const Ok({AlertKind.billDueSoon: true}),
    );
    expect(adapterOf(dio).requests.last.data, {
      'muted': {'BILL_DUE_SOON': true},
    });
    expect(await repository.registerDevice('tok', 'ANDROID'), isA<Ok<void>>());
    expect(adapterOf(dio).requests.last.data, {
      'token': 'tok',
      'platform': 'ANDROID',
    });
    expect(await repository.removeDevice('a:b'), isA<Ok<void>>());
  });

  test('a failed API call is a failure value', () async {
    final repository = ApiAlertsRepository(_api({}));
    expect(await repository.unreadCount(), isA<Err<int>>());
  });

  test('the backend picks the repository', () {
    final fake = ProviderContainer(
      overrides: [clockProvider.overrideWithValue(FixedClock(testNow))],
    );
    addTearDown(fake.dispose);
    expect(fake.read(alertsRepositoryProvider), isA<FakeAlertsRepository>());
    expect(fake.read(registerPushDeviceProvider), isNotNull);

    final api = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(backend: Backend.api, apiBaseUrl: 'https://api.test'),
        ),
      ],
    );
    addTearDown(api.dispose);
    expect(api.read(alertsRepositoryProvider), isA<ApiAlertsRepository>());
  });
}
