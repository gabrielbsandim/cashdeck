import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/entities/presentation/entity_switcher.dart';
import 'package:cashdeck/features/home/presentation/account_rename_sheet.dart';
import 'package:cashdeck/features/home/presentation/balances_screen.dart';
import 'package:cashdeck/features/home/presentation/home_sections.dart';
import 'package:cashdeck/features/open_finance/domain/item_lookup.dart';
import 'package:cashdeck/features/open_finance/open_finance_providers.dart';
import 'package:cashdeck/features/transactions/domain/accounts_repository.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/transactions_providers.dart';
import 'package:flutter/material.dart';
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

final class _Renames implements AccountsRepository {
  new({this.fails = false});

  final bool fails;
  final calls = <(String, String)>[];

  @override
  Future<Result<TransactionAccount>> rename(String id, String name) async {
    calls.add((id, name));
    if (fails) return const Err(NetworkFailure());
    return Ok(_checking.renamed(name));
  }
}

final class _FailingSync implements OpenFinanceRepository {
  @override
  Future<Result<ItemLookup>> lookup(String itemId) async =>
      const Err(NetworkFailure());

  @override
  Future<Result<int>> import(
    String itemId,
    Set<String> accountIds,
    EntityKind owner,
  ) async => const Err(NetworkFailure());

  @override
  Future<Result<int>> sync(String connectionId, {required int days}) async =>
      connectionId == 'conn-stale' ? const Ok(3) : const Err(NetworkFailure());
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

const _billedCard = TransactionAccount(
  id: 'billed',
  name: 'Cartão Faturado',
  owner: EntityKind.personal,
  institution: 'Banco Exemplo',
  type: AccountType.creditCard,
  balance: Money(-90_000),
  openBill: Money(2_000),
);

Finder _nameField() => find.descendant(
  of: find.byKey(AccountRenameSheet.fieldKey),
  matching: find.byType(TextFormField),
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

  testWidgets('a card shows its open bill as owed, not its balance', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      AppRoutes.balances,
      overrides: [
        transactionsRepositoryProvider.overrideWithValue(
          _Accounts(const Ok([_checking, _billedCard, _card])),
        ),
      ],
    );

    expect(
      find.text(
        'Banco Exemplo · ${l10n.accountTypeCreditCard} · '
        '${l10n.balancesOpenBill}',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Banco Exemplo · ${l10n.accountTypeCreditCard} · '
        '${l10n.balancesOutsideTotal}',
      ),
      findsOneWidget,
    );
    final amount = tester.widget<CdAmount>(
      find.descendant(
        of: find.byKey(BalancesScreen.rowKey('billed')),
        matching: find.byType(CdAmount),
      ),
    );
    expect(amount.value, const Money(-2_000));
  });

  testWidgets('tapping a card opens its bills', (tester) async {
    final app = await pumpRoute(
      tester,
      AppRoutes.balances,
      overrides: [
        transactionsRepositoryProvider.overrideWithValue(
          _Accounts(const Ok([_billedCard])),
        ),
      ],
    );

    await tester.tap(find.byKey(BalancesScreen.rowKey('billed')));
    await settle(tester);

    expect(app.location, AppRoutes.cardBills('billed'));
  });

  testWidgets('tapping an account renames it', (tester) async {
    final renames = _Renames();
    await pumpRoute(
      tester,
      AppRoutes.balances,
      overrides: [
        transactionsRepositoryProvider.overrideWithValue(
          _Accounts(const Ok([_checking])),
        ),
        accountsRepositoryProvider.overrideWithValue(renames),
      ],
    );

    await tester.tap(find.byKey(BalancesScreen.rowKey('checking')));
    await settle(tester);
    expect(find.text(l10n.accountRenameTitle), findsOneWidget);
    expect(find.text(l10n.accountRenameHelper), findsOneWidget);
    final save = find.byKey(AccountRenameSheet.saveKey);
    expect(tester.widget<CdButton>(save).onPressed, isNull);

    await tester.enterText(_nameField(), '   ');
    await tester.pump();
    expect(tester.widget<CdButton>(save).onPressed, isNull);

    await tester.enterText(_nameField(), '  Viagem ');
    await tester.pump();
    await tester.tap(save);
    await settle(tester);

    expect(renames.calls, [('checking', 'Viagem')]);
    expect(find.text(l10n.accountRenamed), findsOneWidget);
  });

  testWidgets('a dismissed sheet renames nothing and a failure says why', (
    tester,
  ) async {
    final renames = _Renames(fails: true);
    await pumpRoute(
      tester,
      AppRoutes.balances,
      overrides: [
        transactionsRepositoryProvider.overrideWithValue(
          _Accounts(const Ok([_checking])),
        ),
        accountsRepositoryProvider.overrideWithValue(renames),
      ],
    );

    await tester.tap(find.byKey(BalancesScreen.rowKey('checking')));
    await settle(tester);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(find.text(l10n.accountRenameTitle), findsNothing);
    expect(renames.calls, isEmpty);

    await tester.tap(find.byKey(BalancesScreen.rowKey('checking')));
    await settle(tester);
    await tester.enterText(_nameField(), 'Viagem');
    await tester.pump();
    await tester.tap(find.byKey(AccountRenameSheet.saveKey));
    await settle(tester);

    expect(renames.calls, [('checking', 'Viagem')]);
    expect(find.text(l10n.errorNetwork), findsOneWidget);
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

  testWidgets('syncs a year of each connection and says how many came', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.balances);

    expect(find.text(l10n.syncStateUpdated), findsOneWidget);
    expect(find.text(l10n.syncStateUpdating), findsOneWidget);
    await tester.tap(find.byKey(BalancesScreen.syncKey));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await settle(tester);

    expect(find.text(l10n.balancesSynced(242)), findsOneWidget);
  });

  testWidgets('a failed sync says why and the states read as words', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      AppRoutes.balances,
      overrides: [
        openFinanceRepositoryProvider.overrideWithValue(_FailingSync()),
        transactionsRepositoryProvider.overrideWithValue(
          _Accounts(
            const Ok([
              TransactionAccount(
                id: 'stale',
                name: 'Conta parada',
                owner: EntityKind.personal,
                institution: 'Banco Exemplo',
                type: AccountType.checking,
                balance: Money(1_000),
                connectionId: 'conn-stale',
                sync: AccountSync(state: SyncState.outdated),
              ),
              TransactionAccount(
                id: 'locked',
                name: 'Conta travada',
                owner: EntityKind.personal,
                institution: 'Banco Exemplo',
                type: AccountType.checking,
                balance: Money(2_000),
                connectionId: 'conn-locked',
                sync: AccountSync(state: SyncState.needsAction),
              ),
            ]),
          ),
        ),
      ],
    );

    expect(find.text(l10n.syncStateOutdated), findsOneWidget);
    expect(find.text(l10n.syncStateNeedsAction), findsOneWidget);
    await tester.tap(find.byKey(BalancesScreen.syncKey));
    await settle(tester);
    expect(find.text(l10n.errorNetwork), findsOneWidget);
  });

  testWidgets('connect opens the item id screen', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.balances);
    await tester.tap(find.byKey(BalancesScreen.connectKey));
    await settle(tester);
    expect(app.location, AppRoutes.connectItemId);
  });

  testWidgets('the empty state offers to connect', (tester) async {
    final app = await pumpRoute(
      tester,
      AppRoutes.balances,
      overrides: [
        transactionsRepositoryProvider.overrideWithValue(
          _Accounts(const Ok([])),
        ),
      ],
    );
    expect(find.byKey(BalancesScreen.syncKey), findsNothing);
    await tester.tap(find.text(l10n.balancesConnect));
    await settle(tester);
    expect(app.location, AppRoutes.connectItemId);
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
