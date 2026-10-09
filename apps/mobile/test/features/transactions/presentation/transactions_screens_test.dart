import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/widgets/insights/cd_institution_logo.dart';
import 'package:cashdeck/core/widgets/money/cd_transaction_row.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/alerts/presentation/alerts_controller.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_switcher.dart';
import 'package:cashdeck/features/transactions/data/fake_transactions_repository.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transaction_detail_screen.dart';
import 'package:cashdeck/features/transactions/presentation/transaction_labels.dart';
import 'package:cashdeck/features/transactions/presentation/transaction_pickers.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_controller.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_screen.dart';
import 'package:cashdeck/features/transactions/transactions_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_harness.dart';
import '../../../support/builders.dart';
import '../../../support/pump_app.dart';

/// The fake, failing on demand and empty when asked.
final class _Scripted implements TransactionsRepository {
  final _inner = FakeTransactionsRepository(
    FixedClock(testNow),
    latency: Duration.zero,
  );
  bool failList = false;
  bool failMore = false;
  bool failUpdate = false;
  bool empty = false;
  int lists = 0;

  @override
  Future<Result<TransactionPage>> list(
    TransactionQuery query, {
    String? cursor,
  }) async {
    lists++;
    if (failList || (failMore && cursor != null)) {
      return const Err(NetworkFailure());
    }
    if (empty) return const Ok(TransactionPage(items: []));
    return await _inner.list(query, cursor: cursor);
  }

  @override
  Future<Result<TransactionUpdateResult>> update(
    String id,
    TransactionUpdate update,
  ) async {
    if (failUpdate) return const Err(NetworkFailure());
    return await _inner.update(id, update);
  }

  @override
  Future<Result<List<TransactionAccount>>> accounts() => _inner.accounts();
}

Future<void> _consolidated(WidgetTester tester) async {
  await pickScope(tester, EntityScope.consolidated);
  await settle(tester);
}

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(TransactionsScreen.searchKey), text);
  await tester.pump(TransactionsScreen.searchDelay);
  await settle(tester);
}

/// Taps both ends on the calendar; October, the current month, comes last.
/// The test font is wider than a real one, so the picker header needs room.
Future<void> _pickDays(WidgetTester tester, int from, int to) async {
  tester.view.physicalSize = const Size(2400, 6000);
  await tester.pump();
  await tester.tap(find.byKey(TransactionsScreen.daysFilterKey));
  await settle(tester);
  expect(find.text(l10n.transactionsDaysHelp), findsOneWidget);
  final picker = find.byType(DateRangePickerDialog);
  final material = MaterialLocalizations.of(tester.element(picker));
  await tester.tap(find.text('$from').last);
  await tester.pump();
  await tester.tap(find.text('$to').last);
  await tester.pump();
  await tester.tap(find.text(material.saveButtonLabel));
  await settle(tester);
}

void main() {
  testWidgets('groups by day and shows the category or its absence', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.transactions);

    expect(find.text(l10n.relativeTodayTitle), findsOneWidget);
    expect(find.text(l10n.relativeYesterdayTitle), findsOneWidget);
    expect(find.text('Padaria Trigo Bom'), findsWidgets);
    expect(find.text('Lumen'), findsOneWidget);
    expect(find.textContaining(' · 2/3'), findsOneWidget);
    expect(find.byType(CdInstitutionLogo), findsWidgets);
    expect(find.text(l10n.categoryRestaurants), findsWidgets);
    expect(find.text(l10n.transactionUncategorized), findsWidgets);
    expect(find.text('Cliente Atlas Software'), findsNothing);
  });

  testWidgets('consolidated shows both entities and pages with the cursor', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.transactions);
    await _consolidated(tester);

    expect(find.text('Cliente Atlas Software'), findsOneWidget);
    expect(find.byType(EntityKindBadge), findsWidgets);
    expect(find.text('Aplicação Tesouro'), findsNothing);

    await tester.ensureVisible(find.byKey(TransactionsScreen.loadMoreKey));
    await tester.tap(find.byKey(TransactionsScreen.loadMoreKey));
    await settle(tester);

    await tester.scrollUntilVisible(
      find.byKey(TransactionsScreen.rowKey('tx-30')),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(TransactionsScreen.rowKey('tx-30')), findsOneWidget);
    expect(find.byKey(TransactionsScreen.loadMoreKey), findsNothing);
  });

  testWidgets('a transfer row opens the transfer', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.transactions);

    await tester.tap(find.byKey(TransactionsScreen.rowKey('tx-5')));
    await settle(tester);

    expect(app.location, AppRoutes.transfer('transfer-prolabore'));
  });

  testWidgets('searches after a pause and offers to clear filters', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.transactions);

    await _search(tester, 'mercado');
    expect(find.text('Mercado Bom Preço'), findsNWidgets(3));
    expect(find.text('Padaria Trigo Bom'), findsNothing);

    await _search(tester, 'nada parecido');
    expect(find.text(l10n.transactionsNoMatchTitle), findsOneWidget);

    await tester.tap(find.text(l10n.transactionsClearFilters));
    await settle(tester);
    expect(find.text('Padaria Trigo Bom'), findsWidgets);
  });

  testWidgets('filters by account and by category', (tester) async {
    await pumpRoute(tester, AppRoutes.transactions);

    await tester.tap(find.byKey(TransactionsScreen.accountFilterKey));
    await settle(tester);
    expect(find.text(l10n.accountTypeCreditCard), findsOneWidget);
    expect(find.text(l10n.accountTypeChecking), findsOneWidget);
    await tester.tap(find.byKey(TransactionsScreen.optionKey('acc-pf-card')));
    await settle(tester);
    expect(find.text('Energia Lumina'), findsNothing);
    expect(find.text('Cartão Horizonte ••9021'), findsOneWidget);

    await tester.tap(find.byKey(TransactionsScreen.accountFilterKey));
    await settle(tester);
    await tester.tap(find.byKey(TransactionsScreen.allOptionKey));
    await settle(tester);
    expect(find.text('Energia Lumina'), findsOneWidget);

    await tester.tap(find.byKey(TransactionsScreen.categoryFilterKey));
    await settle(tester);
    await tester.tap(find.byKey(TransactionsScreen.uncategorizedOptionKey));
    await settle(tester);
    expect(find.text('Energia Lumina'), findsNothing);
    expect(find.text('Posto Estrada Azul'), findsOneWidget);

    await tester.tap(find.byKey(TransactionsScreen.categoryFilterKey));
    await settle(tester);
    await tester.tap(find.byKey(TransactionsScreen.optionKey('cat-utilities')));
    await settle(tester);
    expect(find.text('Energia Lumina'), findsOneWidget);
    expect(find.text('Posto Estrada Azul'), findsNothing);

    await tester.tap(find.byKey(TransactionsScreen.categoryFilterKey));
    await settle(tester);
    await tester.tap(find.byKey(TransactionsScreen.allOptionKey));
    await settle(tester);
    expect(find.text('Posto Estrada Azul'), findsWidgets);
  });

  testWidgets('a new category can go to the similar transactions', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.transactions);

    await tester.tap(find.byKey(TransactionsScreen.rowKey('tx-17')));
    await settle(tester);
    expect(find.text('Mobilidade Rota Certa'), findsOneWidget);
    expect(find.text(l10n.transactionCategoryHint), findsOneWidget);

    await tester.tap(find.byKey(TransactionDetailScreen.categoryKey));
    await settle(tester);
    await tester.tap(
      find.byKey(TransactionDetailScreen.categoryOptionKey('cat-transport')),
    );
    await settle(tester);
    expect(find.text(l10n.applyToSimilarTitle), findsOneWidget);
    await tester.tap(find.byKey(applyToSimilarKey));
    await settle(tester);

    expect(find.text(l10n.transactionCategorySavedSimilar(2)), findsOneWidget);
    expect(find.text(l10n.categorySourceUser), findsOneWidget);
    expect(find.text(l10n.categoryTransport), findsOneWidget);
  });

  testWidgets('only this one, a dismissed question and a note', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.transactions);
    await tester.tap(find.byKey(TransactionsScreen.rowKey('tx-4')));
    await settle(tester);
    expect(find.text(l10n.categorySourceAiConfidence(86)), findsOneWidget);

    await tester.tap(find.byKey(TransactionDetailScreen.categoryKey));
    await settle(tester);
    await tester.tap(
      find.byKey(TransactionDetailScreen.categoryOptionKey('cat-shopping')),
    );
    await settle(tester);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(find.text(l10n.categoryGroceries), findsOneWidget);

    await tester.tap(find.byKey(TransactionDetailScreen.categoryKey));
    await settle(tester);
    await tester.tap(
      find.byKey(TransactionDetailScreen.categoryOptionKey('cat-shopping')),
    );
    await settle(tester);
    await tester.tap(find.byKey(applyToThisOnlyKey));
    await settle(tester);
    expect(find.text(l10n.transactionCategorySaved), findsOneWidget);
    expect(find.text(l10n.categoryShopping), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byKey(TransactionDetailScreen.noteKey),
        matching: find.byType(TextField),
      ),
      'Compra do mês',
    );
    await tester.tap(find.byKey(TransactionDetailScreen.saveNoteKey));
    await settle(tester);
    expect(find.text(l10n.transactionNoteSaved), findsOneWidget);

    app.router.pop();
    await settle(tester);
    expect(find.text(l10n.categoryShopping), findsOneWidget);
  });

  testWidgets('the detail finds a row the list loaded, or says it is gone', (
    tester,
  ) async {
    final app = await pumpRoute(tester, AppRoutes.transaction('tx-1'));
    expect(find.byKey(TransactionDetailScreen.categoryKey), findsOneWidget);

    app.router.go(AppRoutes.transaction('none'));
    await settle(tester);
    expect(find.text(l10n.transactionNotFound), findsOneWidget);
  });

  testWidgets('the detail of a transfer links to it', (tester) async {
    final app = await pumpRoute(
      tester,
      AppRoutes.transaction('tx-5'),
      extra: testTransaction(
        id: 'tx-5',
        accountId: 'acc-pf-checking',
        kind: TransactionKind.transfer,
        transferId: 'transfer-prolabore',
        categorizedBy: CategorySource.rule,
        categoryId: 'cat-gone',
      ),
    );
    expect(find.text(l10n.categorySourceRule), findsOneWidget);
    expect(find.text(l10n.transactionCategoryUnknown), findsOneWidget);
    expect(find.text('Corrente Aurora ••4410'), findsOneWidget);

    await tester.tap(find.byKey(TransactionDetailScreen.transferKey));
    await settle(tester);
    expect(app.location, AppRoutes.transfer('transfer-prolabore'));
  });

  testWidgets('failures show a retry, a toast or an empty list', (
    tester,
  ) async {
    final repository = _Scripted()..failList = true;
    final app = await pumpRoute(
      tester,
      AppRoutes.transactions,
      overrides: [
        transactionsRepositoryProvider.overrideWithValue(repository),
        unreadAlertsProvider.overrideWith((ref) async => 0),
      ],
    );
    expect(find.text(l10n.errorNetwork), findsOneWidget);

    repository
      ..failList = false
      ..failMore = true;
    await tester.tap(find.byKey(CdErrorState.retryKey));
    await settle(tester);
    await _consolidated(tester);
    await tester.ensureVisible(find.byKey(TransactionsScreen.loadMoreKey));
    await tester.tap(find.byKey(TransactionsScreen.loadMoreKey));
    await settle(tester);
    expect(find.text(l10n.errorNetwork), findsOneWidget);

    repository.failUpdate = true;
    await tester.tap(find.byKey(TransactionsScreen.rowKey('tx-1')));
    await settle(tester);
    await tester.tap(find.byKey(TransactionDetailScreen.saveNoteKey));
    await settle(tester);
    expect(find.text(l10n.errorNetwork), findsOneWidget);

    app.router.pop();
    await settle(tester);
    repository.empty = true;
    await pickScope(tester, EntityScope.company);
    await settle(tester);
    expect(find.text(l10n.transactionsEmptyTitle), findsOneWidget);
  });

  testWidgets('a day or a range of days narrows the list until cleared', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.transactions);
    expect(find.byTooltip(l10n.transactionsFilterDays), findsOneWidget);
    expect(find.byKey(TransactionsScreen.daysChipKey), findsNothing);

    await _pickDays(tester, 7, 7);
    expect(find.text('7 de out.'), findsOneWidget);
    expect(find.text(l10n.relativeYesterdayTitle), findsOneWidget);
    expect(find.text(l10n.relativeTodayTitle), findsNothing);
    expect(find.text('Mercado Bom Preço'), findsOneWidget);

    await _search(tester, 'nada parecido');
    expect(find.text(l10n.transactionsNoMatchTitle), findsOneWidget);
    await _search(tester, '');
    expect(find.text('Mercado Bom Preço'), findsOneWidget);

    await _pickDays(tester, 1, 6);
    expect(find.text('1 de out. a 6 de out.'), findsOneWidget);
    expect(find.text(l10n.relativeYesterdayTitle), findsNothing);
    expect(find.byType(CdTransactionRow), findsWidgets);

    expect(find.byTooltip(l10n.transactionsClearDays), findsOneWidget);
    await tester.tap(find.byKey(TransactionsScreen.daysChipKey));
    await settle(tester);
    expect(find.byKey(TransactionsScreen.daysChipKey), findsNothing);
    expect(find.text(l10n.relativeTodayTitle), findsOneWidget);
  });

  testWidgets('clearing the filters drops the days too', (tester) async {
    await pumpRoute(tester, AppRoutes.transactions);
    await _pickDays(tester, 7, 7);
    await _search(tester, 'Padaria');
    expect(find.text(l10n.transactionsNoMatchTitle), findsOneWidget);

    await tester.tap(find.text(l10n.transactionsClearFilters));
    await settle(tester);
    expect(find.byKey(TransactionsScreen.daysChipKey), findsNothing);
    expect(find.text(l10n.relativeTodayTitle), findsOneWidget);
  });

  testWidgets('pulling the list fetches it again', (tester) async {
    final repository = _Scripted();
    await pumpRoute(
      tester,
      AppRoutes.transactions,
      overrides: [transactionsRepositoryProvider.overrideWithValue(repository)],
    );
    final before = repository.lists;

    await tester.fling(
      find.byKey(TransactionsScreen.rowKey('tx-1')),
      const Offset(0, 1500),
      1000,
    );
    await settle(tester);

    expect(repository.lists, before + 1);
    expect(find.byType(RefreshProgressIndicator), findsNothing);
  });

  test(
    'the days filter keeps the other filters and refuses a reversed range',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final subscription = container.listen(
        transactionFiltersProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      final filters = container.read(transactionFiltersProvider.notifier)
        ..selectAccount('acc-pf-card')
        ..selectDays(testToday.addDays(-3), testToday);
      expect(
        container.read(transactionFiltersProvider),
        TransactionFilters(
          accountId: 'acc-pf-card',
          from: testToday.addDays(-3),
          to: testToday,
        ),
      );
      filters
        ..search('pão')
        ..selectCategory('cat-groceries');
      expect(container.read(transactionFiltersProvider).to, testToday);
      expect(
        container
            .read(transactionFiltersProvider)
            .queryFor(EntityScope.personal)
            .filtered,
        isTrue,
      );
      expect(
        () => filters.selectDays(testToday, testToday.addDays(-1)),
        throwsArgumentError,
      );
      filters.clearDays();
      expect(container.read(transactionFiltersProvider).from, isNull);
      expect(container.read(transactionFiltersProvider).search, 'pão');
    },
  );

  test('labels cover every source, kind and day', () {
    const today = testToday;
    expect(
      categorySourceLabel(
        l10n,
        testTransaction(categorizedBy: CategorySource.ai),
      ),
      l10n.categorySourceAi,
    );
    expect(categorySourceLabel(l10n, testTransaction()), isNull);
    expect(
      dayLabel(l10n, today.addDays(-3), today, 'pt'),
      isNot(l10n.relativeTodayTitle),
    );
    expect(categoryName(l10n, const Category(id: 'x', name: 'Pets')), 'Pets');
    expect(
      daysLabel(
        l10n,
        from: const CalendarDate(2025, 12, 30),
        to: today,
        today: today,
        locale: 'pt-BR',
      ),
      '30 de dez. de 2025 a 8 de out.',
    );
    for (final key in FakeCategoriesRepository.keys) {
      expect(
        categoryName(l10n, Category(id: key, key: key, name: key)),
        isNot(key),
      );
    }
  });
}
