import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/investments/data/fake_investments_repository.dart';
import 'package:cashdeck/features/investments/domain/investments.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';

Future<Investments> _load(EntityScope scope) async {
  final repository = FakeInvestmentsRepository(
    FixedClock(testNow),
    latency: Duration.zero,
  );
  return ((await repository.investments(scope)) as Ok<Investments>).value;
}

void main() {
  test('splits fictional positions by entity and adds them up', () async {
    final personal = await _load(EntityScope.personal);
    final company = await _load(EntityScope.company);
    final both = await _load(EntityScope.consolidated);

    expect(personal.positions, hasLength(5));
    expect(company.positions, hasLength(1));
    expect(both.total, personal.total + company.total);
    expect(personal.institutions.map((group) => group.count), [2, 3]);
    expect(
      personal.positions.first.balance.cents,
      greaterThan(personal.positions.last.balance.cents),
    );
    expect(personal.kinds.first.kind, InvestmentKind.fixedIncome);
  });
}
