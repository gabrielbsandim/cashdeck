import 'dart:async';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/push/push_messaging.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:cashdeck/core/session/server_session.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/alerts/alerts_providers.dart';
import 'package:cashdeck/features/alerts/data/fake_alerts_repository.dart';
import 'package:cashdeck/features/alerts/domain/app_alert.dart';
import 'package:cashdeck/features/alerts/presentation/alert_labels.dart';
import 'package:cashdeck/features/alerts/presentation/alert_settings_screen.dart';
import 'package:cashdeck/features/alerts/presentation/alerts_controller.dart';
import 'package:cashdeck/features/alerts/presentation/alerts_screen.dart';
import 'package:cashdeck/features/alerts/presentation/push_listener.dart';
import 'package:cashdeck/features/bills/presentation/bill_detail_screen.dart';
import 'package:cashdeck/features/home/presentation/home_screen.dart';
import 'package:cashdeck/features/settings/presentation/settings_screen.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/app_harness.dart';
import '../../support/builders.dart';
import '../../support/pump_app.dart';
import 'alerts_data_test.dart' show MockAlertsRepository;

AppAlert _alert(String id, {String? billId, DateTime? readAt}) => AppAlert(
  id: id,
  kind: AlertKind.billDueSoon,
  title: 'Title $id',
  body: 'Body $id',
  createdAt: testNow,
  billId: billId,
  readAt: readAt,
);

/// Push whose streams a test drives.
final class ScriptedPush implements PushMessaging {
  new({this.available = true});

  final bool available;
  final launch = Completer<PushMessage?>();
  final foregroundMessages = StreamController<PushMessage>.broadcast();
  final openedMessages = StreamController<PushMessage>.broadcast();
  final refreshes = StreamController<String>.broadcast();
  String? nextToken = 'push-token';

  @override
  Future<bool> start() async => available;

  @override
  Future<String?> token() async => nextToken;

  @override
  Stream<String> tokenRefreshes() => refreshes.stream;

  @override
  Stream<PushMessage> foreground() => foregroundMessages.stream;

  @override
  Stream<PushMessage> opened() => openedMessages.stream;

  @override
  Future<PushMessage?> launchedBy() => launch.future;
}

ProviderContainer _container(AlertsRepository repository) {
  final container = ProviderContainer(
    overrides: [alertsRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUpAll(() => registerFallbackValue(AlertKind.other));

  test('push helpers pick the platform and the place to open', () {
    expect(pushPlatformOf(TargetPlatform.android), 'ANDROID');
    expect(pushPlatformOf(TargetPlatform.iOS), 'IOS');
    expect(pushPlatformOf(TargetPlatform.linux), 'WEB');
    expect(pushLocaleOf(const Locale('pt', 'BR')), 'pt');
    expect(pushLocaleOf(const Locale('en', 'BR')), 'en');
    expect(pushLocaleOf(const Locale('es')), 'en');
    expect(pushLocation(const PushMessage()), AppRoutes.alerts);
    expect(
      pushLocation(const PushMessage(data: {'billId': 'b 1'})),
      AppRoutes.bill('b 1'),
    );
  });

  test('alert texts follow the app language and keep the server text', () {
    final en = lookupAppLocalizations(const Locale('en'));
    AlertText textOf(AlertKind kind, Map<String, String> data) => alertText(
      en,
      AppAlert(
        id: 'a',
        kind: kind,
        title: 'Servidor',
        body: 'Texto do servidor',
        createdAt: testNow,
        data: data,
      ),
    );
    const bill = {
      'payee': 'Utility',
      'amount': r'R$ 10,00',
      'dueDate': '06/10',
    };
    const due = r'Utility · R$ 10,00';
    final cases = <AlertKind, (Map<String, String>, AlertText)>{
      AlertKind.billCaptured: (
        bill,
        (title: 'New bill captured', body: '$due, due 06/10.'),
      ),
      AlertKind.billNeedsAmount: (
        {'payee': 'Utility', 'source': 'e-mail'},
        (
          title: 'Bill without an amount',
          body:
              'Utility arrived by email without an amount; add the bill in '
              'the app.',
        ),
      ),
      AlertKind.billDueSoon: (
        bill,
        (title: 'Bill due tomorrow', body: '$due is still unpaid.'),
      ),
      AlertKind.paymentNeedsConfirmation: (
        bill,
        (
          title: 'Confirm the payment',
          body: '$due needs your confirmation before it is paid.',
        ),
      ),
      AlertKind.paymentPaid: (
        bill,
        (title: 'Bill paid', body: '$due was paid.'),
      ),
      AlertKind.paymentMovedDown: (
        {...bill, 'rail': 'Asaas'},
        (
          title: 'Payment changed route',
          body: '$due: Asaas failed, the bill moved to the next step.',
        ),
      ),
      AlertKind.paymentAssisted: (
        {...bill, 'method': 'PIX'},
        (
          title: 'Pay manually',
          body: '$due: use the Pix copy and paste in your bank app.',
        ),
      ),
      AlertKind.approvalPending: (
        bill,
        (
          title: 'Approval pending in the bank',
          body: '$due awaits your approval in internet banking.',
        ),
      ),
      AlertKind.lowBalance: (
        {'shortfall': r'R$ 5,00', 'dueDate': '06/10'},
        (
          title: 'Low reserve balance',
          body: r'R$ 5,00 short in the reserve for the bills due by 06/10.',
        ),
      ),
      AlertKind.invoiceIssued: (
        {'invoice': 'Nota 12', 'client': 'Client', 'amount': r'R$ 1,00'},
        (title: 'Invoice issued', body: r'Invoice 12 to Client · R$ 1,00.'),
      ),
      AlertKind.invoiceFailed: (
        {'invoice': 'Nota', 'client': 'Client', 'amount': r'R$ 1,00'},
        (
          title: 'Invoice not issued',
          body: r'Invoice to Client · R$ 1,00 was rejected.',
        ),
      ),
      AlertKind.cardBillClosed: (
        {'card': 'Bank 1234', 'closing': '01/10', 'dueDate': '08/10'},
        (
          title: 'Card bill closed',
          body: 'Bank 1234: closed on 01/10, due 08/10.',
        ),
      ),
    };
    for (final MapEntry(key: kind, value: (data, text)) in cases.entries) {
      expect(textOf(kind, data), text, reason: kind.name);
    }
    expect(
      textOf(AlertKind.paymentAssisted, {...bill, 'method': 'BARCODE'}).body,
      '$due: use the barcode in your bank app.',
    );
    expect(
      textOf(AlertKind.paymentAssisted, {...bill, 'method': 'NONE'}).body,
      '$due: pay in your bank app and mark it as paid.',
    );
    expect(
      textOf(AlertKind.billNeedsAmount, {
        'payee': 'Utility',
        'source': 'DDA',
        'sourceKind': 'DDA',
      }).body,
      contains('arrived by DDA'),
    );
    expect(
      textOf(AlertKind.billNeedsAmount, {
        'payee': 'Utility',
        'source': 'DDA',
      }).body,
      contains('arrived by DDA'),
    );
    expect(
      textOf(AlertKind.invoiceIssued, {
        'invoice': 'Nota 7',
        'number': '7',
        'client': 'Client',
        'amount': r'R$ 1,00',
      }).body,
      startsWith('Invoice 7 '),
    );
    expect(
      textOf(AlertKind.invoiceIssued, {'client': 'Client', 'amount': '1'}).body,
      startsWith('Invoice to'),
    );
    const stored = (title: 'Servidor', body: 'Texto do servidor');
    expect(textOf(AlertKind.billDueSoon, const {}), stored);
    expect(textOf(AlertKind.other, bill), stored);
  });

  test('every kind has a label and an icon', () {
    for (final kind in AlertKind.values) {
      expect(alertKindLabel(l10n, kind), isNotEmpty);
      expect(alertKindIcon(kind), isNotNull);
    }
  });

  test('the inbox controller pages, reads and reports failures', () async {
    final repository = MockAlertsRepository();
    when(repository.list).thenAnswer(
      (_) async => Ok(AlertPage(items: [_alert('a')], nextCursor: '1')),
    );
    when(() => repository.list(cursor: '1'))
        .thenAnswer((_) async => Ok(AlertPage(items: [_alert('b')])));
    when(() => repository.markRead('a'))
        .thenAnswer((_) async => Ok(_alert('a', readAt: testNow)));
    when(() => repository.markRead('x'))
        .thenAnswer((_) async => const Err(NotFoundFailure()));
    when(repository.unreadCount).thenAnswer((_) async => const Ok(1));
    when(repository.markAllRead).thenAnswer((_) async => const Ok(1));
    final container = _container(repository);
    final controller = container.read(alertsControllerProvider.notifier);

    expect(await controller.markRead('a'), isNull);
    await container.read(alertsControllerProvider.future);
    expect(await controller.loadMore(), isNull);
    expect(
      container.read(alertsControllerProvider).value?.items.map((a) => a.id),
      ['a', 'b'],
    );
    expect(await controller.loadMore(), isNull);
    expect(await controller.markRead('a'), isNull);
    expect(await controller.markRead('x'), const NotFoundFailure());
    expect(await controller.markAllRead(testNow), isNull);
    expect(
      container
          .read(alertsControllerProvider)
          .value
          ?.items
          .every((alert) => !alert.unread),
      isTrue,
    );
    expect(await container.read(unreadAlertsProvider.future), 1);

    when(repository.markAllRead)
        .thenAnswer((_) async => const Err(NetworkFailure()));
    expect(await controller.markAllRead(testNow), const NetworkFailure());
  });

  test('a failed page or count is reported, not thrown', () async {
    final repository = MockAlertsRepository();
    when(repository.list).thenAnswer(
      (_) async => Ok(AlertPage(items: [_alert('a')], nextCursor: '1')),
    );
    when(() => repository.list(cursor: '1'))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    when(repository.unreadCount)
        .thenAnswer((_) async => const Err(NetworkFailure()));
    final container = _container(repository);
    await container.read(alertsControllerProvider.future);
    expect(
      await container.read(alertsControllerProvider.notifier).loadMore(),
      const NetworkFailure(),
    );
    expect(await container.read(unreadAlertsProvider.future), 0);
  });

  test('the settings controller mutes and reports failures', () async {
    final repository = MockAlertsRepository();
    when(repository.settings)
        .thenAnswer((_) async => const Ok({AlertKind.paymentPaid: false}));
    when(() => repository.setMuted(AlertKind.paymentPaid, muted: true))
        .thenAnswer((_) async => const Ok({AlertKind.paymentPaid: true}));
    when(() => repository.setMuted(AlertKind.billDueSoon, muted: true))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    final container = _container(repository);
    final controller = container.read(alertSettingsControllerProvider.notifier);
    await container.read(alertSettingsControllerProvider.future);

    expect(
      await controller.setMuted(AlertKind.paymentPaid, muted: true),
      isNull,
    );
    expect(container.read(alertSettingsControllerProvider).value, {
      AlertKind.paymentPaid: true,
    });
    expect(
      await controller.setMuted(AlertKind.billDueSoon, muted: true),
      const NetworkFailure(),
    );
  });

  testWidgets('the bell and Mais open the inbox; a row opens its bill', (
    tester,
  ) async {
    final app = await pumpRoute(tester, AppRoutes.home);
    await tester.tap(find.byKey(HomeScreen.alertsKey));
    await settle(tester);
    expect(find.byType(AlertsScreen), findsOneWidget);
    expect(find.byKey(AlertsScreen.unreadKey('alert-due')), findsOneWidget);
    expect(find.byKey(AlertsScreen.unreadKey('alert-paid')), findsNothing);

    await tester.tap(find.byKey(AlertsScreen.rowKey('alert-due')));
    await settle(tester);
    expect(app.location, AppRoutes.bill('bill-energy'));
    expect(find.byType(BillDetailScreen), findsOneWidget);

    app.router.go(AppRoutes.settings);
    await settle(tester);
    await tester.tap(find.byKey(SettingsScreen.rowKey(AppRoutes.alerts)));
    await settle(tester);
    expect(find.byKey(AlertsScreen.unreadKey('alert-due')), findsNothing);
    await tester.tap(find.byKey(AlertsScreen.readAllKey));
    await settle(tester);
    expect(find.byKey(AlertsScreen.unreadKey('alert-assisted')), findsNothing);

    await tester.runAsync(
      tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh,
    );
    await settle(tester);
    expect(find.byType(AlertsScreen), findsOneWidget);
  });

  testWidgets('settings switches mute a type', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.alerts);
    await tester.tap(find.byKey(AlertsScreen.settingsKey));
    await settle(tester);
    expect(app.location, AppRoutes.alertSettings);
    expect(find.text(l10n.alertSettingsHint), findsOneWidget);
    final paid = find.byKey(
      AlertSettingsScreen.switchKey(AlertKind.paymentPaid),
    );
    expect(tester.widget<Switch>(paid).value, isTrue);
    await tester.tap(paid);
    await settle(tester);
    expect(tester.widget<Switch>(paid).value, isFalse);
  });

  testWidgets('a failed mute says why', (tester) async {
    final repository = MockAlertsRepository();
    when(repository.unreadCount).thenAnswer((_) async => const Ok(0));
    when(repository.settings)
        .thenAnswer((_) async => const Ok({AlertKind.paymentPaid: false}));
    when(() => repository.setMuted(any(), muted: any(named: 'muted')))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    await pumpRoute(
      tester,
      AppRoutes.alertSettings,
      overrides: [alertsRepositoryProvider.overrideWithValue(repository)],
    );
    await tester.tap(
      find.byKey(AlertSettingsScreen.switchKey(AlertKind.paymentPaid)),
    );
    await settle(tester);
    expect(find.text(l10n.errorNetwork), findsOneWidget);
  });

  testWidgets('the inbox shows empty, failed and paged states', (tester) async {
    final repository = MockAlertsRepository();
    when(repository.unreadCount).thenAnswer((_) async => const Ok(0));
    when(repository.list)
        .thenAnswer((_) async => const Ok(AlertPage(items: [])));
    when(repository.settings)
        .thenAnswer((_) async => const Err(NetworkFailure()));
    final overrides = [alertsRepositoryProvider.overrideWithValue(repository)];
    final app = await pumpRoute(tester, AppRoutes.alerts, overrides: overrides);
    expect(find.text(l10n.alertsInboxEmpty), findsOneWidget);

    app.router.go(AppRoutes.alertSettings);
    await settle(tester);
    expect(find.byType(CdErrorState), findsOneWidget);
    await tester.tap(find.byKey(CdErrorState.retryKey));
    await settle(tester);

    when(repository.list).thenAnswer((_) async => const Err(ServerFailure()));
    app.router.go(AppRoutes.home);
    await settle(tester);
    app.invalidate(alertsControllerProvider);
    app.router.go(AppRoutes.alerts);
    await settle(tester);
    expect(find.byType(CdErrorState), findsOneWidget);

    when(repository.list).thenAnswer(
      (_) async => Ok(AlertPage(items: [_alert('a')], nextCursor: '1')),
    );
    when(() => repository.list(cursor: '1'))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    when(() => repository.markRead('a'))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    await tester.tap(find.byKey(CdErrorState.retryKey));
    await settle(tester);
    await tester.tap(find.byKey(AlertsScreen.loadMoreKey));
    await settle(tester);
    expect(find.text(l10n.errorNetwork), findsOneWidget);
    await waitForToast(tester);
    await tester.tap(find.byKey(AlertsScreen.rowKey('a')));
    await settle(tester);
    expect(app.location, AppRoutes.alerts);
  });

  testWidgets('a push is registered, shown in the foreground and followed', (
    tester,
  ) async {
    final push = ScriptedPush();
    final repository = FakeAlertsRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    );
    final app = await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [
        pushMessagingProvider.overrideWithValue(push),
        alertsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    expect(repository.devices, ['ANDROID:push-token']);
    expect(repository.locales['push-token'], 'pt');

    push.refreshes.add('fresh-token');
    await settle(tester);
    expect(repository.devices.last, 'ANDROID:fresh-token');

    push.foregroundMessages.add(
      const PushMessage(title: 'Conta paga', data: {'billId': 'bill-rent'}),
    );
    await settle(tester);
    expect(find.text('Conta paga'), findsOneWidget);
    await tester.tap(find.text(l10n.alertOpenAction));
    await settle(tester);
    expect(app.location, AppRoutes.bill('bill-rent'));

    push.foregroundMessages.add(const PushMessage());
    await settle(tester);
    expect(find.text(l10n.alertsTitle), findsWidgets);
    await waitForToast(tester);

    push.openedMessages.add(const PushMessage());
    await settle(tester);
    expect(app.location, AppRoutes.alerts);

    await app.read(serverSessionProvider.notifier).signOut();
    await settle(tester);
    push.refreshes.add('ignored');
    await settle(tester);
    expect(repository.devices.last, 'ANDROID:fresh-token');
    await app
        .read(serverSessionProvider.notifier)
        .signIn(ServerCredentials.demo);
    await settle(tester);
    expect(repository.devices.last, 'ANDROID:push-token');
    push.launch.complete(null);
    await settle(tester);
    expect(app.location, AppRoutes.home);
  });

  testWidgets('a registration without a token is retried on resume', (
    tester,
  ) async {
    final push = ScriptedPush()..nextToken = null;
    final repository = FakeAlertsRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    );
    await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [
        pushMessagingProvider.overrideWithValue(push),
        alertsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    expect(repository.devices, isEmpty);

    Future<void> resume() async {
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
    }

    push.nextToken = 'push-token';
    await resume();
    expect(repository.devices, ['ANDROID:push-token']);
    await resume();
    expect(repository.devices, ['ANDROID:push-token']);
  });

  testWidgets('a cold start push opens its bill', (tester) async {
    final push = ScriptedPush();
    final app = await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [pushMessagingProvider.overrideWithValue(push)],
    );
    push.launch.complete(const PushMessage(data: {'billId': 'bill-gym'}));
    await settle(tester);
    expect(app.location, AppRoutes.bill('bill-gym'));
  });

  testWidgets('without push the app runs as before', (tester) async {
    final app = await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [
        pushMessagingProvider.overrideWithValue(ScriptedPush(available: false)),
      ],
    );
    expect(app.location, AppRoutes.home);
  });
}
