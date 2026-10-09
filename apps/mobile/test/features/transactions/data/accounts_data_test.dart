import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/transactions/application/account_use_cases.dart';
import 'package:cashdeck/features/transactions/data/api_accounts_repository.dart';
import 'package:cashdeck/features/transactions/data/fake_accounts_repository.dart';
import 'package:cashdeck/features/transactions/data/transaction_dtos.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/transactions_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/stub_http_adapter.dart';

const JsonMap _card = {
  'id': 'card',
  'name': 'Cartao Exemplo',
  'entityKind': 'PF',
  'institution': 'Banco Exemplo',
  'type': 'CREDIT_CARD',
  'balance': {'cents': -90000, 'currency': 'BRL'},
  'isReserve': false,
  'openBill': {'cents': 25000, 'currency': 'BRL'},
};

void main() {
  test('a card shows its open bill as owed, other accounts their balance', () {
    final card = accountFromJson(_card);
    final checking = accountFromJson({
      ..._card,
      'type': 'CHECKING',
      'balance': {'cents': 5000, 'currency': 'BRL'},
      'openBill': null,
    });

    expect(card.openBill, const Money(25000));
    expect(card.shownAmount, const Money(-25000));
    expect(checking.openBill, isNull);
    expect(checking.shownAmount, const Money(5000));
  });

  test('a renamed account keeps everything but the name', () {
    final card = accountFromJson(_card);
    final renamed = card.renamed('Viagem');

    expect(renamed.name, 'Viagem');
    expect(renamed.renamed(card.name), card);
  });

  test('renames over the api and answers the account', () async {
    final dio = stubDio(
      (options) => switch ('${options.method} ${options.path}') {
        'PATCH /api/v1/accounts/card' => StubResponse(200, {
          'data': Map.of(_card)..['name'] = 'Viagem',
        }),
        _ => const StubResponse(404),
      },
    );

    final result = await RenameAccount(ApiAccountsRepository(dio))
        .call('card', '  Viagem  ');

    expect((result as Ok<TransactionAccount>).value.name, 'Viagem');
    expect(adapterOf(dio).requests.single.data, {'name': 'Viagem'});
    expect(
      await ApiAccountsRepository(dio).rename('gone', 'Viagem'),
      const Err<TransactionAccount>(NotFoundFailure()),
    );
  });

  test('the fake renames a known account and refuses an unknown one', () async {
    const repository = FakeAccountsRepository(latency: Duration.zero);

    final renamed = await repository.rename('acc-pf-card', 'Viagem');
    expect((renamed as Ok<TransactionAccount>).value.name, 'Viagem');
    expect(renamed.value.owner, EntityKind.personal);
    expect(
      await repository.rename('gone', 'Viagem'),
      const Err<TransactionAccount>(NotFoundFailure()),
    );
  });

  test('the accounts repository follows the backend', () {
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
      fake.read(accountsRepositoryProvider),
      isA<FakeAccountsRepository>(),
    );
    expect(api.read(accountsRepositoryProvider), isA<ApiAccountsRepository>());
    expect(api.read(renameAccountProvider), isA<RenameAccount>());
  });
}
