import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/transactions/domain/accounts_repository.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';

final class RenameAccount {
  const new(this._repository);

  final AccountsRepository _repository;

  Future<Result<TransactionAccount>> call(String id, String name) =>
      _repository.rename(id, name.trim());
}
