import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/outlook/domain/net_worth.dart';
import 'package:cashdeck/features/outlook/domain/outlook_repository.dart';
import 'package:cashdeck/features/outlook/domain/safe_to_spend.dart';

/// A fictional typical month with bills still owed, a company with no income
/// in sight, and a net worth that grew steadily every month.
final class FakeOutlookRepository implements OutlookRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 300)});

  final Clock _clock;
  final Duration latency;

  static const monthlyGrowth = Money(85_000);

  static const personal = NetWorthComposition(
    cash: Money(520_000),
    investments: Money(8_400_000),
    cardDebt: Money(142_300),
    assets: Money(8_920_000),
    liabilities: Money(142_300),
    total: Money(8_777_700),
  );

  static const company = NetWorthComposition(
    cash: Money(1_250_000),
    investments: Money(600_000),
    cardDebt: Money(0),
    assets: Money(1_850_000),
    liabilities: Money(0),
    total: Money(1_850_000),
  );

  CalendarDate get _today => CalendarDate.brazilToday(_clock.now());

  Future<void> _wait() => Future<void>.delayed(latency);

  static const typicalIncome = Money(2_400_000);
  static const typicalSavings = Money(650_000);

  Money? _savings;

  static const _payers = [
    IncomeSource(taxId: '11222333000181', name: 'Cliente Exemplo LTDA'),
    IncomeSource(taxId: '52998224725', name: 'Fulana de Tal'),
  ];

  Set<String> _sources = {};

  static CalendarDate _monthEnd(CalendarDate today) {
    final end = DateTime.utc(today.year, today.month + 1, 0);
    return CalendarDate(end.year, end.month, end.day);
  }

  @override
  Future<Result<SafeToSpend>> safeToSpend({
    EntityKind entity = EntityKind.personal,
  }) async {
    await _wait();
    final today = _today;
    if (entity == EntityKind.company) return Ok(_companySafeToSpend(today));
    return Ok(_personalSafeToSpend(today));
  }

  @override
  Future<Result<void>> setSavingsTarget(Money? savings) async {
    await _wait();
    _savings = savings;
    return const Ok(null);
  }

  @override
  Future<Result<List<IncomeSourceCandidate>>> incomeSources() async {
    await _wait();
    return Ok([
      for (final (index, payer) in _payers.indexed)
        IncomeSourceCandidate(
          source: payer,
          total: Money(index == 0 ? 12_000_000 : 1_800_000),
          months: 6,
          lastOn: _today.addDays(-index - 2),
          selected: _sources.contains(payer.taxId),
        ),
    ]);
  }

  @override
  Future<Result<void>> setIncomeSources(List<IncomeSource> sources) async {
    await _wait();
    _sources = {for (final source in sources) source.taxId};
    return const Ok(null);
  }

  /// A typical month less the savings target, what the cards and accounts
  /// already took this month and what is still owed until the month end.
  SafeToSpend _personalSafeToSpend(CalendarDate today) {
    final until = _monthEnd(today);
    final days = today.daysUntil(until) + 1;
    final savings = _savings ?? typicalSavings;
    final lines = [
      const SafeToSpendLine(
        kind: SafeToSpendLineKind.income,
        label: '',
        amount: typicalIncome,
      ),
      SafeToSpendLine(
        kind: SafeToSpendLineKind.savings,
        label: '',
        amount: Money(-savings.cents),
      ),
      const SafeToSpendLine(
        kind: SafeToSpendLineKind.spentCard,
        label: '',
        amount: Money(-420_000),
      ),
      const SafeToSpendLine(
        kind: SafeToSpendLineKind.spentAccount,
        label: '',
        amount: Money(-95_000),
      ),
      SafeToSpendLine(
        kind: SafeToSpendLineKind.bill,
        label: 'Condomínio Jardim',
        amount: const Money(-95_000),
        on: today.addDays(3),
      ),
      SafeToSpendLine(
        kind: SafeToSpendLineKind.subscription,
        label: 'Streaming Plus',
        amount: const Money(-5_590),
        on: today.addDays(4),
      ),
      SafeToSpendLine(
        kind: SafeToSpendLineKind.fixed,
        label: 'Financiamento',
        amount: const Money(-326_300),
        on: until,
      ),
    ];
    final total = lines.fold(const Money(0), (sum, line) => sum + line.amount);
    return SafeToSpend(
      asOf: today,
      basis: SafeToSpendBasis.month,
      cash: const Money(485_000),
      total: total,
      daily: Money(total.cents > 0 ? total.cents ~/ days : 0),
      days: days,
      until: until,
      shortBy: Money(total.cents < 0 ? -total.cents : 0),
      plan: SpendingPlan(
        income: typicalIncome,
        received: const Money(1_500_000),
        savings: savings,
        savingsSet: _savings != null,
        months: 3,
        sources: _sources.length,
      ),
      lines: lines,
    );
  }

  /// No income in sight, so the month end closes the window; the DAS and
  /// what the budgets still allow come off the company cash.
  SafeToSpend _companySafeToSpend(CalendarDate today) {
    final until = _monthEnd(today);
    final days = today.daysUntil(until) + 1;
    const total = Money(1_250_000 - 182_400 - 40_000 - 25_000);
    return SafeToSpend(
      asOf: today,
      cash: const Money(1_250_000),
      total: total,
      daily: Money(total.cents ~/ days),
      days: days,
      until: until,
      shortBy: const Money(0),
      lines: [
        SafeToSpendLine(
          kind: SafeToSpendLineKind.bill,
          label: 'DAS',
          amount: const Money(-182_400),
          on: today.addDays(5),
        ),
        const SafeToSpendLine(
          kind: SafeToSpendLineKind.budget,
          label: 'Software',
          amount: Money(-40_000),
        ),
        const SafeToSpendLine(
          kind: SafeToSpendLineKind.budget,
          label: 'Escritório',
          amount: Money(-25_000),
        ),
      ],
    );
  }

  @override
  Future<Result<NetWorth>> netWorth(
    EntityScope scope,
    NetWorthPeriod period,
  ) async {
    await _wait();
    final today = _today;
    final entities = [
      if (scope.includes(EntityKind.personal))
        const EntityNetWorth(kind: EntityKind.personal, current: personal),
      if (scope.includes(EntityKind.company))
        const EntityNetWorth(kind: EntityKind.company, current: company),
    ];
    final current = entities.map((entity) => entity.current).reduce(_plus);
    NetWorthPoint monthEnd(int monthsAgo) {
      final end = DateTime.utc(today.year, today.month - monthsAgo + 1, 0);
      final total = current.total - Money(monthlyGrowth.cents * monthsAgo);
      return NetWorthPoint(
        on: CalendarDate(end.year, end.month, end.day),
        assets: total + current.liabilities,
        liabilities: current.liabilities,
        total: total,
      );
    }

    final series = [
      for (var ago = period.months; ago >= 1; ago--) monthEnd(ago),
      NetWorthPoint(
        on: today,
        assets: current.assets,
        liabilities: current.liabilities,
        total: current.total,
      ),
    ];
    return Ok(
      NetWorth(
        asOf: today,
        current: current,
        fromLastMonth: _change(current.total, monthEnd(1).total),
        fromYearAgo: _change(current.total, monthEnd(12).total),
        entities: entities,
        series: series,
      ),
    );
  }

  static NetWorthComposition _plus(
    NetWorthComposition a,
    NetWorthComposition b,
  ) => NetWorthComposition(
    cash: a.cash + b.cash,
    investments: a.investments + b.investments,
    cardDebt: a.cardDebt + b.cardDebt,
    assets: a.assets + b.assets,
    liabilities: a.liabilities + b.liabilities,
    total: a.total + b.total,
  );

  static NetWorthChange _change(Money current, Money previous) {
    final amount = current - previous;
    return NetWorthChange(
      amount: amount,
      percent: (amount.cents / previous.cents * 1000).round() / 10,
    );
  }
}
