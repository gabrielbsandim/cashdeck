import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/investments/data/api_investments_repository.dart';
import 'package:cashdeck/features/investments/domain/investments.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/stub_http_adapter.dart';
import '../investment_json.dart';

T valueOf<T>(Result<T> result) => (result as Ok<T>).value;

void main() {
  test('reads the totals, the groupings and every position field', () async {
    final dio = stubDio((_) => StubResponse(200, {'data': investmentsJson()}));
    final investments = valueOf(
      await ApiInvestmentsRepository(dio).investments(EntityScope.personal),
    );

    expect(investments.total, const Money(105_000));
    expect(investments.syncedAt, DateTime.utc(2026, 10, 8, 12));
    expect(investments.institutions.single.logo?.color, '#FF0000');
    expect(investments.kinds.single.kind, InvestmentKind.fixedIncome);
    final position = investments.positions.single;
    expect(position.owner, EntityKind.personal);
    expect(position.rate, const InvestmentRate(percent: 102, index: 'CDI'));
    expect(position.quantity, 1.5);
    expect(position.profitPercent, 5);
    expect(position.dueOn, const CalendarDate(2028, 4, 4));
    expect(position.pending, isFalse);
    final request = adapterOf(dio).requests.single;
    expect(request.path, '/api/v1/investments');
    expect(request.queryParameters, {'entity': 'PF'});
  });

  test('reads a bare position and sends no entity when consolidated', () async {
    final dio = stubDio(
      (_) => StubResponse(200, {'data': investmentsJson(full: false)}),
    );
    final investments = valueOf(
      await ApiInvestmentsRepository(dio).investments(EntityScope.consolidated),
    );

    final position = investments.positions.single;
    expect(investments.syncedAt, isNull);
    expect(investments.institutions.single.logo, isNull);
    expect(position.kind, InvestmentKind.other);
    expect(position.pending, isTrue);
    expect(position.logo, isNull);
    expect(position.invested, isNull);
    expect(position.profit, isNull);
    expect(position.rate, isNull);
    expect(position.dueOn, isNull);
    expect(adapterOf(dio).requests.single.queryParameters, isEmpty);
  });

  test('turns a malformed number and a server error into failures', () async {
    final malformed = stubDio(
      (_) => StubResponse(200, {
        'data': {
          ...investmentsJson(),
          'positions': [
            {...positionJson(), 'quantity': 'many'},
          ],
        },
      }),
    );
    expect(
      await ApiInvestmentsRepository(malformed)
          .investments(EntityScope.company),
      isA<Err<Investments>>(),
    );

    final down = stubDio((_) => const StubResponse(500, {'error': 'down'}));
    final result = await ApiInvestmentsRepository(down)
        .investments(EntityScope.company);
    expect((result as Err<Investments>).failure, isA<AppFailure>());
  });

  test('reads a performance with its series and positions', () async {
    final dio = stubDio((_) => StubResponse(200, {'data': performanceJson()}));
    final performance = valueOf(
      await ApiInvestmentsRepository(dio)
          .performance(EntityScope.personal, PerformancePeriod.month),
    );

    expect(performance.period, PerformancePeriod.month);
    expect(performance.from, const CalendarDate(2026, 9, 8));
    expect(performance.to, const CalendarDate(2026, 10, 8));
    expect(performance.start, const Money(100_000));
    expect(performance.end, const Money(105_000));
    expect(performance.contributions, const Money(2_000));
    expect(performance.withdrawals, const Money(500));
    expect(performance.yieldAmount, const Money(3_500));
    expect(performance.yieldPercent, 3.47);
    expect(performance.cdiPercent, 0.82);
    expect(performance.estimated, isTrue);
    expect(performance.series.last.value, const Money(105_000));
    expect(performance.positionOf('cdb')?.yieldPercent, 3.47);
    final request = adapterOf(dio).requests.single;
    expect(request.path, '/api/v1/investments/performance');
    expect(request.queryParameters, {'period': 'MONTH', 'entity': 'PF'});
  });

  test('reads a bare performance and sends each period', () async {
    final dio = stubDio(
      (_) => StubResponse(200, {'data': performanceJson(full: false)}),
    );
    final repository = ApiInvestmentsRepository(dio);
    final performance = valueOf(
      await repository.performance(
        EntityScope.consolidated,
        PerformancePeriod.year,
      ),
    );
    await repository.performance(
      EntityScope.consolidated,
      PerformancePeriod.week,
    );

    expect(performance.period, PerformancePeriod.year);
    expect(performance.yieldPercent, isNull);
    expect(performance.cdiPercent, isNull);
    expect(performance.estimated, isFalse);
    expect(performance.positions, isEmpty);
    expect(adapterOf(dio).requests.map((request) => request.queryParameters), [
      {'period': 'YEAR'},
      {'period': 'WEEK'},
    ]);
  });

  test('reads a position with its performance and movements', () async {
    final dio = stubDio((_) => StubResponse(200, {'data': detailJson()}));
    final detail = valueOf(
      await ApiInvestmentsRepository(dio)
          .position('cdb/1', PerformancePeriod.month),
    );

    expect(detail.position.id, 'cdb');
    expect(detail.performance.yieldAmount, const Money(3_500));
    final [buy, tax] = detail.movements;
    expect(buy.kind, InvestmentMovementKind.buy);
    expect(buy.occurredOn, const CalendarDate(2026, 3, 4));
    expect(buy.amount, const Money(100_000));
    expect(buy.quantity, 10000);
    expect(buy.unitPrice, 1);
    expect(tax.kind, InvestmentMovementKind.tax);
    expect(tax.quantity, isNull);
    final request = adapterOf(dio).requests.single;
    expect(request.path, '/api/v1/investments/cdb%2F1');
    expect(request.queryParameters, {'period': 'MONTH'});
  });

  test(
    'turns a malformed performance and a missing position into failures',
    () async {
      final malformed = stubDio(
        (_) => StubResponse(200, {
          'data': {...performanceJson(), 'yieldPercent': 'high'},
        }),
      );
      expect(
        await ApiInvestmentsRepository(malformed)
            .performance(EntityScope.personal, PerformancePeriod.week),
        isA<Err<InvestmentPerformance>>(),
      );

      final missing = stubDio(
        (_) => const StubResponse(404, {'error': 'gone'}),
      );
      final result = await ApiInvestmentsRepository(missing)
          .position('nope', PerformancePeriod.year);
      expect((result as Err<InvestmentDetail>).failure, isA<NotFoundFailure>());
    },
  );
}
