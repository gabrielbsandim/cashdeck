import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/outlook/domain/net_worth.dart';
import 'package:cashdeck/features/outlook/domain/outlook_repository.dart';
import 'package:cashdeck/features/outlook/domain/safe_to_spend.dart';

/// Fictional bills, a card and a salary twelve days out, and a net worth
/// that grew steadily every month.
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

  @override
  Future<Result<SafeToSpend>> safeToSpend({
    EntityKind entity = EntityKind.personal,
  }) async {
    await _wait();
    final today = _today;
    if (entity == EntityKind.company) return Ok(_companySafeToSpend(today));
    return Ok(
      SafeToSpend(
        asOf: today,
        cash: const Money(485_000),
        total: const Money(251_370),
        daily: const Money(20_947),
        days: 12,
        until: today.addDays(12),
        shortBy: const Money(0),
        income: ExpectedIncome(
          on: today.addDays(12),
          amount: const Money(820_000),
        ),
        lines: [
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
            kind: SafeToSpendLineKind.bill,
            label: 'Energia Azul',
            amount: const Money(-18_740),
            on: today.addDays(6),
          ),
          SafeToSpendLine(
            kind: SafeToSpendLineKind.fixed,
            label: 'Diarista',
            amount: const Money(-32_000),
            on: today.addDays(8),
          ),
          SafeToSpendLine(
            kind: SafeToSpendLineKind.card,
            label: 'Cartão Aurora',
            amount: const Money(-142_300),
            on: today.addDays(10),
          ),
          const SafeToSpendLine(
            kind: SafeToSpendLineKind.reserve,
            label: '',
            amount: Money(60_000),
          ),
        ],
      ),
    );
  }

  /// No income in sight, so the month end closes the window; the DAS and
  /// what the budgets still allow come off the company cash.
  SafeToSpend _companySafeToSpend(CalendarDate today) {
    final monthEnd = DateTime.utc(today.year, today.month + 1, 0);
    final until = CalendarDate(monthEnd.year, monthEnd.month, monthEnd.day);
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
