import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transaction_labels.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';
import '../../../support/pump_app.dart';

void main() {
  const market = Category(id: 'cat-1', name: 'Mercado Exemplo');
  final categorized = testTransaction(categoryId: 'cat-1');

  test('an account name carries its holder when it has one', () {
    const account = TransactionAccount(
      id: 'acc-1',
      name: 'Banco Exemplo',
      owner: EntityKind.personal,
      institution: 'Banco Exemplo',
    );

    expect(accountName(account), 'Banco Exemplo');
    expect(accountName(account.heldBy('Ana')), 'Banco Exemplo · Ana');
  });

  test('a categorized transaction shows nothing while categories load', () {
    expect(transactionCategoryLabel(l10n, categorized, null), isEmpty);
  });

  test('names the category once categories load', () {
    expect(
      transactionCategoryLabel(l10n, categorized, const [market]),
      'Mercado Exemplo',
    );
  });

  test('flags a category that is gone only after loading', () {
    expect(
      transactionCategoryLabel(l10n, categorized, const []),
      l10n.transactionCategoryUnknown,
    );
  });

  test('an uncategorized transaction says so even while loading', () {
    expect(
      transactionCategoryLabel(l10n, testTransaction(), null),
      l10n.transactionUncategorized,
    );
  });
}
