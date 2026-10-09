import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/insights/data/fake_insights_repository.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';

T valueOf<T>(Result<T> result) => (result as Ok<T>).value;

void main() {
  late FakeInsightsRepository repository;

  setUp(
    () => repository = FakeInsightsRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    ),
  );

  test('the overview runs from the first of the month to today', () async {
    final overview = valueOf(
      await repository.overview(EntityScope.personal, InsightPeriod.month),
    );
    expect(overview.spend.series, hasLength(testToday.day));
    expect(overview.spend.previousSeries, hasLength(30));
    expect(
      overview.categories
          .map((share) => share.sharePercent)
          .fold(0, (sum, share) => sum + share),
      100,
    );
    expect(overview.cards?.dueOn, testToday.addDays(9));
  });

  test('months end at the chosen one and the company adds transfers', () async {
    final current = valueOf(
      await repository.months(EntityScope.consolidated, count: 6),
    );
    expect(current.months, hasLength(6));
    expect(current.months.last.month, YearMonth.of(testToday));
    expect(current.leftThisMonth, isNotNull);
    expect(current.companyToPersonal, isNotNull);

    final past = valueOf(
      await repository.months(
        EntityScope.personal,
        count: 12,
        month: YearMonth.of(testToday).add(-1),
      ),
    );
    expect(past.months, hasLength(12));
    expect(past.leftThisMonth, isNull);
    expect(past.companyToPersonal, isNull);
  });

  test('installments commit less as plans finish', () async {
    final installments = valueOf(
      await repository.installments(EntityScope.personal),
    );
    final totals = [for (final (_, total) in installments.months) total.cents];
    expect(totals.first, greaterThan(totals.last));
    expect(totals.last, 0);
  });

  test('the personal card has an open bill and six before it', () async {
    final cards = valueOf(await repository.cardBills(EntityScope.personal));
    final bills = cards.single.bills;
    expect(bills.first.state, CardBillState.open);
    expect(bills[1].state, CardBillState.closed);
    expect(bills.last.state, CardBillState.past);
    expect(bills[1].range.from, bills[2].closesOn?.addDays(1));
    expect(valueOf(await repository.cardBills(EntityScope.company)), isEmpty);
  });

  test('a suggestion can be confirmed, dismissed and removed', () async {
    var subscriptions = valueOf(
      await repository.subscriptions(EntityScope.personal),
    );
    expect(subscriptions.suggestions.single.key, 'gym');
    expect(
      subscriptions.items.map((item) => item.thisMonth).toSet(),
      containsAll([
        SubscriptionMonthStatus.paid,
        SubscriptionMonthStatus.upcoming,
      ]),
    );
    expect(
      await repository.confirmSubscription('missing'),
      const Err<String>(NotFoundFailure()),
    );
    expect(await repository.confirmSubscription('gym-charge'), const Ok('gym'));
    subscriptions = valueOf(
      await repository.subscriptions(EntityScope.personal),
    );
    expect(subscriptions.suggestions, isEmpty);
    expect(subscriptions.items.map((item) => item.key), contains('gym'));

    await repository.removeSubscription('gym');
    await repository.dismissSubscription('gym-charge');
    subscriptions = valueOf(
      await repository.subscriptions(EntityScope.personal),
    );
    expect(subscriptions.items.map((item) => item.key), isNot(contains('gym')));
    expect(subscriptions.suggestions, isEmpty);
  });

  test('a charge a few days late reads as late', () async {
    final late = FakeInsightsRepository(
      FixedClock(DateTime.utc(2026, 10, 7, 15)),
      latency: Duration.zero,
    );
    final subscriptions = valueOf(
      await late.subscriptions(EntityScope.personal),
    );
    expect(
      subscriptions.items.map((item) => item.thisMonth),
      contains(SubscriptionMonthStatus.late),
    );
  });
}
