import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/insights/domain/card_timeline.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:flutter_test/flutter_test.dart';

TimelineBill _bill(TimelineBillState state) => TimelineBill(
  dueOn: const CalendarDate(2026, 10, 15),
  total: const Money(10_000),
  state: state,
  range: const DateSpan(CalendarDate(2026, 9, 10), CalendarDate(2026, 10, 9)),
);

CardTimeline _timeline(List<TimelineBill> bills, int? current) => CardTimeline(
  accountId: 'card',
  name: 'Cartão Exemplo',
  owner: EntityKind.personal,
  bills: bills,
  current: current,
);

void main() {
  test('starts on the current bill, kept inside the list', () {
    final bills = [
      _bill(TimelineBillState.past),
      _bill(TimelineBillState.open),
      _bill(TimelineBillState.forecast),
    ];
    expect(_timeline(bills, 1).start, 1);
    expect(_timeline(bills, 7).start, 2);
    expect(_timeline(bills, null).start, 0);
    expect(_timeline(const [], null).start, 0);
    expect(_timeline(bills, 1), _timeline(bills, 1));
    expect(_timeline(bills, 1), isNot(_timeline(bills, 2)));
  });

  test('a forecast bill tells itself apart and labels its installments', () {
    expect(_bill(TimelineBillState.forecast).isForecast, isTrue);
    expect(_bill(TimelineBillState.open).isForecast, isFalse);
    expect(
      _bill(TimelineBillState.open),
      isNot(_bill(TimelineBillState.closed)),
    );
    const installment = PlannedInstallment(
      key: 'plan',
      name: 'Loja Exemplo',
      categoryId: 'shopping',
      number: 4,
      count: 6,
      amount: Money(5_000),
    );
    expect(installment.label, '4/6');
    expect(
      installment,
      isNot(
        const PlannedInstallment(
          key: 'plan',
          name: 'Loja Exemplo',
          number: 5,
          count: 6,
          amount: Money(5_000),
        ),
      ),
    );
  });
}
