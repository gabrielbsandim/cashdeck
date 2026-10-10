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
}
