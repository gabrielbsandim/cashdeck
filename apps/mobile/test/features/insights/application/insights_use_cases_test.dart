import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/insights/application/insights_use_cases.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/mocks.dart';

void main() {
  late MockInsightsRepository repository;

  setUp(() => repository = MockInsightsRepository());

  test('loading forwards the scope and the period', () async {
    const failure = Err<InsightsOverview>(NetworkFailure());
    when(() => repository.overview(EntityScope.personal, InsightPeriod.week))
        .thenAnswer((_) async => failure);
    when(() => repository.installments(EntityScope.company))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    when(() => repository.subscriptions(EntityScope.consolidated))
        .thenAnswer((_) async => const Err(NetworkFailure()));

    expect(
      await LoadInsightsOverview(repository)(
        EntityScope.personal,
        InsightPeriod.week,
      ),
      failure,
    );
    expect(
      await LoadInstallments(repository)(EntityScope.company),
      isA<Err<Installments>>(),
    );
    expect(
      await LoadSubscriptions(repository)(EntityScope.consolidated),
      isA<Err<Subscriptions>>(),
    );
  });

  test('monthly insights take six or twelve months', () async {
    const month = YearMonth(2026, 9);
    when(() => repository.months(EntityScope.personal, count: 12, month: month))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    final load = LoadMonthlyInsights(repository);

    expect(
      await load(EntityScope.personal, count: 12, month: month),
      isA<Err<MonthlyInsights>>(),
    );
    expect(() => load(EntityScope.personal, count: 7), throwsArgumentError);
  });

  test('a decision confirms or dismisses, and removal forwards', () async {
    when(() => repository.confirmSubscription('t1'))
        .thenAnswer((_) async => const Ok('r1'));
    when(() => repository.confirmSubscription('t2'))
        .thenAnswer((_) async => const Err(NotFoundFailure()));
    when(() => repository.dismissSubscription('t3'))
        .thenAnswer((_) async => const Ok(null));
    when(() => repository.removeSubscription('r1'))
        .thenAnswer((_) async => const Ok(null));
    final decide = DecideSubscription(repository);

    expect(
      await decide('t1', SubscriptionDecision.confirm),
      const Ok<void>(null),
    );
    expect(
      await decide('t2', SubscriptionDecision.confirm),
      const Err<void>(NotFoundFailure()),
    );
    expect(
      await decide('t3', SubscriptionDecision.dismiss),
      const Ok<void>(null),
    );
    expect(await RemoveSubscription(repository)('r1'), const Ok<void>(null));
    expect(const Money(1), const Money(1));
  });
}
