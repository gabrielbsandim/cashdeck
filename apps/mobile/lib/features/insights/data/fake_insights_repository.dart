import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:cashdeck/features/insights/domain/insights_repository.dart';

/// Fictional spending around today. Subscription decisions live in memory
/// for the session.
final class FakeInsightsRepository implements InsightsRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 300)});

  final Clock _clock;
  final Duration latency;
  final Set<String> _confirmed = {};
  final Set<String> _dismissed = {};
  final Set<String> _removed = {};

  CalendarDate get _today => CalendarDate.brazilToday(_clock.now());

  Future<void> _wait() => Future<void>.delayed(latency);

  static const _dailySpend = [210, 270, 530, 230, 950, 370, 460, 392];

  static List<SpendPoint> _cumulative(
    CalendarDate from,
    int days,
    int Function(int day) spendOf,
  ) {
    var running = 0;
    return [
      for (var day = 0; day < days; day++)
        SpendPoint(from.addDays(day), Money(running += spendOf(day) * 100)),
    ];
  }

  @override
  Future<Result<InsightsOverview>> overview(
    EntityScope scope,
    InsightPeriod period,
  ) async {
    await _wait();
    final today = _today;
    final month = YearMonth.of(today);
    final previous = month.add(-1);
    final series = _cumulative(
      month.firstDay,
      today.day,
      (day) => _dailySpend[day % _dailySpend.length],
    );
    final previousSeries = _cumulative(
      previous.firstDay,
      previous.dayCount,
      (day) => 180 + (day * 37) % 160,
    );
    final total = series.last.cumulative;
    final before = previousSeries[today.day - 1].cumulative;
    return Ok(
      InsightsOverview(
        period: period,
        range: DateSpan(month.firstDay, today),
        previousRange: DateSpan(
          previous.firstDay,
          previous.firstDay.addDays(previous.dayCount - 1),
        ),
        spend: SpendSummary(
          total: total,
          previous: before,
          changePercent: ((total.cents - before.cents) * 100) ~/ before.cents,
          series: series,
          previousSeries: previousSeries,
          topMerchants: const [
            MerchantSpend(
              name: 'Mercado Bom Preço',
              total: Money(84_210),
              count: 6,
            ),
            MerchantSpend(
              name: 'Posto Avenida',
              total: Money(42_000),
              count: 2,
            ),
            MerchantSpend(
              name: 'Café da Praça',
              total: Money(18_640),
              count: 9,
            ),
          ],
        ),
        categoryTotal: total,
        categories: _shares(total),
        flow: CashFlow(
          income: const Money(825_000),
          expenses: total,
          result: Money(825_000 - total.cents),
        ),
        cards: CardsSummary(
          bill: const Money(218_455),
          dueOn: today.addDays(9),
          count: 2,
          limit: const Money(1_500_000),
          used: const Money(611_200),
          usedPercent: 41,
        ),
        billsDue: const BillsDue(days: 7, total: Money(128_740), count: 3),
      ),
    );
  }

  static List<CategoryShare> _shares(Money total) {
    const parts = [
      ('groceries', 'Mercado', 'shopping_cart', 34, 12),
      ('restaurants', 'Restaurantes', 'restaurant', 21, 31),
      ('transport', 'Transporte', 'directions_car', 15, -8),
      (null, null, null, 30, null),
    ];
    return [
      for (final (key, name, icon, share, change) in parts)
        CategoryShare(
          categoryId: key,
          key: key,
          name: name,
          icon: icon,
          total: Money(total.cents * share ~/ 100),
          sharePercent: share,
          changePercent: change,
        ),
    ];
  }

  @override
  Future<Result<MonthlyInsights>> months(
    EntityScope scope, {
    required int count,
    YearMonth? month,
  }) async {
    await _wait();
    final current = YearMonth.of(_today);
    final last = month ?? current;
    final results = [
      for (var index = count - 1; index >= 0; index--)
        _result(last.add(-index), index),
    ];
    final company = scope != EntityScope.personal;
    return Ok(
      MonthlyInsights(
        month: last,
        months: results,
        savings: SavingsRate(
          percent: 15,
          averagePercent: 11,
          trend: [
            for (final result in results)
              (result.month, result.result.cents * 100 ~/ result.income.cents),
          ],
        ),
        rose: const [
          CategoryChange(
            categoryId: 'restaurants',
            key: 'restaurants',
            name: 'Restaurantes',
            icon: 'restaurant',
            total: Money(71_800),
            average: Money(54_800),
            delta: Money(17_000),
          ),
        ],
        fell: const [
          CategoryChange(
            categoryId: 'transport',
            key: 'transport',
            name: 'Transporte',
            icon: 'directions_car',
            total: Money(41_200),
            average: Money(52_900),
            delta: Money(-11_700),
          ),
        ],
        fixedCost: const FixedCost(
          subscriptions: Money(18_870),
          installments: Money(121_240),
          bills: Money(240_000),
          total: Money(380_110),
          income: Money(825_000),
          sharePercent: 46,
        ),
        leftThisMonth: last == current
            ? const LeftThisMonth(
                balance: Money(1_874_230),
                billsDue: Money(128_740),
                cardBill: Money(218_455),
                left: Money(1_527_035),
              )
            : null,
        companyToPersonal: company
            ? const CompanyToPersonal(
                transfers: Money(900_000),
                taxes: Money(276_000),
              )
            : null,
        insights: [
          const CategoryAboveAverage(
            tone: InsightTone.negative,
            categoryId: 'restaurants',
            name: 'Restaurantes',
            percent: 31,
            amount: Money(17_000),
          ),
          InstallmentsCommitted(
            tone: InsightTone.neutral,
            month: current.add(1),
            amount: const Money(121_240),
          ),
          const SavingsRateChanged(
            tone: InsightTone.positive,
            percent: 15,
            averagePercent: 11,
          ),
        ],
      ),
    );
  }

  static MonthResult _result(YearMonth month, int index) {
    const income = 825_000;
    final expenses = 690_000 + (index * 41_000) % 120_000;
    return MonthResult(
      month: month,
      income: const Money(income),
      expenses: Money(expenses),
      result: Money(income - expenses),
    );
  }

  @override
  Future<Result<Installments>> installments(EntityScope scope) async {
    await _wait();
    final month = YearMonth.of(_today);
    final plans = [
      _installment('notebook', 'Notebook Orion', 4, 10, 32_990, month),
      _installment('sofa', 'Sofá Linho', 7, 12, 41_500, month),
      _installment('bike', 'Bicicleta Trilha', 2, 6, 46_750, month),
    ];
    return Ok(
      Installments(
        months: [
          for (var index = 1; index <= 12; index++)
            (
              month.add(index),
              Money(
                plans
                    .where((plan) => plan.left >= index)
                    .fold(0, (sum, plan) => sum + plan.amount.cents),
              ),
            ),
        ],
        plans: plans,
      ),
    );
  }

  InstallmentPlan _installment(
    String key,
    String name,
    int number,
    int count,
    int cents,
    YearMonth month,
  ) => InstallmentPlan(
    key: key,
    accountId: 'aurora-card',
    card: 'Aurora Platinum',
    cardSuffix: '4821',
    owner: EntityKind.personal,
    name: name,
    number: number,
    count: count,
    amount: Money(cents),
    paid: Money(cents * number),
    remaining: Money(cents * (count - number)),
    total: Money(cents * count),
    purchaseOn: month.add(1 - number).firstDay.addDays(4),
    lastBilledOn: month.firstDay.addDays(4),
    finalMonth: month.add(count - number),
  );

  static const _charges = [
    ('stream', 'Streaming Nuvem', 5_590, 5_590, 5),
    ('music', 'Música Onda', 2_190, 1_990, 12),
    ('cloud', 'Armazenamento Céu', 1_090, 1_090, 20),
    ('gym', 'Academia Ritmo', 10_000, 10_000, 1),
  ];

  Subscription _charge(
    (String, String, int, int, int) charge,
    CalendarDate today, {
    required bool confirmed,
  }) {
    final (key, name, cents, before, day) = charge;
    final status = switch (day) {
      _ when day <= today.day - 3 => SubscriptionMonthStatus.paid,
      _ when day < today.day => SubscriptionMonthStatus.late,
      _ => SubscriptionMonthStatus.upcoming,
    };
    return Subscription(
      id: confirmed ? key : null,
      key: key,
      owner: EntityKind.personal,
      name: name,
      amount: Money(cents),
      previousAmount: Money(before),
      priceChanged: cents != before,
      dayOfMonth: day,
      lastChargeOn: YearMonth.of(today).add(-1).firstDay.addDays(day - 1),
      thisMonth: status,
      accountId: 'aurora-card',
      transactionIds: ['$key-charge'],
    );
  }

  static const _billTotals = [
    189_045,
    218_455,
    196_310,
    241_920,
    187_640,
    205_880,
    172_400,
  ];

  @override
  Future<Result<List<CardBills>>> cardBills(EntityScope scope) async {
    await _wait();
    if (!scope.includes(EntityKind.personal)) return const Ok([]);
    final today = _today;
    final next = YearMonth.of(today).add(1);
    CalendarDate closing(int back) {
      final month = next.add(-back);
      return CalendarDate(month.year, month.month, 7);
    }

    CardBillState stateOf(CalendarDate closes, CalendarDate due) {
      if (!closes.isBefore(today)) return CardBillState.open;
      return due.isBefore(today) ? CardBillState.past : CardBillState.closed;
    }

    return Ok([
      CardBills(
        accountId: 'acc-pf-card',
        name: 'Cartão Horizonte',
        suffix: '9021',
        owner: EntityKind.personal,
        bills: [
          for (final (back, total) in _billTotals.indexed)
            CardBill(
              closesOn: closing(back),
              dueOn: closing(back).addDays(7),
              total: Money(total),
              minimum: back == 0 ? null : Money(total ~/ 10),
              state: stateOf(closing(back), closing(back).addDays(7)),
              range: DateSpan(closing(back + 1).addDays(1), closing(back)),
            ),
        ],
      ),
    ]);
  }

  @override
  Future<Result<Subscriptions>> subscriptions(EntityScope scope) async {
    await _wait();
    final today = _today;
    bool confirmed(String key) =>
        (key != 'gym' || _confirmed.contains('gym-charge')) &&
        !_removed.contains(key);
    final items = [
      for (final charge in _charges)
        if (confirmed(charge.$1)) _charge(charge, today, confirmed: true),
    ];
    final suggestions = [
      for (final charge in _charges)
        if (charge.$1 == 'gym' &&
            !_confirmed.contains('gym-charge') &&
            !_dismissed.contains('gym-charge'))
          _charge(charge, today, confirmed: false),
    ];
    final monthly = items.fold(0, (sum, item) => sum + item.amount.cents);
    return Ok(
      Subscriptions(
        monthly: Money(monthly),
        yearly: Money(monthly * 12),
        previousMonth: const Money(8_670),
        changePercent: 3,
        items: items,
        suggestions: suggestions,
      ),
    );
  }

  @override
  Future<Result<String>> confirmSubscription(String transactionId) async {
    await _wait();
    if (transactionId != 'gym-charge') {
      return const Err(NotFoundFailure());
    }
    _confirmed.add(transactionId);
    return const Ok('gym');
  }

  @override
  Future<Result<void>> dismissSubscription(String transactionId) async {
    await _wait();
    _dismissed.add(transactionId);
    return const Ok(null);
  }

  @override
  Future<Result<void>> removeSubscription(String id) async {
    await _wait();
    _removed.add(id);
    return const Ok(null);
  }
}
