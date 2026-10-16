import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/card_notifications/card_notifications_providers.dart';
import 'package:cashdeck/features/card_notifications/data/fake_card_notification_bridge.dart';
import 'package:cashdeck/features/card_notifications/data/platform_card_notification_bridge.dart';
import 'package:cashdeck/features/card_notifications/domain/card_notifications.dart';
import 'package:cashdeck/features/card_notifications/presentation/card_notifications_controller.dart';
import 'package:cashdeck/features/card_notifications/presentation/card_notifications_screen.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/transactions_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/mocks.dart';
import '../../support/pump_app.dart';

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

const failingStatus = CardNotificationStatus(
  access: false,
  enabled: false,
  routes: {},
  pending: 0,
  apps: [NotifyingApp(package: 'com.example.cardapp', label: 'Card App')],
);

final class FailingBridge implements CardNotificationBridge {
  @override
  bool get supported => true;

  @override
  Future<Result<CardNotificationStatus>> status() async =>
      const Ok(failingStatus);

  @override
  Future<Result<void>> openAccessSettings() async =>
      const Err(UnexpectedFailure());

  @override
  Future<Result<CardNotificationStatus>> configure(
    CardNotificationConfig config,
  ) async => const Err(UnexpectedFailure());
}

List<Override> overrides(
  CardNotificationBridge bridge, {
  Result<List<TransactionAccount>> accounts = const Ok([card, other]),
}) {
  final repository = MockTransactionsRepository();
  when(repository.accounts).thenAnswer((_) async => accounts);
  return [
    cardNotificationBridgeProvider.overrideWithValue(bridge),
    transactionsRepositoryProvider.overrideWithValue(repository),
  ];
}

void main() {
  testWidgets('grants access, links each app to a card, then forwards', (
    tester,
  ) async {
    final bridge = FakeCardNotificationBridge();
    await tester.pumpApp(
      const CardNotificationsScreen(),
      overrides: overrides(bridge),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.cardNotificationsAccessMissing), findsOneWidget);
    expect(
      tester
          .widget<Switch>(find.byKey(CardNotificationsScreen.switchKey))
          .onChanged,
      isNull,
    );

    await tester.tap(find.byKey(CardNotificationsScreen.accessKey));
    await tester.pumpAndSettle();
    expect(bridge.access, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(l10n.cardNotificationsAccessGranted), findsOneWidget);

    Future<void> route(String package, Key option) async {
      await tester.tap(find.byKey(CardNotificationsScreen.appKey(package)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(option));
      await tester.pumpAndSettle();
    }

    Future<Map<String, String>> routes() async =>
        (await bridge.status() as Ok<CardNotificationStatus>).value.routes;

    await route('com.example.cardapp', CardNotificationsScreen.cardKey('card'));
    await route('com.example.chat', CardNotificationsScreen.cardKey('other'));
    expect(find.text(l10n.cardNotificationsAppCard('Card')), findsOneWidget);
    expect(
      find.text(l10n.cardNotificationsAppCard('Another card')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(CardNotificationsScreen.switchKey));
    await tester.pumpAndSettle();
    final status = await bridge.status() as Ok<CardNotificationStatus>;
    expect(status.value.enabled, isTrue);
    expect(status.value.routes, {
      'com.example.cardapp': 'card',
      'com.example.chat': 'other',
    });

    await route('com.example.cardapp', CardNotificationsScreen.cardKey('card'));
    await tester.tap(
      find.byKey(CardNotificationsScreen.appKey('com.example.cardapp')),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(await routes(), hasLength(2));

    await route('com.example.chat', CardNotificationsScreen.offKey);
    expect(await routes(), {'com.example.cardapp': 'card'});
    await route('com.example.cardapp', CardNotificationsScreen.offKey);
    final unwatched = await bridge.status() as Ok<CardNotificationStatus>;
    expect(unwatched.value.enabled, isFalse);
    expect(find.text(l10n.cardNotificationsSwitchHint), findsOneWidget);
  });

  testWidgets('shows the empty states and the waiting count', (tester) async {
    final bridge = _PendingBridge();
    await tester.pumpApp(
      const CardNotificationsScreen(),
      overrides: overrides(bridge, accounts: const Ok([])),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.cardNotificationsNoCards), findsOneWidget);
    expect(find.text(l10n.cardNotificationsNoApps), findsOneWidget);
    expect(find.text(l10n.cardNotificationsPending(3)), findsOneWidget);
  });

  testWidgets('reports a failed action with a toast', (tester) async {
    await tester.pumpApp(
      const CardNotificationsScreen(),
      overrides: overrides(FailingBridge()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CardNotificationsScreen.accessKey));
    await tester.pumpAndSettle();
    expect(
      find.text(const UnexpectedFailure().userMessage(l10n)),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(CardNotificationsScreen.appKey('com.example.cardapp')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CardNotificationsScreen.cardKey('card')));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CardNotificationsScreen)),
    );
    expect(
      container.read(cardNotificationsControllerProvider).value?.status,
      failingStatus,
    );
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('says the phone cannot forward and retries a failed load', (
    tester,
  ) async {
    await tester.pumpApp(
      const CardNotificationsScreen(),
      overrides: overrides(
        const PlatformCardNotificationBridge(supported: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.cardNotificationsUnsupported), findsOneWidget);

    await tester.pumpApp(
      const CardNotificationsScreen(),
      overrides: overrides(
        FakeCardNotificationBridge(),
        accounts: const Err(NetworkFailure()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CardNotificationsScreen), findsOneWidget);
    expect(find.text(l10n.cardNotificationsIntro), findsNothing);
  });

  test('the api backend uses the platform bridge', () {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(backend: Backend.api, apiBaseUrl: 'https://x.test'),
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(
      container.read(cardNotificationBridgeProvider),
      isA<PlatformCardNotificationBridge>(),
    );
  });
}

final class _PendingBridge implements CardNotificationBridge {
  @override
  bool get supported => true;

  @override
  Future<Result<CardNotificationStatus>> status() async => const Ok(
    CardNotificationStatus(
      access: true,
      enabled: false,
      routes: {},
      pending: 3,
      apps: [],
    ),
  );

  @override
  Future<Result<void>> openAccessSettings() async => const Ok(null);

  @override
  Future<Result<CardNotificationStatus>> configure(
    CardNotificationConfig config,
  ) => status();
}
