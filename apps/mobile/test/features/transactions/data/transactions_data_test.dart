import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/transactions/data/api_transactions_repository.dart';
import 'package:cashdeck/features/transactions/data/fake_transactions_repository.dart';
import 'package:cashdeck/features/transactions/data/transaction_dtos.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/transactions_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';
import '../../../support/stub_http_adapter.dart';

T _ok<T>(Result<T> result) => (result as Ok<T>).value;

void main() {
  group('dtos', () {
    test('read the merchant and the installment of a card charge', () {
      final charge = transactionFromJson({
        ...transactionJson(),
        'merchant': 'Loja Exemplo',
        'installment': {'number': 3, 'count': 10, 'purchaseOn': '2026-08-02'},
      });
      expect(charge.displayName, 'Loja Exemplo');
      expect(charge.installment?.label, '3/10');
      expect(
        charge.installment,
        const TransactionInstallment(
          number: 3,
          count: 10,
          purchaseOn: CalendarDate(2026, 8, 2),
        ),
      );
      final plain = transactionFromJson(transactionJson());
      expect(plain.displayName, 'Padaria Exemplo');
      expect(plain.installment, isNull);
    });

    test('read a card with its logo, limit and sync status', () {
      JsonMap card(String status) => {
        'id': 'card',
        'name': 'Aurora Platinum',
        'entityKind': 'PF',
        'institution': 'Banco Aurora',
        'type': 'CREDIT_CARD',
        'balance': {'cents': -25000, 'currency': 'BRL'},
        'isReserve': false,
        'numberSuffix': '4821',
        'logo': {'imageUrl': 'https://cdn.test/aurora.png', 'color': '#3263C3'},
        'credit': {
          'limit': {'cents': 100000, 'currency': 'BRL'},
          'available': {'cents': 75000, 'currency': 'BRL'},
          'usedPercent': 25,
          'closesOn': '2026-10-20',
          'dueOn': '2026-10-27',
          'brand': 'VISA',
        },
        'sync': {'status': status, 'lastSyncAt': '2026-10-08T12:00:00Z'},
      };
      final account = accountFromJson(card('UPDATED'));
      expect(account.numberSuffix, '4821');
      expect(account.logo?.color, '#3263C3');
      expect(account.credit?.used, const Money(25000));
      expect(account.credit?.dueOn, const CalendarDate(2026, 10, 27));
      expect(account.sync?.state, SyncState.updated);
      expect(
        accountFromJson(card('LOGIN_ERROR')).sync?.state,
        SyncState.needsAction,
      );
      expect(accountFromJson(card('PAUSED')).sync?.state, SyncState.outdated);
      expect(
        accountFromJson(card('UPDATING')),
        isNot(accountFromJson(card('UPDATED'))),
      );
      final manual = accountFromJson({
        ...card('UPDATED'),
        'logo': null,
        'credit': null,
        'sync': null,
      });
      expect(manual.logo, isNull);
      expect(manual.credit, isNull);
      expect(manual.sync, isNull);
    });

    test('read a transaction with its category source', () {
      final transaction = transactionFromJson(transactionJson());

      expect(transaction.amount, const Money(-4_590));
      expect(transaction.owner, EntityKind.personal);
      expect(transaction.kind, TransactionKind.expense);
      expect(transaction.categorizedBy, CategorySource.ai);
      expect(transaction.categoryConfidence, 0.8);

      final bare = transactionFromJson(
        transactionJson(categorizedBy: null, confidence: null),
      );
      expect(bare.categorizedBy, isNull);
      expect(bare.categoryConfidence, isNull);
      expect(
        transactionFromJson(transactionJson(confidence: 1)).categoryConfidence,
        1.0,
      );
    });

    test('a wrong shape is a format error', () {
      expect(
        () => transactionFromJson(transactionJson(confidence: 'high')),
        throwsFormatException,
      );
      expect(
        () => transactionFromJson(transactionJson(categorizedBy: 'ROBOT')),
        throwsFormatException,
      );
    });

    test('the query string leaves empty filters out', () {
      expect(
        transactionQueryToJson(
          const TransactionQuery(scope: EntityScope.consolidated),
        ),
        {'limit': 30},
      );
      expect(
        transactionQueryToJson(
          const TransactionQuery(
            scope: EntityScope.company,
            accountId: 'a',
            categoryId: 'c',
            uncategorized: true,
            search: ' padaria ',
            from: CalendarDate(2026, 9, 8),
            to: CalendarDate(2026, 10, 7),
          ),
          cursor: '30',
        ),
        {
          'limit': 30,
          'entity': 'PJ',
          'accountId': 'a',
          'categoryId': 'c',
          'uncategorized': 'true',
          'search': 'padaria',
          'from': '2026-09-08',
          'to': '2026-10-07',
          'cursor': '30',
        },
      );
    });

    test('an update sends only what changes, a blank note as null', () {
      expect(
        transactionUpdateToJson(
          const TransactionUpdate.category('c', applyToSimilar: true),
        ),
        {'categoryId': 'c', 'applyToSimilar': true},
      );
      expect(transactionUpdateToJson(const TransactionUpdate.note('  ')), {
        'note': null,
      });
      expect(
        transactionUpdateToJson(const TransactionUpdate.note(' Lembrar ')),
        {'note': 'Lembrar'},
      );
    });
  });

  group('api', () {
    test('lists a page, updates and reads accounts and categories', () async {
      final dio = stubDio(
        (options) => switch ('${options.method} ${options.path}') {
          'GET /api/v1/transactions' => StubResponse(200, {
            'data': [transactionJson()],
            'nextCursor': '30',
          }),
          'PATCH /api/v1/transactions/tx-1' => StubResponse(200, {
            'data': {'transaction': transactionJson(), 'similarUpdated': 3},
          }),
          'GET /api/v1/accounts' => const StubResponse(200, {
            'data': [
              {
                'id': 'acc-1',
                'name': 'Conta',
                'entityKind': 'PJ',
                'institution': 'Banco',
                'type': 'CREDIT_CARD',
                'balance': {'cents': -1200, 'currency': 'BRL'},
                'isReserve': false,
              },
            ],
          }),
          'GET /api/v1/categories' => const StubResponse(200, {
            'data': [
              {
                'id': 'c',
                'key': 'groceries',
                'name': 'Groceries',
                'icon': null,
                'parentId': null,
              },
            ],
          }),
          _ => const StubResponse(404),
        },
      );
      final repository = ApiTransactionsRepository(dio);

      final page = _ok(
        await repository.list(
          const TransactionQuery(scope: EntityScope.personal),
          cursor: '15',
        ),
      );
      final update = _ok(
        await repository.update(
          'tx-1',
          const TransactionUpdate.category('c', applyToSimilar: false),
        ),
      );
      final accounts = _ok(await repository.accounts());
      final categories = _ok(await ApiCategoriesRepository(dio).list());

      expect(page.items.single.id, 'tx-1');
      expect(page.nextCursor, '30');
      expect(adapterOf(dio).requests.first.queryParameters, {
        'limit': 30,
        'entity': 'PF',
        'cursor': '15',
      });
      expect(adapterOf(dio).requests[1].data, {
        'categoryId': 'c',
        'applyToSimilar': false,
      });
      expect(update.similarUpdated, 3);
      expect(accounts.single.owner, EntityKind.company);
      expect(accounts.single.type, AccountType.creditCard);
      expect(accounts.single.balance, const Money(-1200));
      expect(accounts.single.isCash, isFalse);
      expect(categories.single.key, 'groceries');
    });

    test('a failed request is a failure', () async {
      final dio = stubDio((_) => const StubResponse(500));

      expect(
        await ApiTransactionsRepository(dio).accounts(),
        const Err<List<TransactionAccount>>(ServerFailure()),
      );
      expect(
        await ApiCategoriesRepository(dio).list(),
        const Err<List<Category>>(ServerFailure()),
      );
    });
  });

  group('fake', () {
    FakeTransactionsRepository repository() =>
        FakeTransactionsRepository(FixedClock(testNow), latency: Duration.zero);

    test('pages through the scope with a cursor', () async {
      final fake = repository();
      const query = TransactionQuery(scope: EntityScope.consolidated);

      final first = _ok(await fake.list(query));
      final second = _ok(await fake.list(query, cursor: first.nextCursor));

      expect(first.items, hasLength(15));
      expect(second.items, hasLength(15));
      expect(second.nextCursor, isNull);
      expect(first.items.first.bookedOn, testToday);
      expect(
        first.items.where((row) => row.kind == TransactionKind.transfer),
        isNotEmpty,
      );
    });

    test('honors the filters and the search', () async {
      final fake = repository();

      final company = _ok(
        await fake.list(const TransactionQuery(scope: EntityScope.company)),
      );
      final uncategorized = _ok(
        await fake.list(
          const TransactionQuery(
            scope: EntityScope.personal,
            uncategorized: true,
          ),
        ),
      );
      final search = _ok(
        await fake.list(
          const TransactionQuery(
            scope: EntityScope.personal,
            search: 'mercado',
          ),
        ),
      );

      expect(
        company.items.every((row) => row.owner == EntityKind.company),
        isTrue,
      );
      expect(uncategorized.items.every((row) => row.isUncategorized), isTrue);
      expect(search.items, hasLength(3));
    });

    test('a category goes to similar ones the user did not set', () async {
      final fake = repository();

      final result = _ok(
        await fake.update(
          'tx-17',
          const TransactionUpdate.category(
            'cat-transport',
            applyToSimilar: true,
          ),
        ),
      );
      final noted = _ok(
        await fake.update('tx-17', const TransactionUpdate.note(' Táxi ')),
      );
      final cleared = _ok(
        await fake.update('tx-17', const TransactionUpdate.note('')),
      );

      expect(result.transaction.categoryId, 'cat-transport');
      expect(result.transaction.categorizedBy, CategorySource.user);
      expect(result.similarUpdated, 2);
      expect(noted.transaction.note, 'Táxi');
      expect(noted.transaction.categoryId, 'cat-transport');
      expect(cleared.transaction.note, isNull);
      expect(
        await fake.update('none', const TransactionUpdate.note('x')),
        const Err<TransactionUpdateResult>(NotFoundFailure()),
      );
    });

    test('only this one keeps the similar transactions as they were', () async {
      final result = _ok(
        await repository().update(
          'tx-17',
          const TransactionUpdate.category('cat-fuel', applyToSimilar: false),
        ),
      );

      expect(result.similarUpdated, 0);
    });

    test('lists accounts and categories', () async {
      final accounts = _ok(await repository().accounts());
      final categories = _ok(
        await const FakeCategoriesRepository(latency: Duration.zero).list(),
      );

      expect(accounts, hasLength(3));
      expect(categories, hasLength(21));
      expect(categories.last.key, isNull);
    });
  });

  test('providers pick fake or api by the backend', () {
    final fake = ProviderContainer();
    addTearDown(fake.dispose);
    final api = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(backend: Backend.api, apiBaseUrl: 'https://api.test'),
        ),
      ],
    );
    addTearDown(api.dispose);

    expect(
      fake.read(transactionsRepositoryProvider),
      isA<FakeTransactionsRepository>(),
    );
    expect(
      fake.read(categoriesRepositoryProvider),
      isA<FakeCategoriesRepository>(),
    );
    expect(
      api.read(transactionsRepositoryProvider),
      isA<ApiTransactionsRepository>(),
    );
    expect(
      api.read(categoriesRepositoryProvider),
      isA<ApiCategoriesRepository>(),
    );
    expect(fake.read(listTransactionsProvider), isNotNull);
  });
}
