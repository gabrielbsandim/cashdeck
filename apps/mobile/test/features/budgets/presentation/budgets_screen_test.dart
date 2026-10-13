import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/budgets/budgets_providers.dart';
import 'package:cashdeck/features/budgets/domain/budget.dart';
import 'package:cashdeck/features/budgets/presentation/budget_limit_sheet.dart';
import 'package:cashdeck/features/budgets/presentation/budget_suggestions_screen.dart';
import 'package:cashdeck/features/budgets/presentation/budgets_screen.dart';
import 'package:cashdeck/features/budgets/presentation/home_budget_card.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/pump_app.dart';
import '../application/budgets_use_cases_test.dart' show MockBudgetsRepository;
import '../budget_builders.dart';

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

Future<void> _type(WidgetTester tester, Key key, String text) async {
  await tester.enterText(find.byKey(key), text);
  await tester.pump();
}

Future<void> _closeSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(200, 20));
  await settle(tester);
}

BudgetMonth _monthOf(List<BudgetItem> items) =>
    BudgetMonth(month: october, total: usageAt(50), items: items);

void main() {
  setUpAll(() {
    registerFallbackValue(october);
    registerFallbackValue(EntityKind.personal);
    registerFallbackValue(const Money(0));
    registerFallbackValue(<BudgetLimit>[]);
  });

  testWidgets('edits, deletes and sets limits from the month', (tester) async {
    await pumpRoute(tester, AppRoutes.budgets);

    expect(find.byKey(BudgetsScreen.itemKey('budget-restaurants')), findsOne);
    expect(find.byKey(BudgetsScreen.unbudgetedKey('cat-leisure')), findsOne);

    await _tap(tester, find.byKey(BudgetsScreen.itemKey('budget-groceries')));
    expect(
      find.text(l10n.budgetCarried(MoneyFormat.whole(const Money(5_000)))),
      findsOneWidget,
    );
    await _type(tester, BudgetLimitSheet.limitKey, '90000');
    await _tap(tester, find.byKey(BudgetLimitSheet.rolloverKey));
    await _tap(tester, find.byKey(BudgetLimitSheet.saveKey));
    expect(find.byKey(BudgetLimitSheet.saveKey), findsNothing);
    expect(find.text(l10n.budgetSaved), findsOneWidget);
    await waitForToast(tester);

    await _tap(tester, find.byKey(BudgetsScreen.itemKey('budget-restaurants')));
    await _tap(tester, find.byKey(BudgetLimitSheet.deleteKey));
    expect(find.text(l10n.budgetDeleted), findsOneWidget);
    expect(
      find.byKey(BudgetsScreen.itemKey('budget-restaurants')),
      findsNothing,
    );
    expect(
      find.byKey(BudgetsScreen.unbudgetedKey('cat-restaurants')),
      findsOneWidget,
    );
    await waitForToast(tester);

    await _tap(tester, find.byKey(BudgetsScreen.unbudgetedKey('cat-leisure')));
    expect(find.byKey(BudgetLimitSheet.deleteKey), findsNothing);
    await _tap(tester, find.byKey(BudgetLimitSheet.saveKey));
    expect(find.text(l10n.budgetLimitMissing), findsOneWidget);
    await _type(tester, BudgetLimitSheet.limitKey, '20000');
    await _tap(tester, find.byKey(BudgetLimitSheet.saveKey));
    expect(
      find.byKey(BudgetsScreen.unbudgetedKey('cat-leisure')),
      findsNothing,
    );
  });

  testWidgets('switches months and copies one into the next', (tester) async {
    await pumpRoute(tester, AppRoutes.budgets);

    await _tap(tester, find.byKey(BudgetsScreen.previousKey));
    expect(find.text(l10n.budgetsEmptyTitle), findsOneWidget);
    expect(find.byKey(BudgetsScreen.unbudgetedKey('cat-pets')), findsOne);
    await _tap(tester, find.byKey(BudgetsScreen.nextKey));
    await _tap(tester, find.byKey(BudgetsScreen.nextKey));
    expect(find.text(l10n.budgetsEmptyTitle), findsOneWidget);
    await _tap(tester, find.byKey(BudgetsScreen.previousKey));

    await _tap(tester, find.byKey(BudgetsScreen.copyKey));
    expect(find.text(l10n.budgetsCopied), findsOneWidget);
    expect(find.text(l10n.budgetsEmptyTitle), findsNothing);
    expect(
      find.text(l10n.budgetsLeft(MoneyFormat.whole(const Money(168_600)))),
      findsOneWidget,
    );
  });

  testWidgets('builds the budget from the suggestions', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.budgets);

    await _tap(tester, find.byKey(BudgetsScreen.suggestKey));
    expect(app.location, '${AppRoutes.budgets}/suggestions');
    expect(find.byKey(BudgetSuggestionsKeys.rowKey('cat-pets')), findsOne);

    await _tap(tester, find.byKey(BudgetSuggestionsKeys.checkKey('cat-pets')));
    await _tap(
      tester,
      find.byKey(BudgetSuggestionsKeys.adjustKey('cat-leisure')),
    );
    await _type(tester, BudgetSuggestionsKeys.adjustValueKey, '25000');
    await _tap(tester, find.byKey(BudgetSuggestionsKeys.adjustSaveKey));
    expect(
      find.descendant(
        of: find.byKey(BudgetSuggestionsKeys.adjustKey('cat-leisure')),
        matching: find.textContaining('250'),
      ),
      findsOneWidget,
    );
    await _tap(
      tester,
      find.byKey(BudgetSuggestionsKeys.adjustKey('cat-transport')),
    );
    await _closeSheet(tester);

    await _tap(tester, find.byKey(BudgetSuggestionsKeys.acceptKey));
    expect(app.location, AppRoutes.budgets);
    expect(find.text(l10n.budgetsAccepted), findsOneWidget);
    expect(
      find.byKey(BudgetsScreen.unbudgetedKey('cat-leisure')),
      findsNothing,
    );
  });

  testWidgets('a broken month link opens the current month', (tester) async {
    await pumpRoute(tester, '${AppRoutes.budgets}?month=nope');
    expect(find.byKey(BudgetsScreen.itemKey('budget-groceries')), findsOne);

    await pumpRoute(tester, '${AppRoutes.budgets}/suggestions');
    expect(find.byKey(BudgetSuggestionsKeys.rowKey('cat-groceries')), findsOne);
  });

  testWidgets('switches to the company budgets', (tester) async {
    await pumpRoute(tester, AppRoutes.budgets);
    expect(find.byKey(BudgetsScreen.itemKey('budget-software')), findsNothing);

    await _tap(tester, find.byKey(BudgetsScreen.entityKey(EntityKind.company)));
    expect(find.byKey(BudgetsScreen.itemKey('budget-software')), findsOne);
    expect(find.byKey(BudgetsScreen.unbudgetedKey('cat-office')), findsOne);
    expect(
      find.byKey(BudgetsScreen.itemKey('budget-restaurants')),
      findsNothing,
    );

    await _tap(
      tester,
      find.byKey(BudgetsScreen.entityKey(EntityKind.personal)),
    );
    expect(find.byKey(BudgetsScreen.itemKey('budget-restaurants')), findsOne);
  });

  testWidgets('a month link opens that month', (tester) async {
    await pumpRoute(tester, '${AppRoutes.budgets}?month=2026-09');
    expect(find.text(l10n.budgetsEmptyTitle), findsOneWidget);
    await _tap(tester, find.text(l10n.budgetsSuggest));
    expect(find.byType(BudgetSuggestionsScreen), findsOneWidget);
  });

  testWidgets('failures stay on screen with a way out', (tester) async {
    final repository = MockBudgetsRepository();
    var loads = 0;
    when(() => repository.month(any(), any())).thenAnswer(
      (_) async => loads++ == 0
          ? const Err(ServerFailure())
          : Ok(_monthOf([itemAt(85)])),
    );
    when(
      () => repository.update(
        any(),
        limit: any(named: 'limit'),
        rollover: any(named: 'rollover'),
      ),
    ).thenAnswer((_) async => const Err(ValidationFailure('Limite recusado.')));
    when(() => repository.copyToNext(any(), any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    var suggested = 0;
    when(() => repository.suggestions(any(), any())).thenAnswer(
      (_) async => suggested++ == 0
          ? const Err(ServerFailure())
          : Ok(
              BudgetSuggestions(
                month: october,
                basedOn: const [],
                items: [suggestionFor(groceries, 70_000)],
              ),
            ),
    );
    when(() => repository.accept(any(), any(), any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    final app = await pumpRoute(
      tester,
      AppRoutes.budgets,
      overrides: [budgetsRepositoryProvider.overrideWithValue(repository)],
    );

    expect(find.text(l10n.errorServer), findsOneWidget);
    await _tap(tester, find.text(l10n.retryButton));
    expect(find.byKey(BudgetsScreen.itemKey('budget-1')), findsOneWidget);

    await _tap(tester, find.byKey(BudgetsScreen.itemKey('budget-1')));
    await _tap(tester, find.byKey(BudgetLimitSheet.saveKey));
    expect(find.text('Limite recusado.'), findsOneWidget);
    await _closeSheet(tester);

    await _tap(tester, find.byKey(BudgetsScreen.copyKey));
    expect(find.text(l10n.errorNetwork), findsOneWidget);
    await waitForToast(tester);

    await _tap(tester, find.byKey(BudgetsScreen.suggestKey));
    expect(find.text(l10n.errorServer), findsOneWidget);
    await _tap(tester, find.text(l10n.retryButton));
    await _tap(
      tester,
      find.byKey(BudgetSuggestionsKeys.checkKey(groceries.id)),
    );
    await _tap(tester, find.byKey(BudgetSuggestionsKeys.acceptKey));
    verifyNever(() => repository.accept(any(), any(), any()));
    await _tap(
      tester,
      find.byKey(BudgetSuggestionsKeys.checkKey(groceries.id)),
    );
    await _tap(tester, find.byKey(BudgetSuggestionsKeys.acceptKey));
    expect(app.location, '${AppRoutes.budgets}/suggestions');
    expect(find.text(l10n.errorNetwork), findsOneWidget);
  });

  testWidgets('no history means no suggestion', (tester) async {
    final repository = MockBudgetsRepository();
    when(() => repository.suggestions(any(), any())).thenAnswer(
      (_) async =>
          const Ok(BudgetSuggestions(month: october, basedOn: [], items: [])),
    );
    await pumpRoute(
      tester,
      AppRoutes.budgetSuggestionsFor('2026-10'),
      overrides: [budgetsRepositoryProvider.overrideWithValue(repository)],
    );
    expect(find.text(l10n.budgetsSuggestEmptyTitle), findsOneWidget);
  });

  group('home card', () {
    testWidgets('shows the total and the fullest categories', (tester) async {
      final app = await pumpRoute(tester, AppRoutes.home, screenHeight: 5200);

      expect(
        find.text(l10n.budgetsLeft(MoneyFormat.whole(const Money(24_500)))),
        findsOneWidget,
      );
      await _tap(tester, find.byKey(HomeBudgetCard.seeAllKey));
      expect(app.location, AppRoutes.budgets);
    });

    testWidgets('says when every category is calm', (tester) async {
      final repository = MockBudgetsRepository();
      when(() => repository.month(any(), any()))
          .thenAnswer((_) async => Ok(_monthOf([itemAt(20)])));
      await pumpRoute(
        tester,
        AppRoutes.home,
        screenHeight: 5400,
        overrides: [budgetsRepositoryProvider.overrideWithValue(repository)],
      );
      expect(find.text(l10n.homeBudgetAllCalm), findsOneWidget);
    });

    testWidgets('without budgets offers the suggestion', (tester) async {
      final repository = MockBudgetsRepository();
      when(() => repository.month(any(), any()))
          .thenAnswer((_) async => Ok(_monthOf(const [])));
      when(() => repository.suggestions(any(), any())).thenAnswer(
        (_) async =>
            const Ok(BudgetSuggestions(month: october, basedOn: [], items: [])),
      );
      final app = await pumpRoute(
        tester,
        AppRoutes.home,
        screenHeight: 5400,
        overrides: [budgetsRepositoryProvider.overrideWithValue(repository)],
      );
      expect(find.text(l10n.homeBudgetEmpty), findsOneWidget);
      await _tap(tester, find.byKey(HomeBudgetCard.suggestKey));
      expect(app.location, '${AppRoutes.budgets}/suggestions');
    });
  });
}
