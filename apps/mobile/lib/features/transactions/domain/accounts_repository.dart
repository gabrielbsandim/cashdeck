import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';

abstract interface class AccountsRepository {
  /// Gives [id] a name of the user's own, which a bank sync never overwrites.
  Future<Result<TransactionAccount>> rename(String id, String name);
}
