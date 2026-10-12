import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/outlook/domain/net_worth.dart';
import 'package:cashdeck/features/outlook/domain/safe_to_spend.dart';
import 'package:flutter_test/flutter_test.dart';

const _zero = NetWorthComposition(
  cash: Money(0),
  investments: Money(0),
  cardDebt: Money(0),
  assets: Money(0),
  liabilities: Money(0),
  total: Money(0),
);

const _day = CalendarDate(2026, 10, 8);

NetWorth _worth({
  NetWorthComposition current = _zero,
  List<NetWorthPoint> series = const [],
}) => NetWorth(
  asOf: _day,
  current: current,
  fromLastMonth: const NetWorthChange(amount: Money(0)),
  fromYearAgo: const NetWorthChange(amount: Money(0)),
  series: series,
);

void main() {
  test('safe to spend is short only while something is missing', () {
    const free = SafeToSpend(
      asOf: _day,
      cash: Money(100),
      total: Money(100),
      daily: Money(10),
      days: 10,
      until: _day,
      shortBy: Money(0),
    );
    const short = SafeToSpend(
      asOf: _day,
      cash: Money(100),
      total: Money(-50),
      daily: Money(0),
      days: 10,
      until: _day,
      shortBy: Money(50),
      income: ExpectedIncome(on: _day, amount: Money(1_000)),
      lines: [
        SafeToSpendLine(
          kind: SafeToSpendLineKind.bill,
          label: 'Water',
          amount: Money(-150),
          on: _day,
        ),
      ],
    );

    expect(free.isShort, isFalse);
    expect(short.isShort, isTrue);
    expect(free, isNot(short));
    expect(short.lines.single, short.lines.single);
    expect(short.income?.props, [_day, const Money(1_000)]);
  });

  test('net worth is empty only with nothing now and nothing before', () {
    const point = NetWorthPoint(
      on: _day,
      assets: Money(500),
      liabilities: Money(0),
      total: Money(500),
    );

    expect(_worth().isEmpty, isTrue);
    expect(_worth(series: const [point]).isEmpty, isFalse);
    expect(
      _worth(current: _zero.copyWithLiabilities(const Money(10))).isEmpty,
      isFalse,
    );
    expect(NetWorthPeriod.sixMonths.months, 6);
    expect(NetWorthPeriod.twelveMonths.months, 12);
    expect(const NetWorthChange(amount: Money(0)).direction, 0);
    expect(
      const EntityNetWorth(kind: EntityKind.company, current: _zero).props,
      [EntityKind.company, _zero],
    );
    expect(_worth(series: const [point]), _worth(series: const [point]));
  });

  test('each value lists every field it compares by', () {
    const line = SafeToSpendLine(
      kind: SafeToSpendLineKind.card,
      label: 'Card',
      amount: Money(-10),
    );
    const point = NetWorthPoint(
      on: _day,
      assets: Money(3),
      liabilities: Money(1),
      total: Money(2),
    );
    const change = NetWorthChange(amount: Money(5), percent: 1.5);

    expect(line.props, [
      SafeToSpendLineKind.card,
      'Card',
      const Money(-10),
      null,
    ]);
    expect(point.props, [_day, const Money(3), const Money(1), const Money(2)]);
    expect(change.props, [const Money(5), 1.5]);
    expect(_zero.props, List.filled(6, const Money(0)));
  });
}

extension on NetWorthComposition {
  NetWorthComposition copyWithLiabilities(Money liabilities) =>
      NetWorthComposition(
        cash: cash,
        investments: investments,
        cardDebt: liabilities,
        assets: assets,
        liabilities: liabilities,
        total: Money(-liabilities.cents),
      );
}
