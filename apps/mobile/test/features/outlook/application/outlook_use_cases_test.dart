import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
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

    expect(await LoadSafeToSpend(repository)(EntityKind.personal), answer);
  });

  test('safe to spend names the company when asked for it', () async {
    final repository = outlookRepository();
    final answer = Ok(shortSafeToSpend);
    when(() => repository.safeToSpend(entity: EntityKind.company))
        .thenAnswer((_) async => answer);

    expect(await LoadSafeToSpend(repository)(EntityKind.company), answer);
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

    expect(await LoadSafeToSpend(repository)(EntityKind.personal), failure);
  });

  test('the savings target goes to the repository as it is', () async {
    final repository = outlookRepository();
    when(() => repository.setSavingsTarget(any()))
        .thenAnswer((_) async => const Ok(null));

    expect(
      await SetSavingsTarget(repository)(const Money(300_000)),
      const Ok<void>(null),
    );
    verify(() => repository.setSavingsTarget(const Money(300_000))).called(1);
  });

  test('the income sources go to the repository as they are', () async {
    final repository = outlookRepository();
    const source = IncomeSource(taxId: '11222333000181', name: 'Cliente');
    when(repository.incomeSources).thenAnswer((_) async => const Ok([]));
    when(() => repository.setIncomeSources(any()))
        .thenAnswer((_) async => const Ok(null));

    expect(
      await LoadIncomeSources(repository)(),
      const Ok<List<IncomeSourceCandidate>>([]),
    );
    expect(
      await SetIncomeSources(repository)(const [source]),
      const Ok<void>(null),
    );
    verify(() => repository.setIncomeSources(const [source])).called(1);
  });
}
