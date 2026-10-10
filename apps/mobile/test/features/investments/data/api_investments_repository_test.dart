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
}
