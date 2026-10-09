import 'dart:async';

import 'package:cashdeck/core/push/firebase_push_messaging.dart';
import 'package:cashdeck/core/push/push_messaging.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

final class MockMessaging extends Mock implements FirebaseMessaging;

final class FakeSettings extends Fake implements NotificationSettings;

const _remote = RemoteMessage(
  notification: RemoteNotification(title: 'Conta paga', body: 'Supplier'),
  data: {'billId': 'bill-1', 'count': 2},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('push is off by default', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final push = container.read(pushMessagingProvider);
    expect(await push.start(), isFalse);
    expect(await push.token(), isNull);
    expect(await push.launchedBy(), isNull);
    expect(await push.tokenRefreshes().isEmpty, isTrue);
    expect(await push.foreground().isEmpty, isTrue);
    expect(await push.opened().isEmpty, isTrue);
  });

  test('a remote message keeps its texts and stringifies its data', () {
    final message = pushMessageOf(_remote);
    expect(message.title, 'Conta paga');
    expect(message.body, 'Supplier');
    expect(message.data, {'billId': 'bill-1', 'count': '2'});
    expect(message.billId, 'bill-1');
    expect(pushMessageOf(const RemoteMessage()).title, isNull);
    expect(pushMessageOf(_remote), pushMessageOf(_remote));
  });

  test('without a Firebase project push stays off', () async {
    final push = FirebasePushMessaging();
    expect(await push.start(), isFalse);
    expect(await push.start(), isFalse);
    expect(await push.token(), isNull);
    expect(await push.launchedBy(), isNull);
    expect(await push.tokenRefreshes().isEmpty, isTrue);
    expect(await push.foreground().isEmpty, isTrue);
    expect(await push.opened().isEmpty, isTrue);
  });

  test('a Firebase app without messaging stays off', () async {
    final push = FirebasePushMessaging(initialize: () async {});
    expect(await push.start(), isFalse);
  });

  test('with Firebase it asks permission and relays messages', () async {
    final messaging = MockMessaging();
    when(messaging.requestPermission).thenAnswer((_) async => FakeSettings());
    when(messaging.getToken).thenAnswer((_) async => 'token-1');
    when(() => messaging.onTokenRefresh)
        .thenAnswer((_) => Stream.value('token-2'));
    when(messaging.getInitialMessage).thenAnswer((_) async => _remote);
    final foreground = StreamController<RemoteMessage>();
    final push = FirebasePushMessaging(
      initialize: () async {},
      messaging: () => messaging,
      onMessage: foreground.stream,
      onMessageOpenedApp: Stream.value(_remote),
    );

    expect(await push.start(), isTrue);
    expect(await push.token(), 'token-1');
    expect(await push.tokenRefreshes().first, 'token-2');
    expect((await push.launchedBy())?.billId, 'bill-1');
    expect((await push.opened().first).title, 'Conta paga');
    foreground.add(const RemoteMessage(data: {'billId': 'bill-2'}));
    expect((await push.foreground().first).billId, 'bill-2');

    when(messaging.getToken).thenThrow(Exception('no token'));
    expect(await push.token(), isNull);
    when(messaging.getInitialMessage).thenAnswer((_) async => null);
    expect(await push.launchedBy(), isNull);
    await foreground.close();
  });
}
