import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/entities/presentation/entity_switcher.dart';
import 'package:cashdeck/features/home/presentation/balances_screen.dart';
import 'package:cashdeck/features/home/presentation/home_sections.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/transactions_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_harness.dart';
import '../../../support/pump_app.dart';

final class _Accounts implements TransactionsRepository {
  new(this.result);

  Result<List<TransactionAccount>> result;

  @override
  Future<Result<List<TransactionAccount>>> accounts() async => result;

  @override
  Future<Result<TransactionPage>> list(
    TransactionQuery query, {
    String? cursor,
  }) async => const Ok(TransactionPage(items: []));

  @override
  Future<Result<TransactionUpdateResult>> update(
    String id,
    TransactionUpdate update,
  ) async => const Err(NetworkFailure());
}

const _checking = TransactionAccount(
  id: 'checking',
  name: 'Corrente Exemplo',
  owner: EntityKind.personal,
  institution: 'Banco Exemplo',
  type: AccountType.checking,
  balance: Money(30_000),
);
const _wallet = TransactionAccount(
  id: 'wallet',
  name: 'Carteira Exemplo',
  owner: EntityKind.personal,
  institution: 'Fintech Exemplo',
  type: AccountType.wallet,
  balance: Money(10_000),
);
const _reserve = TransactionAccount(
  id: 'reserve',
  name: 'Reserva Exemplo',
  owner: EntityKind.personal,
  institution: 'Banco Exemplo',
  type: AccountType.savings,
  balance: Money(90_000),
  isReserve: true,
);
const _card = TransactionAccount(
  id: 'card',
  name: 'Cartão Exemplo',
  owner: EntityKind.personal,
  institution: 'Banco Exemplo',
  type: AccountType.creditCard,
  balance: Money(-5_000),
);

void main() {
  testWidgets('the home balance opens the balance of each account', (
    tester,
  ) async {
    final app = await pumpRoute(tester, AppRoutes.home);

    await tester.tap(find.byKey(BalanceHeader.openKey));
    await settle(tester);

    expect(app.location, AppRoutes.balances);
    expect(find.text(l10n.balancesTitle), findsOneWidget);
    expect(find.byKey(BalancesScreen.rowKey('acc-pf-checking')), findsOne);
    expect(find.byKey(BalancesScreen.rowKey('acc-pf-card')), findsOne);
    expect(find.byKey(BalancesScreen.rowKey('acc-pj-checking')), findsNothing);
  });

  testWidgets('splits the available share from the reserve and the cards', (
    tester,
  ) async {
    final app = await pumpRoute(
      tester,
      AppRoutes.balances,
      overrides: [
        transactionsRepositoryProvider.overrideWithValue(
          _Accounts(const Ok([_card, _wallet, _reserve, _checking])),
        ),
      ],
    );

    expect(find.text(l10n.balancesInAccounts(2)), findsOneWidget);
    expect(find.text(l10n.balancesReserve), findsOneWidget);
    expect(find.text(l10n.balancesOther), findsOneWidget);
    expect(
      find.text(
        'Banco Exemplo · ${l10n.accountTypeChecking} · '
        '${l10n.balancesShare(75)}',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Banco Exemplo · ${l10n.accountTypeSavings}'),
      findsOneWidget,
    );

    app.read(entityScopeProvider.notifier).select(EntityScope.consolidated);
    await settle(tester);
    expect(find.byType(EntityKindBadge), findsNWidgets(4));
  });

  testWidgets('shows the empty and the error states', (tester) async {
    final repository = _Accounts(const Ok([]));
    final app = await pumpRoute(
      tester,
      AppRoutes.balances,
      overrides: [transactionsRepositoryProvider.overrideWithValue(repository)],
    );
    expect(find.byType(CdEmptyState), findsOneWidget);

    repository.result = const Err(NetworkFailure());
    app.read(entityScopeProvider.notifier).select(EntityScope.company);
    await settle(tester);
    expect(find.byType(CdErrorState), findsOneWidget);
  });

  test('only BRL checking, savings and wallets count as cash', () {
    expect(_checking.isCash, isTrue);
    expect(_card.isCash, isFalse);
    expect(
      const TransactionAccount(
        id: 'usd',
        name: 'Conta global',
        owner: EntityKind.personal,
        institution: 'Banco Exemplo',
        type: AccountType.checking,
        balance: Money(100, currency: 'USD'),
      ).isCash,
      isFalse,
    );
  });
}
