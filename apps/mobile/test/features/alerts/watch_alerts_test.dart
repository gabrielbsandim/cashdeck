import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/push/push_messaging.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/alerts/alerts_providers.dart';
import 'package:cashdeck/features/alerts/domain/app_alert.dart';
import 'package:cashdeck/features/alerts/presentation/alert_destination.dart';
import 'package:cashdeck/features/alerts/presentation/alert_labels.dart';
import 'package:cashdeck/features/alerts/presentation/alerts_screen.dart';
import 'package:cashdeck/features/alerts/presentation/push_listener.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/app_harness.dart';
import '../../support/builders.dart';
import 'alerts_data_test.dart' show MockAlertsRepository;

AppAlert _alert(AlertKind kind, Map<String, String> data, {String? billId}) =>
    AppAlert(
      id: 'a',
      kind: kind,
      title: 'Servidor',
      body: 'Texto do servidor',
      createdAt: testNow,
      billId: billId,
      data: data,
    );

void main() {
  test('the new alerts read in the app language', () {
    final en = lookupAppLocalizations(const Locale('en'));
    AlertText textOf(AlertKind kind, Map<String, String> data) =>
        alertText(en, _alert(kind, data));
    const amount = r'R$ 900,00';

    expect(
      textOf(AlertKind.unusualPurchase, {
        'merchant': 'Loja Exemplo',
        'amount': amount,
        'day': '07/10',
        'times': '4.5',
        'usual': r'R$ 200,00',
      }),
      (
        title: 'Unusual purchase',
        body:
            'Loja Exemplo · $amount on 07/10, about 4.5x the usual '
            r'(R$ 200,00).',
      ),
    );
    expect(
      textOf(AlertKind.subscriptionChanged, {
        'change': 'PRICE_UP',
        'name': 'Streaming',
        'previous': r'R$ 39,90',
        'amount': r'R$ 45,90',
        'percent': '15',
      }).body,
      r'Streaming went from R$ 39,90 to R$ 45,90 (+15%).',
    );
    expect(
      textOf(AlertKind.subscriptionChanged, {
        'change': 'DUPLICATE',
        'name': 'Streaming',
        'count': '2',
        'amount': r'R$ 39,90',
      }),
      (
        title: 'Subscription charged twice',
        body:
            r'Streaming was charged 2 times in the same month (R$ 39,90 each).',
      ),
    );
    expect(
      textOf(AlertKind.cardBillAboveAverage, {
        'card': 'Banco 1234',
        'amount': amount,
        'percent': '50',
        'average': r'R$ 600,00',
        'dueDate': '15/10',
      }).body,
      r'Banco 1234: R$ 900,00, 50% above the R$ 600,00 average; due 15/10.',
    );
    expect(
      textOf(AlertKind.bankSyncStale, {
        'institution': 'Banco',
        'hours': '72',
      }).body,
      'Banco has not synced for 72 h; reconnect it in Settings.',
    );
    expect(
      textOf(AlertKind.bankSyncStale, {
        'institution': 'Banco',
        'hours': '',
      }).body,
      'Banco needs attention to sync again.',
    );
    expect(
      textOf(AlertKind.invoiceNotIssued, {
        'client': 'Cliente',
        'amount': amount,
        'day': '05/10',
      }).title,
      'Invoice not issued',
    );
    expect(textOf(AlertKind.bankSyncStale, const {}), (
      title: 'Servidor',
      body: 'Texto do servidor',
    ));
  });

  test('an alert opens the screen it is about', () {
    expect(
      alertDestination(AlertKind.unusualPurchase, {'transactionId': 'tx 1'}),
      AppRoutes.transaction('tx 1'),
    );
    expect(
      alertDestination(AlertKind.cardChargeCaptured, {'transactionId': 'tx 2'}),
      AppRoutes.transaction('tx 2'),
    );
    expect(
      alertDestination(AlertKind.subscriptionChanged, {'key': 'streaming'}),
      AppRoutes.subscription('streaming'),
    );
    expect(
      alertDestination(AlertKind.cardBillAboveAverage, {'accountId': 'card'}),
      AppRoutes.cardBills('card'),
    );
    expect(
      alertDestination(AlertKind.bankSyncStale, const {}),
      AppRoutes.settingsConnections,
    );
    expect(
      alertDestination(AlertKind.invoiceNotIssued, const {}),
      AppRoutes.settingsCompany,
    );
    expect(alertDestination(AlertKind.unusualPurchase, const {}), isNull);
    expect(
      alertDestination(AlertKind.billDueSoon, const {}, billId: 'b'),
      AppRoutes.bill('b'),
    );
    expect(alertDestination(AlertKind.billDueSoon, const {}), isNull);
    expect(
      pushLocation(
        const PushMessage(
          data: {'alertType': 'UNUSUAL_PURCHASE', 'transactionId': 'tx-1'},
        ),
      ),
      AppRoutes.transaction('tx-1'),
    );
    expect(
      pushLocation(const PushMessage(data: {'alertType': 'BANK_SYNC_STALE'})),
      AppRoutes.settingsConnections,
    );
    expect(
      pushLocation(const PushMessage(data: {'alertType': 'UNUSUAL_PURCHASE'})),
      AppRoutes.alerts,
    );
  });

  testWidgets('a row opens the transaction an alert is about', (tester) async {
    final alert = _alert(AlertKind.unusualPurchase, {'transactionId': 'tx-1'});
    final repository = MockAlertsRepository();
    when(repository.unreadCount).thenAnswer((_) async => const Ok(1));
    when(repository.list)
        .thenAnswer((_) async => Ok(AlertPage(items: [alert])));
    when(() => repository.markRead('a'))
        .thenAnswer((_) async => Ok(alert.read(testNow)));
    final app = await pumpRoute(
      tester,
      AppRoutes.alerts,
      overrides: [alertsRepositoryProvider.overrideWithValue(repository)],
    );

    await tester.tap(find.byKey(AlertsScreen.rowKey('a')));
    await settle(tester);

    expect(app.location, AppRoutes.transaction('tx-1'));
  });
}
