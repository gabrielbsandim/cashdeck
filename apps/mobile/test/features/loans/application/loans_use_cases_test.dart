import 'dart:typed_data';

import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/loans/application/loans_use_cases.dart';
import 'package:cashdeck/features/loans/domain/loan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../loan_builders.dart';

final class MockLoansRepository extends Mock implements LoansRepository;

final _file = LocalFile(name: 'extrato.pdf', bytes: Uint8List(4));

void main() {
  late MockLoansRepository repository;

  setUpAll(() => registerFallbackValue(const Money(0)));

  setUp(() => repository = MockLoansRepository());

  test('each use case forwards to the repository', () async {
    final loan = loanWith();
    when(repository.list).thenAnswer((_) async => Ok([loan]));
    when(() => repository.importStatement(_file))
        .thenAnswer((_) async => Ok(loan));
    when(() => repository.prepayment('loan-1', const Money(1_000_000)))
        .thenAnswer((_) async => const Ok(testPrepayment));
    when(() => repository.delete('loan-1'))
        .thenAnswer((_) async => const Ok(null));

    expect(await ListLoans(repository).call(), Ok([loan]));
    expect(await ImportLoanStatement(repository).call(_file), Ok(loan));
    expect(
      await SimulatePrepayment(repository)
          .call('loan-1', const Money(1_000_000)),
      const Ok(testPrepayment),
    );
    expect(await DeleteLoan(repository).call('loan-1'), const Ok<void>(null));
  });

  test('no prepayment is simulated for nothing', () async {
    expect(
      await SimulatePrepayment(repository).call('loan-1', const Money(0)),
      const Err<Prepayment>(UnexpectedFailure()),
    );
    verifyNever(() => repository.prepayment(any(), any()));
  });
}
