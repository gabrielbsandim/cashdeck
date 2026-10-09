import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';

/// One page of the transactions [TransactionQuery] asks for, newest first.
final class ListTransactions {
  const new(this._repository);

  final TransactionsRepository _repository;

  Future<Result<TransactionPage>> call(
    TransactionQuery query, {
    String? cursor,
  }) => _repository.list(query, cursor: cursor);
}

final class UpdateTransaction {
  const new(this._repository);

  final TransactionsRepository _repository;

  Future<Result<TransactionUpdateResult>> call(
    String id,
    TransactionUpdate update,
  ) => _repository.update(id, update);
}

/// The accounts of [EntityScope], by name, for the account filter.
final class ListTransactionAccounts {
  const new(this._repository);

  final TransactionsRepository _repository;

  Future<Result<List<TransactionAccount>>> call(EntityScope scope) async {
    final result = await _repository.accounts();
    return switch (result) {
      Ok(:final value) => Ok(
        value.where((account) => scope.includes(account.owner)).toList()
          ..sort((a, b) => a.name.compareTo(b.name)),
      ),
      Err(:final failure) => Err(failure),
    };
  }
}

/// The categories a transaction can take, by name.
final class ListCategories {
  const new(this._repository);

  final CategoriesRepository _repository;

  Future<Result<List<Category>>> call() async {
    final result = await _repository.list();
    return switch (result) {
      Ok(:final value) => Ok(
        [...value]..sort((a, b) => a.name.compareTo(b.name)),
      ),
      Err(:final failure) => Err(failure),
    };
  }
}
