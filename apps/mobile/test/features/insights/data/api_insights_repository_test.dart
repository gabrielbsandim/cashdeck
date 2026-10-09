import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/insights/data/api_insights_repository.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/stub_http_adapter.dart';
import '../insight_json.dart';

T valueOf<T>(Result<T> result) => (result as Ok<T>).value;

void main() {
  test('reads the overview with and without cards', () async {
    var withCards = false;
    final dio = stubDio(
      (_) => StubResponse(200, {
        'data': overviewJson(cards: withCards ? fullCards() : null),
      }),
    );
    final repository = ApiInsightsRepository(dio);

    final plain = valueOf(
      await repository.overview(EntityScope.personal, InsightPeriod.month),
    );
    expect(plain.cards, isNull);
    expect(plain.period, InsightPeriod.month);
    expect(plain.spend.topMerchants.single.name, 'Loja');
    expect(plain.categories.single.categoryId, isNull);
    expect(plain.flow.result, const Money(4000));
    expect(plain.billsDue.count, 1);
    expect(plain.range.from, const CalendarDate(2026, 10, 1));
    final request = adapterOf(dio).requests.single;
    expect(request.path, '/api/v1/insights/overview');
    expect(request.queryParameters, {'entity': 'PF', 'period': '1m'});

    withCards = true;
    final full = valueOf(
      await repository.overview(EntityScope.consolidated, InsightPeriod.year),
    );
    expect(full.cards?.usedPercent, 25);
    expect(full.cards?.limit, const Money(100000));
    expect(adapterOf(dio).requests.last.queryParameters, {'period': '1y'});
  });

  test('reads the monthly insights and skips unknown sentences', () async {
    var current = true;
    final dio = stubDio(
      (_) => StubResponse(200, {'data': monthlyJson(current: current)}),
    );
    final repository = ApiInsightsRepository(dio);

    final insights = valueOf(
      await repository.months(
        EntityScope.company,
        count: 12,
        month: const YearMonth(2026, 10),
      ),
    );
    expect(insights.month, const YearMonth(2026, 10));
    expect(insights.months.single.result, const Money(60));
    expect(insights.savings.trend.single, (const YearMonth(2026, 10), 60));
    expect(insights.rose.single.categoryId, 'food');
    expect(insights.fell.single.delta, const Money(-500));
    expect(insights.fixedCost.sharePercent, 60);
    expect(insights.leftThisMonth?.left, const Money(70));
    expect(insights.companyToPersonal?.taxes, const Money(50));
    expect(insights.insights.map((insight) => insight.runtimeType), [
      CategoryAboveAverage,
      InstallmentsCommitted,
      SavingsRateChanged,
      SubscriptionPriceUp,
    ]);
    expect(adapterOf(dio).requests.single.queryParameters, {
      'entity': 'PJ',
      'months': 12,
      'month': '2026-10',
    });

    current = false;
    final past = valueOf(
      await repository.months(EntityScope.consolidated, count: 6),
    );
    expect(past.leftThisMonth, isNull);
    expect(past.companyToPersonal, isNull);
    expect(adapterOf(dio).requests.last.queryParameters, {'months': 6});
  });

  test('reads installments and subscriptions', () async {
    final dio = stubDio(
      (options) => StubResponse(200, {
        'data': options.path.endsWith('installments')
            ? installmentsJson()
            : subscriptionsJson(),
      }),
    );
    final repository = ApiInsightsRepository(dio);

    final installments = valueOf(
      await repository.installments(EntityScope.personal),
    );
    final plan = installments.plans.single;
    expect(plan.left, 2);
    expect(plan.owner, EntityKind.personal);
    expect(plan.finalMonth, const YearMonth(2026, 12));
    expect(installments.months.single.$2, const Money(5000));

    final subscriptions = valueOf(
      await repository.subscriptions(EntityScope.personal),
    );
    expect(subscriptions.items.single.isSuggestion, isFalse);
    expect(subscriptions.items.single.previousAmount, const Money(3000));
    expect(subscriptions.suggestions.single.isSuggestion, isTrue);
    expect(subscriptions.suggestions.single.previousAmount, isNull);
    expect(subscriptions.items.single.thisMonth, SubscriptionMonthStatus.paid);
  });

  test('reads the bills of each card', () async {
    final dio = stubDio(
      (options) => StubResponse(200, {
        'data': options.path.endsWith('card-bills') ? cardBillsJson() : null,
      }),
    );

    final cards = valueOf(
      await ApiInsightsRepository(dio).cardBills(EntityScope.personal),
    );

    final card = cards.single;
    expect(card.suffix, '4821');
    expect(card.owner, EntityKind.personal);
    expect(card.bills.first.closesOn, isNull);
    expect(card.bills.last.minimum, const Money(3_000));
    expect(card.bills.last.state, CardBillState.closed);
    expect(card.bills.last.range.from, const CalendarDate(2026, 9, 8));
  });

  test('decides and removes subscriptions', () async {
    final dio = stubDio(
      (options) => switch (options.path) {
        '/api/v1/subscriptions' => const StubResponse(201, {
          'data': {'id': 'r1'},
        }),
        '/api/v1/subscriptions/dismiss' => const StubResponse(200, {
          'data': {'id': 'r2'},
        }),
        _ => const StubResponse(404, {
          'error': {'code': 'NOT_FOUND', 'message': 'Not found'},
        }),
      },
    );
    final repository = ApiInsightsRepository(dio);

    expect(await repository.confirmSubscription('t1'), const Ok('r1'));
    expect(await repository.dismissSubscription('t2'), isA<Ok<void>>());
    final removed = await repository.removeSubscription('a b');
    expect(removed, isA<Err<void>>());
    expect((removed as Err<void>).failure, isA<NotFoundFailure>());
    final requests = adapterOf(dio).requests;
    expect(requests.first.data, {'transactionId': 't1'});
    expect(requests.last.path, '/api/v1/subscriptions/a%20b');
    expect(requests.last.method, 'DELETE');
  });
}
