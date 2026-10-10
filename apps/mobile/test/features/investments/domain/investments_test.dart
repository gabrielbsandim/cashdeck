import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/investments/domain/investments.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

InvestmentPosition _position({Money? profit}) => InvestmentPosition(
  id: 'cdb',
  owner: EntityKind.personal,
  institutionId: 'aurora',
  institution: 'Banco Aurora',
  logo: const AccountLogo(imageUrl: 'https://logo.example/a.svg'),
  name: 'CDB',
  kind: InvestmentKind.fixedIncome,
  balance: const Money(10_000),
  profit: profit,
  rate: const InvestmentRate(percent: 102, index: 'CDI'),
  dueOn: const CalendarDate(2028, 4, 4),
);

Investments _investments({
  Money invested = const Money(10_000),
  List<InvestmentPosition>? positions,
}) => Investments(
  total: const Money(10_500),
  invested: invested,
  profit: const Money(500),
  syncedAt: DateTime.utc(2026, 10, 8),
  institutions: const [
    InstitutionHoldings(
      institutionId: 'aurora',
      institution: 'Banco Aurora',
      total: Money(10_500),
      count: 1,
    ),
  ],
  kinds: const [
    KindHoldings(
      kind: InvestmentKind.fixedIncome,
      total: Money(10_500),
      count: 1,
    ),
  ],
  positions: positions ?? [_position()],
);

void main() {
  test('positions compare by value and know a loss', () {
    expect(_position(), _position());
    expect(_position(profit: const Money(-1)).isLoss, isTrue);
    expect(_position(profit: const Money(1)).isLoss, isFalse);
    expect(_position().isLoss, isFalse);
    expect(
      const InvestmentRate(index: 'IPCA', fixedAnnual: 6.2),
      isNot(const InvestmentRate(index: 'IPCA')),
    );
  });

  test('the summary yields over what was invested', () {
    expect(_investments(), _investments());
    expect(_investments().profitPercent, 5);
    expect(_investments(invested: const Money(0)).profitPercent, isNull);
    expect(_investments().isEmpty, isFalse);
    expect(_investments(positions: const []).isEmpty, isTrue);
  });

  test('the groupings compare by value', () {
    InstitutionHoldings institution(int cents) => InstitutionHoldings(
      institutionId: 'aurora',
      institution: 'Banco Aurora',
      total: Money(cents),
      count: 1,
    );
    KindHoldings kind(int cents) =>
        KindHoldings(kind: InvestmentKind.fund, total: Money(cents), count: 1);

    expect(institution(100), institution(100));
    expect(institution(100), isNot(institution(200)));
    expect(kind(100), kind(100));
    expect(kind(100), isNot(kind(200)));
  });

  test('a performance compares to the CDI and finds a position', () {
    InvestmentPerformance performance({double? percent, double? cdi}) =>
        InvestmentPerformance(
          period: PerformancePeriod.month,
          from: const CalendarDate(2026, 9, 8),
          to: const CalendarDate(2026, 10, 8),
          start: const Money(10_000),
          end: const Money(10_200),
          contributions: const Money(0),
          withdrawals: const Money(0),
          yieldAmount: const Money(200),
          yieldPercent: percent,
          cdiPercent: cdi,
          series: const [
            PerformancePoint(CalendarDate(2026, 10, 8), Money(10_200)),
          ],
          positions: const [
            PositionPerformance(
              id: 'cdb',
              start: Money(10_000),
              end: Money(10_200),
              yieldAmount: Money(200),
              yieldPercent: 2,
            ),
          ],
        );

    expect(performance(percent: 1.12, cdi: 1).ofCdi, 112);
    expect(performance(percent: 1.12).ofCdi, isNull);
    expect(performance(cdi: 1).ofCdi, isNull);
    expect(performance(percent: 1, cdi: 0).ofCdi, isNull);
    expect(performance(), performance());
    expect(performance(percent: 1), isNot(performance(percent: 2)));
    expect(performance().positionOf('cdb')?.yieldPercent, 2);
    expect(performance().positionOf('none'), isNull);
  });

  test('points and position yields compare by value', () {
    PerformancePoint point(int cents) =>
        PerformancePoint(const CalendarDate(2026, 10, 8), Money(cents));
    PositionPerformance own(int cents) => PositionPerformance(
      id: 'cdb',
      start: const Money(0),
      end: Money(cents),
      yieldAmount: Money(cents),
    );

    expect(point(1), point(1));
    expect(point(1), isNot(point(2)));
    expect(own(1), own(1));
    expect(own(1), isNot(own(2)));
  });

  test('movements and a detail compare by value', () {
    InvestmentMovement movement(int cents) => InvestmentMovement(
      id: 'mv',
      kind: InvestmentMovementKind.buy,
      occurredOn: const CalendarDate(2026, 3, 4),
      amount: Money(cents),
      quantity: 10,
      unitPrice: 1,
    );
    InvestmentDetail detail(int cents) => InvestmentDetail(
      position: _position(),
      performance: const InvestmentPerformance(
        period: PerformancePeriod.week,
        from: CalendarDate(2026, 10, 1),
        to: CalendarDate(2026, 10, 8),
        start: Money(0),
        end: Money(0),
        contributions: Money(0),
        withdrawals: Money(0),
        yieldAmount: Money(0),
        series: [],
      ),
      movements: [movement(cents)],
    );

    expect(movement(100), movement(100));
    expect(movement(100), isNot(movement(200)));
    expect(detail(100), detail(100));
    expect(detail(100), isNot(detail(200)));
  });
}
