import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/outlook/domain/net_worth.dart';
import 'package:cashdeck/features/outlook/domain/outlook_repository.dart';
import 'package:cashdeck/features/outlook/domain/safe_to_spend.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/builders.dart';

final class MockOutlookRepository extends Mock implements OutlookRepository;

MockOutlookRepository outlookRepository() {
  registerFallbackValue(EntityScope.personal);
  registerFallbackValue(NetWorthPeriod.twelveMonths);
  return MockOutlookRepository();
}

/// Short by R$ 120 before the month ends, with no income in sight.
final SafeToSpend shortSafeToSpend = SafeToSpend(
  asOf: testToday,
  cash: const Money(30_000),
  total: const Money(-12_000),
  daily: const Money(0),
  days: 24,
  until: const CalendarDate(2026, 10, 31),
  shortBy: const Money(12_000),
  lines: [
    SafeToSpendLine(
      kind: SafeToSpendLineKind.bill,
      label: '',
      amount: const Money(-42_000),
      on: testToday.addDays(2),
    ),
  ],
);

const NetWorthComposition emptyComposition = NetWorthComposition(
  cash: Money(0),
  investments: Money(0),
  cardDebt: Money(0),
  assets: Money(0),
  liabilities: Money(0),
  total: Money(0),
);

NetWorth netWorthOf({
  NetWorthComposition current = emptyComposition,
  NetWorthChange fromLastMonth = const NetWorthChange(amount: Money(0)),
  List<EntityNetWorth> entities = const [],
  List<NetWorthPoint> series = const [],
}) => NetWorth(
  asOf: testToday,
  current: current,
  fromLastMonth: fromLastMonth,
  fromYearAgo: const NetWorthChange(amount: Money(0)),
  entities: entities,
  series: series,
);
