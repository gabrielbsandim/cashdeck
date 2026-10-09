import 'dart:async';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/insights/cd_calendar_month.dart';
import 'package:cashdeck/core/widgets/insights/cd_column_bars.dart';
import 'package:cashdeck/core/widgets/money/privacy_toggle.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/insights/application/insights_use_cases.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:cashdeck/features/insights/insights_providers.dart';
import 'package:cashdeck/features/insights/presentation/cards_screen.dart';
import 'package:cashdeck/features/insights/presentation/insights_controller.dart';
import 'package:cashdeck/features/insights/presentation/insights_labels.dart';
import 'package:cashdeck/features/insights/presentation/insights_screen.dart';
import 'package:cashdeck/features/insights/presentation/installments_screen.dart';
import 'package:cashdeck/features/insights/presentation/subscription_detail_screen.dart';
import 'package:cashdeck/features/insights/presentation/subscriptions_screen.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/mocks.dart';
import '../../../support/pump_app.dart';

const _october = YearMonth(2026, 10);

MonthlyInsights _monthly({
  int? percent,
  int? average,
  List<CategoryChange> rose = const [],
}) => MonthlyInsights(
  month: _october,
  months: const [
    MonthResult(
      month: _october,
      income: Money(0),
      expenses: Money(10_000),
      result: Money(-10_000),
    ),
  ],
  savings: SavingsRate(
    percent: percent,
    averagePercent: average,
    trend: const [(_october, null)],
  ),
  rose: rose,
  fell: const [],
  fixedCost: const FixedCost(
    subscriptions: Money(0),
    installments: Money(0),
    bills: Money(0),
    total: Money(0),
    income: Money(0),
  ),
  insights: const [
    SubscriptionPriceUp(
      tone: InsightTone.negative,
      name: 'Música Onda',
      amount: Money(2_190),
      previousAmount: Money(1_990),
    ),
    SavingsRateChanged(
      tone: InsightTone.negative,
      percent: 5,
      averagePercent: 11,
    ),
  ],
);

Subscription _subscription({
  String? id,
  String key = 'music',
  List<String> transactionIds = const [],
}) => Subscription(
  id: id,
  key: key,
  owner: EntityKind.personal,
  name: 'Música Onda',
  amount: const Money(2_190),
  priceChanged: false,
  dayOfMonth: 12,
  thisMonth: SubscriptionMonthStatus.upcoming,
  transactionIds: transactionIds,
);

void main() {
  group('on the fake backend', () {
    testWidgets('Análises walks the months, widens the bars and links out', (
      tester,
    ) async {
      final app = await pumpRoute(tester, AppRoutes.insights);

      expect(find.byType(InsightsScreen), findsOneWidget);
      expect(find.text(monthTitle(l10n, _october)), findsOneWidget);
      expect(find.text(l10n.insightsLeftTitle), findsOneWidget);
      expect(
        tester.widget<IconButton>(find.byKey(InsightsScreen.nextKey)).onPressed,
        isNull,
      );

      await tester.tap(find.byKey(CdColumnBars.columnKey(0)).first);
      await settle(tester);
      await tester.tap(find.byKey(InsightsScreen.twelveKey));
      await settle(tester);
      expect(app.read(monthWindowProvider).count, 12);

      await tester.tap(find.byKey(InsightsScreen.previousKey));
      await settle(tester);
      expect(find.text(monthTitle(l10n, _october.add(-1))), findsOneWidget);
      expect(find.text(l10n.insightsLeftTitle), findsNothing);

      await tester.tap(find.byKey(InsightsScreen.nextKey));
      await settle(tester);
      expect(app.read(monthWindowProvider).month, isNull);

      await tester.tap(find.byKey(PrivacyToggle.buttonKey));
      await pickScope(tester, EntityScope.consolidated);
      final sentence = find.text(
        l10n.insightCategoryAbove(
          'Restaurantes',
          31,
          MoneyFormat.format(const Money(17_000), hide: true),
        ),
      );
      await tester.scrollUntilVisible(
        sentence,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(sentence, findsOneWidget);
      expect(find.text(l10n.insightsCompanyTitle), findsOneWidget);

      final link = find.byKey(InsightsScreen.linkKey(AppRoutes.installments));
      await tester.scrollUntilVisible(
        link,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(link);
      await settle(tester);
      expect(find.byType(InstallmentsScreen), findsOneWidget);
    });

    testWidgets('Parcelamentos filters, picks a month and opens a plan', (
      tester,
    ) async {
      await pumpRoute(tester, AppRoutes.installments);

      expect(
        find.byKey(InstallmentsScreen.planKey('notebook')),
        findsOneWidget,
      );
      expect(
        find.text(l10n.installmentsCommitted(monthName(l10n, _october.add(1)))),
        findsOneWidget,
      );

      await tester.tap(find.byKey(CdColumnBars.columnKey(1)));
      await settle(tester);
      expect(
        find.text(l10n.installmentsCommitted(monthName(l10n, _october.add(2)))),
        findsOneWidget,
      );

      await tester.tap(find.byKey(InstallmentsScreen.endingKey));
      await settle(tester);
      expect(find.byKey(InstallmentsScreen.planKey('bike')), findsNothing);

      await tester.tap(find.byKey(InstallmentsScreen.allKey));
      await settle(tester);
      await tester.tap(find.byKey(InstallmentsScreen.planKey('bike')));
      await settle(tester);
      expect(find.text(l10n.installmentsNumber(6)), findsOneWidget);
      expect(find.text(l10n.installmentsPurchase), findsOneWidget);
    });

    testWidgets('Assinaturas confirms a suggestion and removes a charge', (
      tester,
    ) async {
      await pumpRoute(tester, AppRoutes.subscriptions);

      expect(find.text(l10n.subscriptionsSuggestionTitle), findsOneWidget);
      expect(
        find.text(
          l10n.subscriptionsPriceUp(MoneyFormat.format(const Money(1_990))),
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(SubscriptionsScreen.confirmKey('gym')));
      await settle(tester);
      expect(find.text(l10n.subscriptionsConfirmed), findsOneWidget);
      expect(find.text(l10n.subscriptionsSuggestionTitle), findsNothing);
      expect(find.byKey(SubscriptionsScreen.rowKey('gym')), findsOneWidget);

      await tester.tap(find.byKey(SubscriptionsScreen.rowKey('stream')));
      await settle(tester);
      expect(find.byType(SubscriptionDetailScreen), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(SubscriptionDetailScreen.removeKey),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(SubscriptionDetailScreen.removeKey));
      await settle(tester);
      await tester.tap(find.byKey(SubscriptionDetailScreen.removeConfirmKey));
      await settle(tester);
      expect(find.text(l10n.subscriptionsRemoved), findsOneWidget);
      expect(find.byType(SubscriptionDetailScreen), findsNothing);
      expect(find.byKey(SubscriptionsScreen.rowKey('stream')), findsNothing);

      await tester.tap(find.byKey(SubscriptionsScreen.calendarKey));
      await settle(tester);
      expect(find.byType(CdCalendarMonth), findsOneWidget);
      expect(find.text(l10n.subscriptionsNoneOnDay), findsOneWidget);

      await tester.tap(find.byKey(CdCalendarMonth.dayKey(12)));
      await settle(tester);
      expect(find.byKey(SubscriptionsScreen.rowKey('music')), findsOneWidget);
      expect(find.byKey(SubscriptionsScreen.rowKey('cloud')), findsNothing);
    });

    testWidgets('Assinaturas ignores a suggestion and opens a charge', (
      tester,
    ) async {
      final app = await pumpRoute(tester, AppRoutes.subscriptions);

      await tester.tap(find.byKey(SubscriptionsScreen.dismissKey('gym')));
      await settle(tester);
      expect(find.text(l10n.subscriptionsDismissed), findsOneWidget);
      expect(find.text(l10n.subscriptionsSuggestionTitle), findsNothing);

      await tester.tap(find.byKey(SubscriptionsScreen.rowKey('music')));
      await settle(tester);
      expect(find.byKey(SubscriptionDetailScreen.priceKey), findsOneWidget);
      expect(find.text(l10n.subscriptionsEveryDay(12)), findsOneWidget);
      expect(
        find.byKey(SubscriptionDetailScreen.chargeKey('music-charge')),
        findsOneWidget,
      );
      expect(
        find.text(
          l10n.subscriptionDetailChargeUp(MoneyFormat.format(const Money(200))),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.subscriptionDetailSpent(5)), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await settle(tester);
      expect(find.byKey(SubscriptionsScreen.rowKey('music')), findsOneWidget);

      await tester.tap(find.byKey(SubscriptionsScreen.rowKey('music')));
      await settle(tester);
      await tester.tap(
        find.byKey(SubscriptionDetailScreen.chargeKey('music-charge')),
      );
      await settle(tester);
      expect(app.location, AppRoutes.transaction('music-charge'));
    });

    testWidgets('a suggestion opens, confirms and stays, or goes away', (
      tester,
    ) async {
      await pumpRoute(tester, AppRoutes.subscription('gym'));

      expect(find.text(l10n.subscriptionDetailSuggestionHint), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(SubscriptionDetailScreen.confirmKey),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(SubscriptionDetailScreen.confirmKey));
      await settle(tester);
      expect(find.text(l10n.subscriptionsConfirmed), findsOneWidget);
      expect(find.text(l10n.subscriptionDetailSuggestionHint), findsNothing);
      expect(find.byKey(SubscriptionDetailScreen.removeKey), findsOneWidget);

      await pumpRoute(tester, AppRoutes.subscription('nothing-here'));
      expect(find.text(l10n.subscriptionDetailNotFound), findsOneWidget);
    });

    testWidgets('Cartões leads with the bill to pay, its history and charges', (
      tester,
    ) async {
      final app = await pumpRoute(tester, AppRoutes.cards);

      expect(find.byKey(CardsScreen.cardKey('acc-pf-card')), findsOneWidget);
      expect(
        find.text(
          '${l10n.cardsBillOf(monthName(l10n, _october))} · '
          '${l10n.cardsStateClosed}',
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.cardsDueIn(6)), findsOneWidget);
      expect(
        find.text(l10n.cardsClosedDates('07/10', '14/10')),
        findsOneWidget,
      );
      expect(
        find.text(
          l10n.cardsAverage(6, MoneyFormat.format(const Money(203_768))),
        ),
        findsOneWidget,
      );
      expect(find.text('Mercado Bom Preço'), findsWidgets);

      await tester.tap(find.text(shortMonth(l10n, const YearMonth(2026, 11))));
      await settle(tester);
      expect(find.text(l10n.cardsBillDates('07/11', '14/11')), findsOneWidget);
      expect(find.text('Padaria Trigo Bom'), findsWidgets);

      await tester.tap(find.text(shortMonth(l10n, const YearMonth(2026, 9))));
      await settle(tester);
      expect(find.text(l10n.cardsPastDue('14/09')), findsOneWidget);

      await tester.tap(find.byKey(CardsScreen.seeInBillsKey));
      await settle(tester);
      expect(app.location, AppRoutes.bills);
    });

    testWidgets('Cartões imports a bill and shows each limit', (tester) async {
      final app = await pumpRoute(tester, AppRoutes.cards);
      await tester.tap(find.byKey(CardsScreen.importKey));
      await settle(tester);
      expect(app.location, AppRoutes.cardImport);
      app.router.pop();
      await settle(tester);

      await tester.tap(find.byKey(CardsScreen.limitsTabKey));
      await settle(tester);
      expect(
        find.text(
          l10n.cardsUsed(
            MoneyFormat.format(const Money(189_045)),
            MoneyFormat.format(const Money(800_000)),
          ),
        ),
        findsOneWidget,
      );
    });
  });

  group('on a mocked repository', () {
    late MockInsightsRepository repository;

    setUpAll(() => registerFallbackValue(EntityScope.personal));
    setUp(() => repository = MockInsightsRepository());

    List<Override> overrides() => [
      insightsRepositoryProvider.overrideWithValue(repository),
    ];

    Future<Result<MonthlyInsights>> Function() monthsCall() =>
        () => repository.months(
          any(),
          count: any(named: 'count'),
          month: any(named: 'month'),
        );

    testWidgets('pulling Análises fetches the window again', (tester) async {
      when(monthsCall()).thenAnswer((_) async => Ok(_monthly()));
      await pumpRoute(tester, AppRoutes.insights, overrides: overrides());
      verify(monthsCall()).called(1);

      await tester.fling(
        find.byType(ListView).last,
        const Offset(0, 1500),
        1000,
      );
      await settle(tester);

      verify(monthsCall()).called(1);
    });

    testWidgets('Análises retries a failure and reads a month with no income', (
      tester,
    ) async {
      when(monthsCall()).thenAnswer((_) async => const Err(NetworkFailure()));

      await pumpRoute(tester, AppRoutes.insights, overrides: overrides());
      expect(find.text(l10n.errorNetwork), findsOneWidget);

      when(monthsCall()).thenAnswer((_) async => Ok(_monthly()));
      await tester.tap(find.byKey(CdErrorState.retryKey));
      await settle(tester);

      expect(find.text(l10n.insightsSavingsNoIncome), findsOneWidget);
      expect(find.text(l10n.insightsChangesEmpty), findsOneWidget);
      expect(find.text(l10n.insightSavingsDown(5, 11)), findsOneWidget);
      expect(
        find.text(
          l10n.insightPriceUp(
            'Música Onda',
            MoneyFormat.format(const Money(2_190)),
            MoneyFormat.format(const Money(1_990)),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Análises reads a savings rate without an average', (
      tester,
    ) async {
      when(monthsCall()).thenAnswer((_) async => Ok(_monthly(percent: 12)));

      await pumpRoute(tester, AppRoutes.insights, overrides: overrides());

      expect(find.text(l10n.insightsPercent(12)), findsOneWidget);
      expect(find.text(l10n.insightsSavingsNoAverage), findsOneWidget);
    });

    testWidgets('Parcelamentos is empty or retries a failure', (tester) async {
      when(() => repository.installments(any()))
          .thenAnswer((_) async => const Err(NetworkFailure()));

      await pumpRoute(tester, AppRoutes.installments, overrides: overrides());
      expect(find.text(l10n.errorNetwork), findsOneWidget);

      when(
        () => repository.installments(any()),
      ).thenAnswer((_) async => const Ok(Installments(months: [], plans: [])));
      await tester.tap(find.byKey(CdErrorState.retryKey));
      await settle(tester);
      expect(find.text(l10n.installmentsEmpty), findsOneWidget);
    });

    testWidgets('Assinaturas is empty, retries and says why a decision fails', (
      tester,
    ) async {
      when(() => repository.subscriptions(any()))
          .thenAnswer((_) async => const Err(NetworkFailure()));

      await pumpRoute(tester, AppRoutes.subscriptions, overrides: overrides());
      expect(find.text(l10n.errorNetwork), findsOneWidget);

      when(() => repository.subscriptions(any())).thenAnswer(
        (_) async => const Ok(
          Subscriptions(
            monthly: Money(0),
            yearly: Money(0),
            previousMonth: Money(0),
            items: [],
            suggestions: [],
          ),
        ),
      );
      await tester.tap(find.byKey(CdErrorState.retryKey));
      await settle(tester);
      expect(find.text(l10n.subscriptionsEmpty), findsOneWidget);

      when(() => repository.subscriptions(any())).thenAnswer(
        (_) async => Ok(
          Subscriptions(
            monthly: const Money(2_190),
            yearly: const Money(26_280),
            previousMonth: const Money(2_190),
            items: [_subscription(id: 'music')],
            suggestions: [
              _subscription(transactionIds: ['tx-1']),
            ],
          ),
        ),
      );
      when(() => repository.confirmSubscription('tx-1'))
          .thenAnswer((_) async => const Err(NotFoundFailure()));
      when(() => repository.removeSubscription('music'))
          .thenAnswer((_) async => const Err(NetworkFailure()));
      final app = await pumpRoute(
        tester,
        AppRoutes.subscriptions,
        overrides: overrides(),
      );
      app.invalidate(subscriptionsControllerProvider);
      await settle(tester);

      await tester.tap(find.byKey(SubscriptionsScreen.confirmKey('music')));
      await settle(tester);
      expect(find.text(l10n.subscriptionsConfirmed), findsNothing);
      expect(find.text(l10n.subscriptionsSuggestionTitle), findsOneWidget);

      await tester.tap(find.byKey(SubscriptionsScreen.rowKey('music')));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.byKey(SubscriptionDetailScreen.removeKey),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(SubscriptionDetailScreen.removeKey));
      await settle(tester);
      await tester.tap(find.byKey(SubscriptionDetailScreen.removeConfirmKey));
      await settle(tester);
      expect(find.text(l10n.errorNetwork), findsOneWidget);
      expect(find.byType(SubscriptionDetailScreen), findsOneWidget);
    });

    testWidgets('only the tapped suggestion spins while it waits', (
      tester,
    ) async {
      final pending = Completer<Result<String>>();
      when(() => repository.subscriptions(any())).thenAnswer(
        (_) async => Ok(
          Subscriptions(
            monthly: const Money(0),
            yearly: const Money(0),
            previousMonth: const Money(0),
            items: const [],
            suggestions: [
              _subscription(transactionIds: ['tx-1']),
              _subscription(key: 'cloud', transactionIds: ['tx-2']),
            ],
          ),
        ),
      );
      when(() => repository.confirmSubscription('tx-1'))
          .thenAnswer((_) => pending.future);
      await pumpRoute(tester, AppRoutes.subscriptions, overrides: overrides());

      await tester.tap(find.byKey(SubscriptionsScreen.confirmKey('music')));
      await tester.pump();

      Finder spinnerIn(Key key) => find.descendant(
        of: find.byKey(key),
        matching: find.byType(CircularProgressIndicator),
      );
      CdButton button(Key key) => tester.widget<CdButton>(find.byKey(key));
      expect(
        spinnerIn(SubscriptionsScreen.confirmKey('music')),
        findsOneWidget,
      );
      expect(spinnerIn(SubscriptionsScreen.dismissKey('music')), findsNothing);
      expect(spinnerIn(SubscriptionsScreen.confirmKey('cloud')), findsNothing);
      expect(spinnerIn(SubscriptionsScreen.dismissKey('cloud')), findsNothing);
      expect(button(SubscriptionsScreen.dismissKey('music')).onPressed, isNull);
      expect(
        button(SubscriptionsScreen.confirmKey('cloud')).onPressed,
        isNotNull,
      );
      expect(button(SubscriptionsScreen.confirmKey('cloud')).loading, isFalse);

      pending.complete(const Err(NotFoundFailure()));
      await settle(tester);
      expect(spinnerIn(SubscriptionsScreen.confirmKey('music')), findsNothing);
      expect(
        button(SubscriptionsScreen.confirmKey('music')).onPressed,
        isNotNull,
      );
    });

    test(
      'a decision without a charge or an id fails before the server',
      () async {
        final container = ProviderContainer(overrides: overrides());
        addTearDown(container.dispose);
        when(() => repository.subscriptions(any())).thenAnswer(
          (_) async => const Ok(
            Subscriptions(
              monthly: Money(0),
              yearly: Money(0),
              previousMonth: Money(0),
              items: [],
              suggestions: [],
            ),
          ),
        );
        final listener = container.listen(
          subscriptionsControllerProvider,
          (_, _) {},
        );
        addTearDown(listener.close);
        await container.read(subscriptionsControllerProvider.future);
        final controller = container.read(
          subscriptionsControllerProvider.notifier,
        );

        expect(
          await controller.decide(
            _subscription(),
            SubscriptionDecision.confirm,
          ),
          isA<UnexpectedFailure>(),
        );
        expect(
          await controller.remove(_subscription()),
          isA<UnexpectedFailure>(),
        );
      },
    );
  });

  group('Cartões on given accounts', () {
    TransactionAccount card(String id, {CreditLine? credit}) =>
        TransactionAccount(
          id: id,
          name: 'Cartão $id',
          owner: EntityKind.personal,
          institution: 'Banco Aurora',
          type: AccountType.creditCard,
          balance: const Money(-10_000),
          credit: credit,
        );

    CardBill bill(
      CardBillState state,
      int day, {
      CalendarDate? closesOn,
      int total = 10_000,
    }) => CardBill(
      closesOn: closesOn,
      dueOn: CalendarDate(2026, 10, day),
      total: Money(total),
      state: state,
      range: const DateSpan(
        CalendarDate(2026, 9, 1),
        CalendarDate(2026, 9, 30),
      ),
    );

    const charge = Transaction(
      id: 'charge',
      accountId: 'a',
      owner: EntityKind.personal,
      amount: Money(-4_200),
      bookedOn: CalendarDate(2026, 9, 12),
      description: 'Livraria Exemplo',
      kind: TransactionKind.expense,
    );

    List<Override> withBills(
      List<CardBills> cards, {
      Future<List<Transaction>> Function()? charges,
      List<TransactionAccount>? accounts,
    }) => [
      transactionAccountsProvider.overrideWith(
        (ref) async => accounts ?? [card('a'), card('b')],
      ),
      cardBillsProvider.overrideWith((ref) async => cards),
      billChargesProvider.overrideWith(
        (ref, _) => charges?.call() ?? Future.value(<Transaction>[]),
      ),
    ];

    testWidgets('reads open and closed bills without a closing day', (
      tester,
    ) async {
      await pumpRoute(
        tester,
        AppRoutes.cards,
        overrides: withBills([
          CardBills(
            accountId: 'a',
            name: 'Cartão a',
            suffix: '1234',
            owner: EntityKind.personal,
            bills: [bill(CardBillState.open, 20)],
          ),
          CardBills(
            accountId: 'b',
            name: 'Cartão b',
            owner: EntityKind.personal,
            bills: [
              bill(CardBillState.closed, 9),
              bill(CardBillState.past, 1, total: 20_000),
            ],
          ),
          const CardBills(
            accountId: 'c',
            name: 'Cartão c',
            owner: EntityKind.personal,
            bills: [],
          ),
        ]),
      );

      expect(find.text(l10n.cardsBillDue('20/10')), findsOneWidget);
      expect(find.byType(CdColumnBars), findsNothing);
      expect(find.text(l10n.cardsNoCharges), findsOneWidget);

      await tester.tap(find.byKey(CardsScreen.cardKey('b')));
      await settle(tester);
      expect(find.text(l10n.cardsDueIn(1)), findsOneWidget);
      expect(find.byType(CdColumnBars), findsOneWidget);
      expect(
        find.text(
          l10n.cardsAverage(2, MoneyFormat.format(const Money(15_000))),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(CardsScreen.cardKey('c')));
      await settle(tester);
      expect(find.text(l10n.cardsNoBills), findsOneWidget);
    });

    testWidgets('a charge opens its transaction and a failure retries', (
      tester,
    ) async {
      var fail = true;
      final app = await pumpRoute(
        tester,
        AppRoutes.cards,
        overrides: withBills(
          [
            CardBills(
              accountId: 'a',
              name: 'Cartão a',
              owner: EntityKind.personal,
              bills: [bill(CardBillState.closed, 9)],
            ),
          ],
          charges: () async {
            if (fail) throw const LoadFailure(NetworkFailure());
            return [charge];
          },
        ),
      );

      expect(find.text(l10n.homeSectionFailed), findsOneWidget);
      fail = false;
      await tester.tap(find.byKey(CardsScreen.chargesRetryKey));
      await settle(tester);
      await tester.tap(find.byKey(CardsScreen.chargeKey('charge')));
      await settle(tester);
      expect(app.location, AppRoutes.transaction('charge'));
    });

    testWidgets('no bills at all still offers the import', (tester) async {
      await pumpRoute(tester, AppRoutes.cards, overrides: withBills([]));
      expect(find.text(l10n.cardsNoBills), findsOneWidget);
      expect(find.byKey(CardsScreen.importKey), findsOneWidget);
    });

    testWidgets('a failed load of the bills retries', (tester) async {
      var fail = true;
      await pumpRoute(
        tester,
        AppRoutes.cards,
        overrides: [
          transactionAccountsProvider.overrideWith((ref) async => [card('a')]),
          cardBillsProvider.overrideWith((ref) async {
            if (fail) throw const LoadFailure(NetworkFailure());
            return <CardBills>[];
          }),
        ],
      );
      expect(find.byType(CdErrorState), findsOneWidget);
      fail = false;
      await tester.tap(find.text(l10n.retryButton));
      await settle(tester);
      expect(find.text(l10n.cardsNoBills), findsOneWidget);
    });

    testWidgets('reads a card without a limit', (tester) async {
      await pumpRoute(
        tester,
        AppRoutes.cards,
        overrides: withBills(
          [],
          accounts: [
            card(
              'a',
              credit: const CreditLine(
                limit: Money(100_000),
                available: Money(90_000),
              ),
            ),
            card('c'),
          ],
        ),
      );

      await tester.tap(find.byKey(CardsScreen.limitsTabKey));
      await settle(tester);
      expect(find.text(l10n.cardsNoLimit), findsOneWidget);
      expect(find.text(l10n.insightsPercent(10)), findsOneWidget);
    });

    testWidgets('asks for a card when there is none and retries a failure', (
      tester,
    ) async {
      var fail = true;
      await pumpRoute(
        tester,
        AppRoutes.cards,
        overrides: [
          transactionAccountsProvider.overrideWith((ref) async {
            if (fail) throw const LoadFailure(NetworkFailure());
            return <TransactionAccount>[];
          }),
        ],
      );
      expect(find.text(l10n.errorNetwork), findsOneWidget);

      fail = false;
      await tester.tap(find.byKey(CdErrorState.retryKey));
      await settle(tester);
      expect(find.text(l10n.cardsEmpty), findsOneWidget);
    });
  });
}
