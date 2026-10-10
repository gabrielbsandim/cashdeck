import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/insights/domain/card_timeline.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:cashdeck/features/insights/presentation/card_timeline_screen.dart';
import 'package:cashdeck/features/insights/presentation/cards_screen.dart';
import 'package:cashdeck/features/insights/presentation/insights_controller.dart';
import 'package:cashdeck/features/insights/presentation/insights_labels.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_harness.dart';
import '../../../support/pump_app.dart';

const _card = TransactionAccount(
  id: 'card',
  name: 'Cartão Exemplo',
  owner: EntityKind.personal,
  institution: 'Banco Exemplo',
  type: AccountType.creditCard,
  balance: Money(-40_000),
);

TimelineBill _bill(
  TimelineBillState state,
  CalendarDate dueOn, {
  CalendarDate? closesOn,
  BillPayment? payment,
  Money? minimum,
  List<PlannedInstallment> installments = const [],
}) => TimelineBill(
  closesOn: closesOn,
  dueOn: dueOn,
  total: const Money(10_000),
  minimum: minimum,
  state: state,
  payment: payment,
  range: DateSpan(dueOn.addDays(-35), dueOn.addDays(-6)),
  installments: installments,
);

final _timeline = CardTimeline(
  accountId: 'card',
  name: 'Cartão Exemplo',
  suffix: '4821',
  owner: EntityKind.personal,
  current: 3,
  bills: [
    _bill(
      TimelineBillState.past,
      const CalendarDate(2026, 8, 14),
      payment: BillPayment.unconfirmed,
    ),
    _bill(
      TimelineBillState.past,
      const CalendarDate(2026, 9, 14),
      payment: BillPayment.paid,
    ),
    _bill(
      TimelineBillState.closed,
      const CalendarDate(2026, 10, 14),
      closesOn: const CalendarDate(2026, 10, 7),
      payment: BillPayment.due,
      minimum: const Money(1_500),
    ),
    _bill(TimelineBillState.open, const CalendarDate(2026, 11, 14)),
    _bill(
      TimelineBillState.forecast,
      const CalendarDate(2026, 12, 14),
      closesOn: const CalendarDate(2026, 12, 7),
      installments: const [
        PlannedInstallment(
          key: 'plan',
          name: 'Loja Exemplo',
          categoryId: 'shopping',
          number: 4,
          count: 6,
          amount: Money(10_000),
        ),
      ],
    ),
    _bill(
      TimelineBillState.forecast,
      const CalendarDate(2027, 1, 14),
      closesOn: const CalendarDate(2027, 1, 7),
    ),
  ],
);

List<Override> _overrides(Future<CardTimeline> Function() load) => [
  transactionAccountsProvider.overrideWith((ref) async => [_card]),
  cardTimelineProvider.overrideWith((ref, _) => load()),
  billChargesProvider.overrideWith((ref, _) async => <Transaction>[]),
];

String _header(YearMonth month, String state, {bool year = false}) {
  final name = monthName(l10n, month);
  return '${l10n.cardsBillOf(year ? '$name ${month.year}' : name)} · $state';
}

Future<void> _swipe(WidgetTester tester, double dx) async {
  await tester.drag(find.byKey(CardTimelineScreen.pagesKey), Offset(dx, 0));
  await settle(tester);
}

void main() {
  testWidgets('opens on the open bill and swipes to past and forecast ones', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      AppRoutes.cardBills('card'),
      overrides: _overrides(() async => _timeline),
    );

    expect(find.text('Cartão Exemplo •• 4821'), findsOneWidget);
    expect(
      find.text(_header(const YearMonth(2026, 11), l10n.cardsStateOpen)),
      findsOneWidget,
    );
    expect(find.text(l10n.cardsBillDue('14/11')), findsOneWidget);

    await _swipe(tester, -600);
    expect(
      find.text(_header(const YearMonth(2026, 12), l10n.cardsStateForecast)),
      findsOneWidget,
    );
    expect(find.text(l10n.cardTimelineForecastNote), findsOneWidget);
    expect(find.text(l10n.cardsBillDates('07/12', '14/12')), findsOneWidget);
    expect(find.byKey(CardTimelineScreen.installmentKey('plan')), findsOne);
    expect(find.text('4/6 · ${l10n.cardsStateForecast}'), findsOneWidget);

    await tester.tap(find.byKey(CardTimelineScreen.nextKey));
    await settle(tester);
    expect(
      find.text(
        _header(const YearMonth(2027, 1), l10n.cardsStateForecast, year: true),
      ),
      findsOneWidget,
    );
    expect(find.text('jan 27'), findsOneWidget);
    final next = tester.widget<IconButton>(
      find.byKey(CardTimelineScreen.nextKey),
    );
    expect(next.onPressed, isNull);

    await _swipe(tester, 600);
    await _swipe(tester, 600);
    await _swipe(tester, 600);
    expect(
      find.text(_header(const YearMonth(2026, 10), l10n.cardsStateClosed)),
      findsOneWidget,
    );
    expect(find.text(l10n.cardsClosedDates('07/10', '14/10')), findsOneWidget);
    expect(find.text(l10n.cardsDueIn(6)), findsOneWidget);
    expect(find.text(l10n.cardTimelineDue), findsOneWidget);
    expect(
      find.text(
        l10n.cardTimelineMinimum(MoneyFormat.format(const Money(1_500))),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(CardTimelineScreen.previousKey));
    await settle(tester);
    expect(find.text(l10n.cardTimelinePaid), findsOneWidget);
    expect(find.text(l10n.cardsPastDue('14/09')), findsOneWidget);

    await tester.tap(find.byKey(CardTimelineScreen.monthKey(0)));
    await settle(tester);
    expect(find.text(l10n.cardTimelineUnconfirmed), findsOneWidget);
    final previous = tester.widget<IconButton>(
      find.byKey(CardTimelineScreen.previousKey),
    );
    expect(previous.onPressed, isNull);
  });

  testWidgets('shows a card without bills and retries a failed load', (
    tester,
  ) async {
    var fail = true;
    await pumpRoute(
      tester,
      AppRoutes.cardBills('card'),
      overrides: _overrides(() async {
        if (fail) throw const LoadFailure(NetworkFailure());
        return const CardTimeline(
          accountId: 'card',
          name: 'Cartão Exemplo',
          owner: EntityKind.personal,
          bills: [],
        );
      }),
    );

    expect(find.byType(CdErrorState), findsOneWidget);
    fail = false;
    await tester.tap(find.text(l10n.retryButton));
    await settle(tester);
    expect(find.text(l10n.cardsNoBills), findsOneWidget);
  });

  testWidgets('the rename action opens the name sheet', (tester) async {
    await pumpRoute(
      tester,
      AppRoutes.cardBills('card'),
      overrides: _overrides(() async => _timeline),
    );

    await tester.tap(find.byKey(CardTimelineScreen.renameKey));
    await settle(tester);
    expect(find.text(l10n.accountRenameTitle), findsOneWidget);
  });

  testWidgets('the cards screen opens every bill of the fake card', (
    tester,
  ) async {
    final app = await pumpRoute(tester, AppRoutes.cards);

    await tester.tap(find.byKey(CardsScreen.seeAllBillsKey));
    await settle(tester);

    expect(app.location, AppRoutes.cardBills('acc-pf-card'));
    expect(find.text('Cartão Horizonte ••9021'), findsOneWidget);
    expect(
      find.text(_header(const YearMonth(2026, 11), l10n.cardsStateOpen)),
      findsOneWidget,
    );
  });
}
