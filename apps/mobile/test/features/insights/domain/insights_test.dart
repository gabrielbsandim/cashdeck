import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:flutter_test/flutter_test.dart';

const _day = CalendarDate(2026, 10, 8);
const _month = YearMonth(2026, 10);

InstallmentPlan _plan({int number = 2}) => InstallmentPlan(
  key: 'k',
  accountId: 'a',
  card: 'Card',
  owner: EntityKind.personal,
  name: 'Sofa',
  number: number,
  count: 4,
  amount: const Money(100),
  paid: const Money(200),
  remaining: const Money(200),
  total: const Money(400),
  lastBilledOn: _day,
  finalMonth: _month,
);

Subscription _subscription({String? id}) => Subscription(
  id: id,
  key: 'k',
  owner: EntityKind.personal,
  name: 'Stream',
  amount: const Money(100),
  priceChanged: false,
  dayOfMonth: 7,
  thisMonth: SubscriptionMonthStatus.upcoming,
  transactionIds: const ['t'],
);

void main() {
  test('values compare by content', () {
    const span = DateSpan(_day, _day);
    const point = SpendPoint(_day, Money(1));
    const merchant = MerchantSpend(name: 'M', total: Money(1), count: 1);
    const share = CategoryShare(total: Money(1), sharePercent: 100);
    const flow = CashFlow(
      income: Money(2),
      expenses: Money(1),
      result: Money(1),
    );
    const cards = CardsSummary(bill: Money(1), count: 1);
    const bills = BillsDue(days: 7, total: Money(1), count: 1);
    const spend = SpendSummary(
      total: Money(1),
      previous: Money(1),
      series: [point],
      previousSeries: [point],
      topMerchants: [merchant],
    );
    const overview = InsightsOverview(
      period: InsightPeriod.month,
      range: span,
      previousRange: span,
      spend: spend,
      categoryTotal: Money(1),
      categories: [share],
      flow: flow,
      cards: cards,
      billsDue: bills,
    );
    const result = MonthResult(
      month: _month,
      income: Money(2),
      expenses: Money(1),
      result: Money(1),
    );
    const savings = SavingsRate(trend: [(_month, 50)], percent: 50);
    const change = CategoryChange(
      categoryId: 'c',
      name: 'C',
      total: Money(2),
      average: Money(1),
      delta: Money(1),
    );
    const fixed = FixedCost(
      subscriptions: Money(1),
      installments: Money(1),
      bills: Money(1),
      total: Money(3),
      income: Money(10),
    );
    const left = LeftThisMonth(
      balance: Money(10),
      billsDue: Money(1),
      cardBill: Money(1),
      left: Money(8),
    );
    const company = CompanyToPersonal(transfers: Money(1), taxes: Money(1));
    final insights = <Insight>[
      const CategoryAboveAverage(
        tone: InsightTone.negative,
        categoryId: 'c',
        name: 'C',
        percent: 30,
        amount: Money(1),
      ),
      const InstallmentsCommitted(
        tone: InsightTone.neutral,
        month: _month,
        amount: Money(1),
      ),
      const SavingsRateChanged(
        tone: InsightTone.positive,
        percent: 20,
        averagePercent: 10,
      ),
      const SubscriptionPriceUp(
        tone: InsightTone.negative,
        name: 'S',
        amount: Money(2),
        previousAmount: Money(1),
      ),
    ];
    final monthly = MonthlyInsights(
      month: _month,
      months: const [result],
      savings: savings,
      rose: const [change],
      fell: const [],
      fixedCost: fixed,
      leftThisMonth: left,
      companyToPersonal: company,
      insights: insights,
    );
    final installments = Installments(
      months: const [(_month, Money(1))],
      plans: [_plan()],
    );
    final subscriptions = Subscriptions(
      monthly: const Money(1),
      yearly: const Money(12),
      previousMonth: const Money(1),
      items: [_subscription(id: 'r')],
      suggestions: [_subscription()],
    );
    final values = <Object>[
      span,
      point,
      merchant,
      share,
      flow,
      cards,
      bills,
      spend,
      overview,
      result,
      savings,
      change,
      fixed,
      left,
      company,
      ...insights,
      monthly,
      installments,
      subscriptions,
    ];
    for (final value in values) {
      expect(value, value);
      expect((value as dynamic).props, isNotEmpty);
    }
    expect(_plan(), _plan());
    expect(_plan(number: 3), isNot(_plan()));
  });

  test('a subscription adds up its year and its charges', () {
    const charge = SubscriptionCharge(
      transactionId: 't',
      bookedOn: CalendarDate(2026, 9, 7),
      amount: Money(90),
    );
    const subscription = Subscription(
      key: 'k',
      owner: EntityKind.personal,
      name: 'Stream',
      amount: Money(100),
      priceChanged: true,
      dayOfMonth: 7,
      thisMonth: SubscriptionMonthStatus.paid,
      transactionIds: ['t', 'u'],
      nextChargeOn: CalendarDate(2026, 11, 7),
      charges: [
        charge,
        SubscriptionCharge(
          transactionId: 'u',
          bookedOn: CalendarDate(2026, 10, 7),
          amount: Money(100),
        ),
      ],
    );
    expect(subscription.yearly, const Money(1_200));
    expect(subscription.spent, const Money(190));
    expect(_subscription().spent, const Money(0));
    expect(charge, charge);
    expect(charge.props, isNotEmpty);
  });

  test('a card looks first at the bill to pay and averages closed ones', () {
    CardBill bill(CardBillState state, int cents) => CardBill(
      dueOn: const CalendarDate(2026, 10, 14),
      total: Money(cents),
      state: state,
      range: const DateSpan(
        CalendarDate(2026, 9, 8),
        CalendarDate(2026, 10, 7),
      ),
    );
    CardBills card(List<CardBill> bills) => CardBills(
      accountId: 'card',
      name: 'Cartão',
      owner: EntityKind.personal,
      bills: bills,
    );

    final full = card([
      bill(CardBillState.open, 9_000),
      bill(CardBillState.closed, 10_000),
      bill(CardBillState.past, 20_001),
    ]);
    expect(full.focus, 1);
    expect(full.average(), const Money(15_001));
    expect(full.averaged(), 2);
    expect(full.average(1), const Money(10_000));
    expect(card([bill(CardBillState.open, 1)]).focus, 0);
    expect(card([bill(CardBillState.open, 1)]).average(), isNull);
    expect(card(const []).focus, isNull);
    expect(full, card([...full.bills]));
    expect(full.bills.first, bill(CardBillState.open, 9_000));
  });

  test('a plan counts what is left and a suggestion has no id', () {
    expect(_plan().left, 2);
    expect(_subscription().isSuggestion, isTrue);
    expect(_subscription(), _subscription());
    expect(_subscription().props, hasLength(15));
    expect(_subscription(id: 'r').isSuggestion, isFalse);
  });
}
