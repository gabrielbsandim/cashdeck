import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/transactions/application/transactions_use_cases.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/builders.dart';
import '../../../support/mocks.dart';

void main() {
  late MockTransactionsRepository transactions;
  late MockCategoriesRepository categories;

  const query = TransactionQuery(scope: EntityScope.personal);
  const update = TransactionUpdate.note('nota');
  const zeta = TransactionAccount(
    id: 'z',
    name: 'Zeta',
    owner: EntityKind.personal,
    institution: 'Banco',
  );
  const alpha = TransactionAccount(
    id: 'a',
    name: 'Alpha',
    owner: EntityKind.personal,
    institution: 'Banco',
  );
  const company = TransactionAccount(
    id: 'c',
    name: 'Empresa',
    owner: EntityKind.company,
    institution: 'Banco',
  );

  setUpAll(() {
    registerFallbackValue(query);
    registerFallbackValue(update);
  });

  setUp(() {
    transactions = MockTransactionsRepository();
    categories = MockCategoriesRepository();
  });

  test('lists a page and updates through the repository', () async {
    final page = TransactionPage(items: [testTransaction()]);
    final result = TransactionUpdateResult(
      transaction: testTransaction(),
      similarUpdated: 0,
    );
    when(() => transactions.list(query, cursor: '15'))
        .thenAnswer((_) async => Ok(page));
    when(() => transactions.update('tx-1', update))
        .thenAnswer((_) async => Ok(result));

    expect(
      await ListTransactions(transactions).call(query, cursor: '15'),
      Ok(page),
    );
    expect(
      await UpdateTransaction(transactions).call('tx-1', update),
      Ok(result),
    );
  });

  test('accounts are scoped and sorted by name', () async {
    when(transactions.accounts)
        .thenAnswer((_) async => const Ok([zeta, company, alpha]));

    final result = await ListTransactionAccounts(transactions)
        .call(EntityScope.personal);

    expect(result, const Ok([alpha, zeta]));
  });

  test('an accounts failure passes through', () async {
    when(transactions.accounts)
        .thenAnswer((_) async => const Err(NetworkFailure()));

    expect(
      await ListTransactionAccounts(transactions).call(EntityScope.company),
      const Err<List<TransactionAccount>>(NetworkFailure()),
    );
  });

  test('categories are sorted by name and failures pass through', () async {
    const b = Category(id: 'b', name: 'B');
    const a = Category(id: 'a', name: 'A');
    when(categories.list).thenAnswer((_) async => const Ok([b, a]));

    expect(await ListCategories(categories).call(), const Ok([a, b]));

    when(categories.list).thenAnswer((_) async => const Err(ServerFailure()));
    expect(
      await ListCategories(categories).call(),
      const Err<List<Category>>(ServerFailure()),
    );
  });
}
