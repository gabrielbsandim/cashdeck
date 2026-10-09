import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/key_value_store.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/home/presentation/home_insights.dart';
import 'package:cashdeck/features/home/presentation/home_widgets_controller.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:cashdeck/features/insights/insights_providers.dart';
import 'package:cashdeck/features/insights/presentation/cards_screen.dart';
import 'package:cashdeck/features/insights/presentation/insights_controller.dart';
import 'package:cashdeck/features/insights/presentation/installments_screen.dart';
import 'package:cashdeck/features/insights/presentation/subscriptions_screen.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/mocks.dart';
import '../../../support/pump_app.dart';

const double _height = 4200;

InsightsOverview _overview({required Money result}) => InsightsOverview(
  period: InsightPeriod.month,
  range: const DateSpan(CalendarDate(2026, 10, 1), CalendarDate(2026, 10, 8)),
  previousRange: const DateSpan(
    CalendarDate(2026, 9, 1),
    CalendarDate(2026, 9, 30),
  ),
  spend: const SpendSummary(
    total: Money(50_000),
    previous: Money(40_000),
    series: [],
    previousSeries: [],
    topMerchants: [],
  ),
  categoryTotal: const Money(50_000),
  categories: const [
    CategoryShare(
      categoryId: 'cat-own',
      name: 'Pets',
      total: Money(30_000),
      sharePercent: 60,
    ),
    CategoryShare(total: Money(20_000), sharePercent: 40),
  ],
  flow: CashFlow(
    income: const Money(10_000),
    expenses: const Money(50_000),
    result: result,
  ),
  billsDue: const BillsDue(days: 7, total: Money(0), count: 0),
);

TransactionAccount _account(String id, String institution, int cents) =>
    TransactionAccount(
      id: id,
      name: 'Conta $id',
      owner: EntityKind.personal,
      institution: institution,
      type: AccountType.checking,
      balance: Money(cents),
    );

void main() {
  testWidgets('the summary tiles open their screens', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.home, screenHeight: _height);

    for (final (widget, screen) in [
      (HomeWidget.installments, InstallmentsScreen),
      (HomeWidget.subscriptions, SubscriptionsScreen),
      (HomeWidget.cardBill, CardsScreen),
      (HomeWidget.creditUsed, CardsScreen),
    ]) {
      await tester.tap(find.byKey(HomeSummaryGrid.tileKey(widget)));
      await settle(tester);
      expect(find.byType(screen), findsOneWidget);
      app.router.pop();
      await settle(tester);
    }

    await tester.tap(find.byKey(HomeSummaryGrid.tileKey(HomeWidget.reserve)));
    await settle(tester);
    expect(app.location, AppRoutes.balances);
    app.router.pop();
    await settle(tester);

    await tester.tap(find.byKey(HomeSummaryGrid.tileKey(HomeWidget.billsDue)));
    await settle(tester);
    expect(app.location, AppRoutes.bills);
  });

  testWidgets('the period toggle reloads the spending', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.home, screenHeight: _height);

    await tester.tap(find.byKey(HomeSpendCard.periodKey(InsightPeriod.week)));
    await settle(tester);

    expect(app.read(insightPeriodProvider), InsightPeriod.week);
    expect(find.text(l10n.homeTopMerchants), findsOneWidget);
    expect(find.text(l10n.homeMerchantCount(6)), findsOneWidget);
  });

  testWidgets('the editor hides and reorders the tiles', (tester) async {
    final store = InMemoryKeyValueStore();
    final app = await pumpRoute(
      tester,
      AppRoutes.home,
      screenHeight: _height,
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
    );

    await tester.tap(find.byKey(HomeSummaryGrid.editKey));
    await settle(tester);
    await tester.tap(find.byKey(HomeSummaryGrid.toggleKey(HomeWidget.reserve)));
    await settle(tester);
    app.read(homeWidgetsProvider.notifier).move(0, 2);
    await settle(tester);
    await tester.tapAt(const Offset(200, 20));
    await settle(tester);

    expect(
      find.byKey(HomeSummaryGrid.tileKey(HomeWidget.reserve)),
      findsNothing,
    );
    expect(
      store.getString(HomeWidgetsController.orderKey),
      'installments,subscriptions,cardBill,creditUsed,billsDue,reserve',
    );
    expect(store.getString(HomeWidgetsController.hiddenKey), 'reserve');

    app.read(homeWidgetsProvider.notifier).toggle(HomeWidget.reserve);
    await settle(tester);
    expect(
      find.byKey(HomeSummaryGrid.tileKey(HomeWidget.reserve)),
      findsOneWidget,
    );
  });

  test('a saved layout keeps its order and appends tiles it never saw', () {
    final container = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(
          InMemoryKeyValueStore({
            HomeWidgetsController.orderKey: 'reserve,gone,billsDue',
            HomeWidgetsController.hiddenKey: 'billsDue',
          }),
        ),
      ],
    );
    addTearDown(container.dispose);

    final layout = container.read(homeWidgetsProvider);

    expect(layout.order.take(3), [
      HomeWidget.reserve,
      HomeWidget.billsDue,
      HomeWidget.cardBill,
    ]);
    expect(layout.order, hasLength(HomeWidget.values.length));
    expect(layout.visible, isNot(contains(HomeWidget.billsDue)));
  });

  testWidgets('a short month, own categories and a failed retry', (
    tester,
  ) async {
    final repository = MockInsightsRepository();
    registerFallbackValue(EntityScope.personal);
    registerFallbackValue(InsightPeriod.month);
    when(() => repository.overview(any(), any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    when(() => repository.installments(any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    when(() => repository.subscriptions(any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));

    await pumpRoute(
      tester,
      AppRoutes.home,
      screenHeight: _height,
      overrides: [
        insightsRepositoryProvider.overrideWithValue(repository),
        transactionAccountsProvider.overrideWith(
          (ref) async => [
            for (final (index, name) in ['A', 'B', 'C', 'D', 'E'].indexed)
              _account('$index', 'Banco $name', 10_000 * (index + 1)),
            _account('neg', 'Banco F', -500),
          ],
        ),
      ],
    );
    expect(find.text(l10n.homeSectionFailed), findsOneWidget);
    expect(find.text(l10n.homeOtherInstitutions), findsOneWidget);
    expect(find.text('Banco F'), findsNothing);

    when(() => repository.overview(any(), any()))
        .thenAnswer((_) async => Ok(_overview(result: const Money(-40_000))));
    await tester.tap(find.byKey(HomeSpendCard.retryKey));
    await settle(tester);

    expect(
      find.text(l10n.homeFlowShort(MoneyFormat.format(const Money(40_000)))),
      findsOneWidget,
    );
    expect(find.text('Pets'), findsOneWidget);
    expect(find.text(l10n.transactionUncategorized), findsOneWidget);
    expect(find.text(l10n.cardsNoDates), findsOneWidget);
    expect(find.text(l10n.cardsNotSent), findsOneWidget);

    await tester.tap(
      find.byKey(HomeSummaryGrid.tileKey(HomeWidget.creditUsed)),
    );
    await settle(tester);
    expect(find.byType(CardsScreen), findsOneWidget);
  });
}
