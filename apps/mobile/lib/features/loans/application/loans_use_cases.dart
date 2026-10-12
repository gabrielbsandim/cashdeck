import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/loans/domain/loan.dart';

final class ListLoans {
  const new(this._repository);

  final LoansRepository _repository;

  Future<Result<List<Loan>>> call() => _repository.list();
}

final class ImportLoanStatement {
  const new(this._repository);

  final LoansRepository _repository;

  Future<Result<Loan>> call(LocalFile file) =>
      _repository.importStatement(file);
}

/// Only a positive extra payment is simulated.
final class SimulatePrepayment {
  const new(this._repository);

  final LoansRepository _repository;

  Future<Result<Prepayment>> call(String id, Money amount) {
    if (amount.cents <= 0) {
      return Future.value(const Err(UnexpectedFailure()));
    }
    return _repository.prepayment(id, amount);
  }
}

final class DeleteLoan {
  const new(this._repository);

  final LoansRepository _repository;

  Future<Result<void>> call(String id) => _repository.delete(id);
}
