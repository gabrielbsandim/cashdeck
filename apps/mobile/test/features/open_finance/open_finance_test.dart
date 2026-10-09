import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/bills/presentation/bill_labels.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/open_finance/data/fake_open_finance_repository.dart';
import 'package:cashdeck/features/open_finance/domain/item_lookup.dart';
import 'package:cashdeck/features/open_finance/open_finance_providers.dart';
import 'package:cashdeck/features/open_finance/presentation/connect_by_item_id_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';
import '../../support/pump_app.dart';

final class _FailingImport implements OpenFinanceRepository {
  final _inner = FakeOpenFinanceRepository(latency: Duration.zero);
  bool lookupFails = false;

  @override
  Future<Result<ItemLookup>> lookup(String itemId) async {
    if (lookupFails) return const Err(NetworkFailure());
    return await _inner.lookup(itemId);
  }

  @override
  Future<Result<int>> import(
    String itemId,
    Set<String> accountIds,
    EntityKind owner,
  ) async => const Err(NetworkFailure());

  @override
  Future<Result<int>> sync(String connectionId, {required int days}) async =>
      const Err(NetworkFailure());
}

void main() {
  test('an item id is a UUID in any case, padded or not', () {
    expect(
      isValidItemId(' ${FakeOpenFinanceRepository.foundId.toUpperCase()} '),
      isTrue,
    );
    expect(isValidItemId('a3f9c2e1-58b4-4d7e-9a61'), isFalse);
    expect(isValidItemId('z3f9c2e1-58b4-4d7e-9a61-0c2b7e4f1d93'), isFalse);
  });

  test('lookups and accounts compare by value', () {
    const account = FoundAccount(id: 'a', name: 'Conta', balance: Money(1));
    const found = ItemFound(
      institution: 'Banco Exemplo',
      consentUntil: CalendarDate(2027, 1, 1),
      accounts: [account],
    );

    expect(account.props, ['a', 'Conta', const Money(1)]);
    expect(found.props, hasLength(3));
    expect(const ItemNotFound().props, isEmpty);
    expect(const ItemAlreadyConnected(EntityKind.company).props, [
      EntityKind.company,
    ]);
  });

  test('the fake resolves one item, knows a linked one and imports', () async {
    final repository = FakeOpenFinanceRepository(latency: Duration.zero);

    expect(
      await repository.lookup(FakeOpenFinanceRepository.connectedId),
      const Ok<ItemLookup>(ItemAlreadyConnected(EntityKind.company)),
    );
    expect(
      await repository.lookup('c0000000-0000-4000-8000-000000000000'),
      const Ok<ItemLookup>(ItemNotFound()),
    );
    final found = await repository.lookup(FakeOpenFinanceRepository.foundId);
    expect(
      ((found as Ok<ItemLookup>).value as ItemFound).accounts,
      hasLength(3),
    );
    expect(
      await repository.import(
        FakeOpenFinanceRepository.foundId,
        {},
        EntityKind.personal,
      ),
      const Err<int>(ValidationFailure('accounts')),
    );
    expect(
      await repository.import(FakeOpenFinanceRepository.foundId, {
        'acc-card',
      }, EntityKind.personal),
      const Ok(1),
    );
    expect(
      await repository.lookup(FakeOpenFinanceRepository.foundId),
      const Ok<ItemLookup>(ItemAlreadyConnected(EntityKind.personal)),
    );
    expect(await repository.sync('conn-aurora', days: 90), const Ok(30));
  });

  test('the provider reads the fake', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(openFinanceRepositoryProvider),
      isA<FakeOpenFinanceRepository>(),
    );
  });

  group('the item id screen', () {
    Future<void> type(WidgetTester tester, String value) async {
      await tester.enterText(
        find.descendant(
          of: find.byKey(ConnectByItemIdScreen.fieldKey),
          matching: find.byType(TextField),
        ),
        value,
      );
      await settle(tester);
    }

    testWidgets('finds the accounts and imports the chosen ones', (
      tester,
    ) async {
      final app = await pumpRoute(tester, AppRoutes.connectItemId);
      app.read(entityScopeProvider.notifier).select(EntityScope.company);
      await settle(tester);
      expect(find.text(l10n.itemIdTitle), findsOneWidget);

      await type(tester, '${FakeOpenFinanceRepository.foundId}x');
      expect(find.text(l10n.itemIdInvalid), findsOneWidget);

      await type(tester, FakeOpenFinanceRepository.foundId);
      expect(
        find.text(l10n.itemFoundLine('Banco Aurora', '03/04/2027')),
        findsOneWidget,
      );
      expect(find.text(l10n.itemImportButton(3)), findsOneWidget);

      await tester.tap(
        find.byKey(ConnectByItemIdScreen.accountKey('acc-card')),
      );
      await settle(tester);
      expect(find.text(l10n.itemImportButton(2)), findsOneWidget);
      await tester.tap(
        find.byKey(ConnectByItemIdScreen.accountKey('acc-card')),
      );
      await settle(tester);
      expect(find.text(l10n.itemImportButton(3)), findsOneWidget);

      await tester.tap(find.byKey(ConnectByItemIdScreen.importKey));
      await settle(tester);
      expect(find.text(l10n.itemImportedToast(3)), findsOneWidget);

      await type(tester, '');
      await type(tester, FakeOpenFinanceRepository.foundId);
      expect(
        find.text(
          l10n.itemAlreadyConnected(entityKindLabel(l10n, EntityKind.company)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an unknown item is said so', (tester) async {
      await pumpRoute(tester, AppRoutes.connectItemId);

      await type(tester, 'c0000000-0000-4000-8000-000000000000');

      expect(find.text(l10n.itemNotFound), findsOneWidget);
    });

    testWidgets('a failed lookup or import is reported', (tester) async {
      final repository = _FailingImport()..lookupFails = true;
      await pumpRoute(
        tester,
        AppRoutes.connectItemId,
        overrides: [
          openFinanceRepositoryProvider.overrideWithValue(repository),
        ],
      );

      await type(tester, FakeOpenFinanceRepository.foundId);
      expect(find.text(l10n.itemNotFound), findsOneWidget);

      repository.lookupFails = false;
      await type(tester, '');
      await type(tester, FakeOpenFinanceRepository.foundId);
      await tester.tap(find.byKey(ConnectByItemIdScreen.importKey));
      await settle(tester);
      expect(find.text(l10n.errorNetwork), findsOneWidget);
    });

    testWidgets('the help sheet explains where the id lives', (tester) async {
      await pumpRoute(tester, AppRoutes.connectItemId);

      await tester.tap(find.byKey(ConnectByItemIdScreen.helpKey));
      await settle(tester);
      expect(find.text(l10n.itemIdHelpTitle), findsOneWidget);
      expect(find.text(l10n.itemHelpStep4), findsOneWidget);

      await tester.tap(find.byKey(ItemIdHelpSheet.openPanelKey));
      await settle(tester);
      expect(find.text(l10n.openPanelToast), findsOneWidget);
      await waitForToast(tester);

      await tester.tap(find.byKey(ItemIdHelpSheet.doneKey));
      await settle(tester);
      expect(find.byType(ItemIdHelpSheet), findsNothing);
    });
  });
}
