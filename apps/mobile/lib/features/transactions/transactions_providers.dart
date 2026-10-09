import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/transactions/application/transactions_use_cases.dart';
import 'package:cashdeck/features/transactions/data/api_transactions_repository.dart';
import 'package:cashdeck/features/transactions/data/api_transfers_repository.dart';
import 'package:cashdeck/features/transactions/data/fake_transactions_repository.dart';
import 'package:cashdeck/features/transactions/data/fake_transfers_repository.dart';
import 'package:cashdeck/features/transactions/domain/internal_transfer.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final transfersRepositoryProvider = Provider<TransfersRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeTransfersRepository(ref.watch(clockProvider)),
    Backend.api => ApiTransfersRepository(ref.watch(dioProvider)),
  };
});

final transactionsRepositoryProvider = Provider<TransactionsRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeTransactionsRepository(ref.watch(clockProvider)),
    Backend.api => ApiTransactionsRepository(ref.watch(dioProvider)),
  };
});

final categoriesRepositoryProvider = Provider<CategoriesRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => const FakeCategoriesRepository(),
    Backend.api => ApiCategoriesRepository(ref.watch(dioProvider)),
  };
});

final listTransactionsProvider = Provider<ListTransactions>(
  (ref) => ListTransactions(ref.watch(transactionsRepositoryProvider)),
);

final updateTransactionProvider = Provider<UpdateTransaction>(
  (ref) => UpdateTransaction(ref.watch(transactionsRepositoryProvider)),
);

final listTransactionAccountsProvider = Provider<ListTransactionAccounts>(
  (ref) => ListTransactionAccounts(ref.watch(transactionsRepositoryProvider)),
);

final listCategoriesProvider = Provider<ListCategories>(
  (ref) => ListCategories(ref.watch(categoriesRepositoryProvider)),
);
