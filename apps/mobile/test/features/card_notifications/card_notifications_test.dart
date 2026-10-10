import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:cashdeck/features/card_notifications/application/card_notification_use_cases.dart';
import 'package:cashdeck/features/card_notifications/card_notifications_providers.dart';
import 'package:cashdeck/features/card_notifications/data/fake_card_notification_bridge.dart';
import 'package:cashdeck/features/card_notifications/data/platform_card_notification_bridge.dart';
import 'package:cashdeck/features/card_notifications/domain/card_notifications.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/mocks.dart';

const card = TransactionAccount(
  id: 'card',
  name: 'Card',
  owner: EntityKind.personal,
  institution: 'Card Bank',
  type: AccountType.creditCard,
);
const other = TransactionAccount(
  id: 'other',
  name: 'Another card',
  owner: EntityKind.personal,
  institution: 'Card Bank',
  type: AccountType.creditCard,
);
const checking = TransactionAccount(
  id: 'checking',
  name: 'Checking',
  owner: EntityKind.personal,
  institution: 'Bank',
  type: AccountType.checking,
);
const session = ServerCredentials(
  baseUrl: 'https://cashdeck.example.com',
  token: 'token',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('domain', () {
    test('values compare by their fields', () {
      const app = NotifyingApp(package: 'com.example.app', label: 'App');
      expect(app.props, ['com.example.app', 'App']);
      expect(CardNotificationStatus.unsupported.props, [
        false,
        false,
        <String>{},
        null,
        0,
        <NotifyingApp>[],
      ]);
      expect(CardNotificationConfig.off.props, [
        false,
        <String>{},
        null,
        null,
        null,
      ]);
    });
  });

  group('use cases', () {
    test('lists only credit cards, by name', () async {
      final repository = MockTransactionsRepository();
      when(repository.accounts)
          .thenAnswer((_) async => const Ok([card, checking, other]));
      expect(
        await ListNotificationCards(repository).call(),
        const Ok([other, card]),
      );
      when(repository.accounts)
          .thenAnswer((_) async => const Err(NetworkFailure()));
      expect(
        await ListNotificationCards(repository).call(),
        const Err<List<TransactionAccount>>(NetworkFailure()),
      );
    });

    test('forwards only with a card and a session', () async {
      final bridge = FakeCardNotificationBridge(access: true);
      final save = SaveCardNotifications(bridge);
      final on = await save(
        enabled: true,
        packages: {'com.example.cardapp'},
        accountId: 'card',
        session: session,
      );
      expect((on as Ok<CardNotificationStatus>).value.enabled, isTrue);
      final signedOut = await save(
        enabled: true,
        packages: {'com.example.cardapp'},
        accountId: 'card',
        session: null,
      );
      expect((signedOut as Ok<CardNotificationStatus>).value.enabled, isFalse);

      await save(
        enabled: true,
        packages: {'com.example.cardapp'},
        accountId: 'card',
        session: session,
      );
      await StopCardNotifications(bridge).call();
      final stopped = await bridge.status() as Ok<CardNotificationStatus>;
      expect(stopped.value.enabled, isFalse);
      expect(stopped.value.packages, isEmpty);
    });

    test('stopping skips a phone without the listener', () async {
      const bridge = PlatformCardNotificationBridge(supported: false);
      await const StopCardNotifications(bridge).call();
      expect(
        await bridge.status(),
        const Ok(CardNotificationStatus.unsupported),
      );
      expect(
        await bridge.openAccessSettings(),
        const Err<void>(UnsupportedFailure()),
      );
    });
  });

  group('platform bridge', () {
    const channel = MethodChannel('test/card_notifications');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      calls.clear();
      messenger.setMockMethodCallHandler(channel, null);
    });

    void answer(Object? Function(MethodCall call) reply) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return reply(call);
      });
    }

    test('reads the status and sends the settings', () async {
      answer(
        (call) => {
          'access': true,
          'enabled': call.method == 'configure',
          'packages': ['com.example.cardapp'],
          'accountId': 'card',
          'pending': 2,
          'apps': [
            {'package': 'com.example.zeta', 'label': 'zeta'},
            {'package': 'com.example.cardapp', 'label': 'Card App'},
            'broken',
          ],
        },
      );
      const bridge = PlatformCardNotificationBridge(channel: channel);
      final status = await bridge.status() as Ok<CardNotificationStatus>;
      expect(status.value.pending, 2);
      expect(status.value.apps.map((app) => app.label), ['Card App', 'zeta']);
      final configured = await bridge.configure(
        const CardNotificationConfig(
          enabled: true,
          packages: {'com.example.cardapp'},
          accountId: 'card',
          baseUrl: 'https://cashdeck.example.com',
          token: 'token',
        ),
      );
      expect((configured as Ok<CardNotificationStatus>).value.enabled, isTrue);
      expect(calls.last.arguments, {
        'enabled': true,
        'packages': ['com.example.cardapp'],
        'accountId': 'card',
        'baseUrl': 'https://cashdeck.example.com',
        'token': 'token',
      });
      expect(await bridge.openAccessSettings(), const Ok<void>(null));
      expect(calls.last.method, 'openAccessSettings');
    });

    test('reads a sparse answer with defaults', () async {
      answer((_) => <String, Object?>{});
      const bridge = PlatformCardNotificationBridge(channel: channel);
      expect(
        await bridge.status(),
        const Ok(CardNotificationStatus.unsupported),
      );
    });

    test('turns platform errors into failures', () async {
      answer((_) => throw PlatformException(code: 'boom'));
      const bridge = PlatformCardNotificationBridge(channel: channel);
      expect(
        await bridge.status(),
        const Err<CardNotificationStatus>(UnexpectedFailure()),
      );
      expect(
        await bridge.openAccessSettings(),
        const Err<void>(UnexpectedFailure()),
      );
      answer((_) => 'not a map');
      expect(
        await bridge.status(),
        const Err<CardNotificationStatus>(UnexpectedFailure()),
      );
    });

    test('a build without the listener reads as unsupported', () async {
      const bridge = PlatformCardNotificationBridge(channel: channel);
      expect(
        await bridge.status(),
        const Ok(CardNotificationStatus.unsupported),
      );
    });
  });

  test('the fake backend uses the in-memory bridge', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(cardNotificationBridgeProvider),
      isA<FakeCardNotificationBridge>(),
    );
    expect(container.read(listNotificationCardsProvider), isNotNull);
    expect(container.read(saveCardNotificationsProvider), isNotNull);
    expect(container.read(stopCardNotificationsProvider), isNotNull);
  });
}
