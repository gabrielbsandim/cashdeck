import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/transactions/domain/accounts_repository.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';

final class RenameAccount {
  const new(this._repository);

  final AccountsRepository _repository;

  Future<Result<TransactionAccount>> call(String id, String name) =>
      _repository.rename(id, name.trim());
}

final class SetAccountHolder {
  const new(this._repository);

  final AccountsRepository _repository;

  /// A blank holder clears it.
  Future<Result<TransactionAccount>> call(String id, String? holder) {
    final trimmed = holder?.trim() ?? '';
    return _repository.setHolder(id, trimmed.isEmpty ? null : trimmed);
  }
}
