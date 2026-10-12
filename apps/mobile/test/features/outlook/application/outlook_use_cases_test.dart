import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/outlook/application/outlook_use_cases.dart';
import 'package:cashdeck/features/outlook/domain/net_worth.dart';
import 'package:cashdeck/features/outlook/domain/safe_to_spend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../outlook_support.dart';

void main() {
  test('safe to spend asks the repository', () async {
    final repository = outlookRepository();
    final answer = Ok(shortSafeToSpend);
    when(repository.safeToSpend).thenAnswer((_) async => answer);

    expect(await LoadSafeToSpend(repository)(), answer);
  });

  test('net worth forwards the scope and the window', () async {
    final repository = outlookRepository();
    const failure = Err<NetWorth>(NetworkFailure());
    when(
      () => repository.netWorth(EntityScope.company, NetWorthPeriod.sixMonths),
    ).thenAnswer((_) async => failure);

    expect(
      await LoadNetWorth(repository)(
        EntityScope.company,
        NetWorthPeriod.sixMonths,
      ),
      failure,
    );
  });

  test('a failure passes through untouched', () async {
    final repository = outlookRepository();
    const failure = Err<SafeToSpend>(NetworkFailure());
    when(repository.safeToSpend).thenAnswer((_) async => failure);

    expect(await LoadSafeToSpend(repository)(), failure);
  });
}
