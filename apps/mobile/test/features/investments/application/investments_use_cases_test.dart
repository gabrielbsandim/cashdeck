import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/investments/application/investments_use_cases.dart';
import 'package:cashdeck/features/investments/domain/investments.dart';
import 'package:cashdeck/features/investments/domain/investments_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

final class _MockInvestmentsRepository extends Mock
    implements InvestmentsRepository;

void main() {
  test('loading forwards the scope', () async {
    final repository = _MockInvestmentsRepository();
    const failure = Err<Investments>(NetworkFailure());
    when(() => repository.investments(EntityScope.company))
        .thenAnswer((_) async => failure);

    expect(await LoadInvestments(repository)(EntityScope.company), failure);
  });
}
