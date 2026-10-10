import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/investments/data/fake_investments_repository.dart';
import 'package:cashdeck/features/investments/domain/investments.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';

final _repository = FakeInvestmentsRepository(
  FixedClock(testNow),
  latency: Duration.zero,
);

T _value<T>(Result<T> result) => (result as Ok<T>).value;

Future<Investments> _load(EntityScope scope) =>
    _repository.investments(scope).then(_value);

Future<InvestmentPerformance> _performance(
  EntityScope scope,
  PerformancePeriod period,
) => _repository.performance(scope, period).then(_value);

void main() {
  test('splits fictional positions by entity and adds them up', () async {
    final personal = await _load(EntityScope.personal);
    final company = await _load(EntityScope.company);
    final both = await _load(EntityScope.consolidated);

    expect(personal.positions, hasLength(5));
    expect(company.positions, hasLength(1));
    expect(both.total, personal.total + company.total);
    expect(personal.institutions.map((group) => group.count), [2, 3]);
    expect(
      personal.positions.first.balance.cents,
      greaterThan(personal.positions.last.balance.cents),
    );
    expect(personal.kinds.first.kind, InvestmentKind.fixedIncome);
  });

  test('a performance closes on today and adds up its flows', () async {
    final today = CalendarDate.brazilToday(testNow);
    for (final (period, days, points) in [
      (PerformancePeriod.week, 7, 8),
      (PerformancePeriod.month, 30, 31),
      (PerformancePeriod.year, 365, 54),
    ]) {
      final performance = await _performance(EntityScope.personal, period);
      final holdings = await _load(EntityScope.personal);

      expect(performance.period, period);
      expect(performance.to, today);
      expect(performance.from, today.addDays(-days));
      expect(performance.end, holdings.total);
      expect(performance.series, hasLength(points));
      expect(performance.series.first.day, performance.from);
      expect(performance.series.last.value, performance.end);
      expect(
        performance.yieldAmount,
        performance.end -
            performance.start -
            performance.contributions +
            performance.withdrawals,
      );
      expect(performance.positions, hasLength(5));
      expect(
        performance.positions.first.yieldAmount.cents,
        greaterThanOrEqualTo(performance.positions.last.yieldAmount.cents),
      );
      expect(performance.estimated, period != PerformancePeriod.week);
      expect(performance.cdiPercent, greaterThan(0));
    }
  });

  test('a month holds the new treasury buy and the company sale', () async {
    final personal = await _performance(
      EntityScope.personal,
      PerformancePeriod.month,
    );
    final company = await _performance(
      EntityScope.company,
      PerformancePeriod.month,
    );

    expect(personal.contributions, const Money(450_000));
    expect(personal.withdrawals, const Money(0));
    expect(personal.yieldPercent, isNotNull);
    expect(company.withdrawals, const Money(100_000));
    expect(company.contributions, const Money(0));
  });

  test('a position comes with its movements and no breakdown', () async {
    final detail = _value(
      await _repository.position('tesouro-ipca', PerformancePeriod.year),
    );

    expect(detail.position.name, 'Tesouro IPCA+ 2035');
    expect(detail.performance.positions, isEmpty);
    expect(detail.performance.end, detail.position.balance);
    expect(detail.movements.map((movement) => movement.kind), [
      InvestmentMovementKind.buy,
      InvestmentMovementKind.income,
      InvestmentMovementKind.buy,
    ]);
    final today = CalendarDate.brazilToday(testNow);
    expect(detail.movements.map((movement) => movement.occurredOn), [
      today.addDays(-20),
      today.addDays(-60),
      today.addDays(-510),
    ]);
  });

  test('a bought this week position starts from nothing', () async {
    final detail = _value(
      await _repository.position('fii', PerformancePeriod.week),
    );

    expect(detail.performance.start, const Money(0));
    expect(detail.performance.contributions, const Money(250_000));
    expect(detail.performance.yieldAmount, const Money(0));
    expect(detail.performance.yieldPercent, 0);
  });

  test('an unknown position is not found', () async {
    expect(
      await _repository.position('nope', PerformancePeriod.month),
      const Err<InvestmentDetail>(NotFoundFailure()),
    );
  });
}
