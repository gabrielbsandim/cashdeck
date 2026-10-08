import 'package:cashdeck/app/app.dart';
import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/widgets/layout/cd_nav_bar.dart';
import 'package:cashdeck/features/bills/presentation/bill_detail_screen.dart';
import 'package:cashdeck/features/bills/presentation/bills_screen.dart';
import 'package:cashdeck/features/chat/presentation/chat_screen.dart';
import 'package:cashdeck/features/home/presentation/home_screen.dart';
import 'package:cashdeck/features/settings/presentation/more_screen.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/pump_app.dart';

void main() {
  testWidgets('walks the tabs and opens a bill on the fake backend', (
    tester,
  ) async {
    final app = await pumpRoute(tester, AppRoutes.home);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(CdNavBar), findsOneWidget);

    await tester.tap(find.byKey(CdNavBar.itemKey(1)));
    await settle(tester);
    expect(find.byType(TransactionsScreen), findsOneWidget);

    await tester.tap(find.byKey(CdNavBar.itemKey(3)));
    await settle(tester);
    expect(find.byType(ChatScreen), findsOneWidget);

    await tester.tap(find.byKey(CdNavBar.itemKey(2)));
    await settle(tester);
    expect(find.byType(BillsScreen), findsOneWidget);

    await tester.tap(find.byKey(BillsScreen.tileKey('bill-energy')));
    await settle(tester);
    expect(find.byType(BillDetailScreen), findsOneWidget);
    expect(find.byType(CdNavBar), findsNothing);

    app.router.go(AppRoutes.bills);
    await settle(tester);
    await tester.tap(find.byKey(CdNavBar.itemKey(2)));
    await settle(tester);
    expect(app.location, AppRoutes.bills);
  });

  testWidgets('the bills tab counts what waits on the user', (tester) async {
    await pumpRoute(tester, AppRoutes.bills);

    final bar = tester.widget<CdNavBar>(find.byType(CdNavBar));
    expect(bar.items[2].badge, greaterThan(0));
    expect(bar.items[2].label, l10n.tabBills);
  });

  testWidgets('switches to the dark theme from Mais', (tester) async {
    await pumpRoute(tester, AppRoutes.more);
    expect(find.byType(MoreScreen), findsOneWidget);

    await tester.tap(find.text(l10n.themeDark));
    await settle(tester);

    final context = tester.element(find.byType(MoreScreen));
    expect(Theme.of(context).brightness, Brightness.dark);
  });

  test('speaks the device language when supported, Portuguese otherwise', () {
    const supported = [Locale('en'), Locale('pt')];

    expect(
      CashdeckApp.resolveLocale(const Locale('en', 'US'), supported),
      const Locale('en'),
    );
    expect(
      CashdeckApp.resolveLocale(const Locale('fr'), supported),
      CashdeckApp.fallbackLocale,
    );
    expect(
      CashdeckApp.resolveLocale(null, supported),
      CashdeckApp.fallbackLocale,
    );
  });
}
