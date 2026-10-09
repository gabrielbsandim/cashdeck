import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';

void main() {
  test('a transfer with an id opens its transfer', () {
    final transfer = testTransaction(
      kind: TransactionKind.transfer,
      transferId: 'transfer-1',
    );

    expect(transfer.opensTransfer, isTrue);
    expect(
      testTransaction(kind: TransactionKind.transfer).opensTransfer,
      false,
    );
    expect(testTransaction().isUncategorized, isTrue);
    expect(testTransaction(categoryId: 'cat').isUncategorized, isFalse);
    expect(transfer.props, hasLength(15));
  });

  test('a query maps the scope to the entity and knows when it filters', () {
    expect(
      const TransactionQuery(scope: EntityScope.personal).entity,
      EntityKind.personal,
    );
    expect(
      const TransactionQuery(scope: EntityScope.company).entity,
      EntityKind.company,
    );
    expect(
      const TransactionQuery(scope: EntityScope.consolidated).entity,
      isNull,
    );
    expect(
      const TransactionQuery(scope: EntityScope.personal).filtered,
      isFalse,
    );
    for (final query in const [
      TransactionQuery(scope: EntityScope.personal, accountId: 'a'),
      TransactionQuery(scope: EntityScope.personal, categoryId: 'c'),
      TransactionQuery(scope: EntityScope.personal, uncategorized: true),
      TransactionQuery(scope: EntityScope.personal, search: 'x'),
      TransactionQuery(
        scope: EntityScope.personal,
        from: CalendarDate(2026, 10, 1),
      ),
      TransactionQuery(
        scope: EntityScope.personal,
        to: CalendarDate(2026, 10, 1),
      ),
    ]) {
      expect(query.filtered, isTrue);
    }
    expect(
      const TransactionQuery(scope: EntityScope.personal).props,
      hasLength(7),
    );
  });

  test('a query matches the scope, filters and the search text', () {
    final row = testTransaction(
      categoryId: 'cat-food',
      note: 'Jantar de aniversário',
    );
    const personal = TransactionQuery(scope: EntityScope.personal);

    expect(personal.matches(row), isTrue);
    for (final (from, to, kept) in [
      (testToday, testToday, true),
      (testToday.addDays(1), null, false),
      (null, testToday.addDays(-1), false),
    ]) {
      expect(
        TransactionQuery(
          scope: EntityScope.personal,
          from: from,
          to: to,
        ).matches(row),
        kept,
      );
    }
    expect(
      const TransactionQuery(scope: EntityScope.company).matches(row),
      isFalse,
    );
    expect(
      const TransactionQuery(
        scope: EntityScope.personal,
        accountId: 'other',
      ).matches(row),
      isFalse,
    );
    expect(
      const TransactionQuery(
        scope: EntityScope.personal,
        categoryId: 'cat-food',
      ).matches(row),
      isTrue,
    );
    expect(
      const TransactionQuery(
        scope: EntityScope.personal,
        uncategorized: true,
      ).matches(row),
      isFalse,
    );
    expect(
      const TransactionQuery(
        scope: EntityScope.personal,
        search: 'ANIVERS',
      ).matches(row),
      isTrue,
    );
    expect(
      const TransactionQuery(
        scope: EntityScope.personal,
        search: 'mercado',
      ).matches(row),
      isFalse,
    );
  });

  test('groups by day, newest day first', () {
    final older = testTransaction(id: 'a', bookedOn: testToday.addDays(-1));
    final newer = testTransaction(id: 'b');
    final sameDay = testTransaction(id: 'c');

    final days = groupByDay([older, newer, sameDay]);

    expect(days.map((day) => day.day), [testToday, testToday.addDays(-1)]);
    expect(days.first.items, [newer, sameDay]);
    expect(days.first.props, hasLength(2));
  });

  test('value classes compare by value', () {
    const category = Category(id: 'c', name: 'Mercado', key: 'groceries');
    const account = TransactionAccount(
      id: 'a',
      name: 'Conta',
      owner: EntityKind.personal,
      institution: 'Banco',
    );
    const page = TransactionPage(items: [], nextCursor: '10');
    const update = TransactionUpdate.category('c', applyToSimilar: true);
    const note = TransactionUpdate.note('lembrar');
    final result = TransactionUpdateResult(
      transaction: testTransaction(),
      similarUpdated: 2,
    );

    expect(category.props, hasLength(5));
    expect(account.props, hasLength(13));
    expect(page.hasMore, isTrue);
    expect(const TransactionPage(items: []).hasMore, isFalse);
    expect(page.props, hasLength(2));
    expect(update.note, isNull);
    expect(note.categoryId, isNull);
    expect(note.applyToSimilar, isFalse);
    expect(update.props, hasLength(3));
    expect(result.props, hasLength(2));
    const logo = AccountLogo(imageUrl: 'https://cdn.test/logo.png');
    const credit = CreditLine(limit: Money(100), available: Money(40));
    const sync = AccountSync(state: SyncState.updating);
    expect(logo.props, hasLength(2));
    expect(credit.used, const Money(60));
    expect(credit.props, hasLength(6));
    expect(sync.props, hasLength(2));
  });
}
