import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/home_widget/domain/home_widget_publisher.dart';
import 'package:cashdeck/features/home_widget/domain/widget_snapshot.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:cashdeck/features/outlook/domain/safe_to_spend.dart';

import '../../support/builders.dart';

/// Records what the app hands the widget instead of reaching the platform.
final class FakeHomeWidgetPublisher implements HomeWidgetPublisher {
  final List<WidgetSnapshot> published = [];
  int cleared = 0;
  int enabled = 0;

  WidgetSnapshot? get last => published.lastOrNull;

  @override
  Future<void> publish(WidgetSnapshot snapshot) async =>
      published.add(snapshot);

  @override
  Future<void> clear() async => cleared++;

  @override
  Future<void> enableBackgroundRefresh() async => enabled++;
}

SafeToSpend safeToSpendOf({
  Money daily = const Money(8_500),
  Money shortBy = const Money(0),
}) => SafeToSpend(
  asOf: testToday,
  cash: const Money(300_000),
  total: const Money(195_500),
  daily: daily,
  days: 23,
  until: const CalendarDate(2026, 10, 31),
  shortBy: shortBy,
);

const _span = DateSpan(CalendarDate(2026, 10, 1), CalendarDate(2026, 10, 31));

InsightsOverview overviewWith(CardsSummary? cards) => InsightsOverview(
  period: InsightPeriod.month,
  range: _span,
  previousRange: _span,
  spend: const SpendSummary(
    total: Money(0),
    previous: Money(0),
    series: [],
    previousSeries: [],
    topMerchants: [],
  ),
  categoryTotal: const Money(0),
  categories: const [],
  flow: const CashFlow(income: Money(0), expenses: Money(0), result: Money(0)),
  cards: cards,
  billsDue: const BillsDue(days: 7, total: Money(0), count: 0),
);
