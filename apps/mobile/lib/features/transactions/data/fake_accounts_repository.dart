import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/transactions/data/fake_transactions_repository.dart';
import 'package:cashdeck/features/transactions/domain/accounts_repository.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';

/// Answers with the renamed fictional account; the list keeps its names.
final class FakeAccountsRepository implements AccountsRepository {
  const new({this.latency = const Duration(milliseconds: 250)});

  final Duration latency;

  @override
  Future<Result<TransactionAccount>> rename(String id, String name) async {
    await Future<void>.delayed(latency);
    for (final account in FakeTransactionsRepository.accountsList) {
      if (account.id == id) return Ok(account.renamed(name));
    }
    return const Err(NotFoundFailure());
  }
}
