import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/category_review/category_review_providers.dart';
import 'package:cashdeck/features/category_review/domain/category_review.dart';
import 'package:cashdeck/features/category_review/presentation/category_review_badge.dart';
import 'package:cashdeck/features/category_review/presentation/category_review_labels.dart';
import 'package:cashdeck/features/category_review/presentation/category_review_screen.dart';
import 'package:cashdeck/features/category_review/presentation/category_rules_screen.dart';
import 'package:cashdeck/features/category_review/presentation/review_group_card.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/settings/presentation/settings_section.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/builders.dart';
import '../../../support/mocks.dart';
import '../../../support/pump_app.dart';
import '../review_fixtures.dart';

MockCategoryReviewRepository _mock({
  ReviewQueue queue = const ReviewQueue(pending: 0),
  List<CategoryRule> rules = const [],
}) {
  final repository = MockCategoryReviewRepository();
  when(() => repository.queue(entity: any(named: 'entity')))
      .thenAnswer((_) async => Ok(queue));
  when(repository.rules).thenAnswer((_) async => Ok(rules));
  return repository;
}

Future<void> _pick(WidgetTester tester, Key chip, Key option) async {
  await tester.tap(find.byKey(chip));
  await settle(tester);
  await tester.tap(find.byKey(option));
  await settle(tester);
}

void main() {
  setUpAll(() => registerFallbackValue(const CategoryRuleChange()));

  testWidgets('the transactions tab counts what waits and opens the review', (
    tester,
  ) async {
    final app = await pumpRoute(tester, AppRoutes.transactions);

    expect(find.byTooltip(l10n.categoryReviewPending(6)), findsOneWidget);
    await tester.tap(find.byKey(CategoryReviewBadge.buttonKey));
    await settle(tester);

    expect(app.location, AppRoutes.categoryReview);
    expect(find.byType(CategoryReviewScreen), findsOneWidget);
  });

  testWidgets('confirms groups and accepts a rule until all is categorized', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.categoryReview);

    expect(
      find.text(l10n.categoryReviewReasonLowConfidence('62')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(ReviewGroupCard.confirmKey('group-fuel')));
    await settle(tester);
    expect(find.text(l10n.categoryReviewSavedRule(2)), findsOneWidget);
    expect(find.text('Posto Modelo'), findsNothing);

    final confirm = find.byKey(ReviewGroupCard.confirmKey('group-bakery'));
    await tester.tap(confirm);
    await settle(tester);
    expect(find.text('Padaria Exemplo'), findsOneWidget);
    await _pick(
      tester,
      ReviewGroupCard.categoryKey('group-bakery'),
      ReviewGroupCard.optionKey('cat-groceries'),
    );
    await tester.tap(find.byKey(ReviewGroupCard.ruleKey('group-bakery')));
    await tester.pump();
    await tester.tap(confirm);
    await settle(tester);
    expect(find.text(l10n.categoryReviewSaved(4)), findsOneWidget);

    await tester.tap(
      find.byKey(CategoryReviewScreen.acceptKey('suggestion-market')),
    );
    await settle(tester);
    expect(find.text(l10n.categoryReviewRuleCreated), findsOneWidget);
    expect(find.text(l10n.categoryReviewDoneTitle), findsOneWidget);
  });

  testWidgets('swipes confirm and skip; a dismissed suggestion leaves', (
    tester,
  ) async {
    final app = await pumpRoute(tester, AppRoutes.categoryReview);

    await tester.drag(find.text('Posto Modelo'), const Offset(600, 0));
    await settle(tester);
    expect(find.text('Posto Modelo'), findsNothing);
    expect(find.text(l10n.categoryReviewSavedRule(2)), findsOneWidget);

    await tester.drag(find.text('Padaria Exemplo'), const Offset(600, 0));
    await settle(tester);
    expect(find.text('Padaria Exemplo'), findsOneWidget);
    await tester.drag(find.text('Padaria Exemplo'), const Offset(-600, 0));
    await settle(tester);
    expect(find.text('Padaria Exemplo'), findsNothing);

    await tester.tap(
      find.byKey(CategoryReviewScreen.dismissKey('suggestion-market')),
    );
    await settle(tester);
    expect(find.text(l10n.categoryReviewDoneTitle), findsOneWidget);

    await tester.tap(find.byKey(CategoryReviewScreen.rulesKey));
    await settle(tester);
    expect(app.location, AppRoutes.categoryRules);
  });

  testWidgets('a skipped group leaves by its button', (tester) async {
    await pumpRoute(tester, AppRoutes.categoryReview);

    await tester.tap(find.byKey(ReviewGroupCard.skipKey('group-bakery')));
    await settle(tester);

    expect(find.text('Padaria Exemplo'), findsNothing);
    expect(find.text('Posto Modelo'), findsOneWidget);
  });

  testWidgets('failures keep the cards and say why', (tester) async {
    final group = reviewGroup('a', suggestedCategoryId: 'cat-groceries');
    final repository = _mock(
      queue: ReviewQueue(
        pending: 2,
        groups: [group],
        suggestions: const [suggestion],
      ),
    );
    when(
      () => repository.categorize(
        any(),
        any(),
        createRule: any(named: 'createRule'),
      ),
    ).thenAnswer((_) async => const Err(NetworkFailure()));
    when(() => repository.acceptSuggestion(any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    when(() => repository.dismissSuggestion(any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    await pumpRoute(
      tester,
      AppRoutes.categoryReview,
      overrides: [
        categoryReviewRepositoryProvider.overrideWithValue(repository),
      ],
    );

    await tester.tap(find.byKey(ReviewGroupCard.confirmKey('a')));
    await settle(tester);
    expect(find.text(l10n.errorNetwork), findsOneWidget);
    expect(find.byKey(CategoryReviewScreen.groupKey('a')), findsOneWidget);

    await waitForToast(tester);
    await tester.tap(find.byKey(CategoryReviewScreen.acceptKey(suggestion.id)));
    await settle(tester);
    expect(find.text(l10n.errorNetwork), findsOneWidget);

    await waitForToast(tester);
    await tester.tap(
      find.byKey(CategoryReviewScreen.dismissKey(suggestion.id)),
    );
    await settle(tester);
    expect(find.text(l10n.errorNetwork), findsOneWidget);
    expect(find.text(l10n.categoryReviewSuggestionAccept), findsOneWidget);
  });

  testWidgets('a rule that relabels others reloads the queue', (tester) async {
    final group = reviewGroup('a', suggestedCategoryId: 'cat-groceries');
    final repository = _mock(queue: ReviewQueue(pending: 2, groups: [group]));
    when(
      () => repository.categorize(
        any(),
        any(),
        createRule: any(named: 'createRule'),
      ),
    ).thenAnswer(
      (_) async => Ok(
        CategorizeOutcome(updated: 2, similarUpdated: 3, rule: categoryRule()),
      ),
    );
    await pumpRoute(
      tester,
      AppRoutes.categoryReview,
      overrides: [
        categoryReviewRepositoryProvider.overrideWithValue(repository),
      ],
    );
    clearInteractions(repository);

    await tester.tap(find.byKey(ReviewGroupCard.confirmKey('a')));
    await settle(tester);

    expect(find.text(l10n.categoryReviewSavedRule(5)), findsOneWidget);
    verify(() => repository.queue(entity: EntityKind.personal))
        .called(greaterThanOrEqualTo(1));
  });

  testWidgets('a failed queue retries', (tester) async {
    final repository = MockCategoryReviewRepository();
    when(() => repository.queue(entity: any(named: 'entity')))
        .thenAnswer((_) async => const Err(ServerFailure()));
    await pumpRoute(
      tester,
      AppRoutes.categoryReview,
      overrides: [
        categoryReviewRepositoryProvider.overrideWithValue(repository),
      ],
    );
    expect(find.byType(CdErrorState), findsOneWidget);

    when(() => repository.queue(entity: any(named: 'entity')))
        .thenAnswer((_) async => const Ok(ReviewQueue(pending: 0)));
    await tester.tap(find.byKey(CdErrorState.retryKey));
    await settle(tester);

    expect(find.text(l10n.categoryReviewDoneTitle), findsOneWidget);
  });

  testWidgets('settings opens the rules; a rule is edited and deleted', (
    tester,
  ) async {
    final app = await pumpRoute(tester, AppRoutes.settings);
    await tester.tap(find.byKey(SettingsLink.keyOf(AppRoutes.categoryRules)));
    await settle(tester);
    expect(app.location, AppRoutes.categoryRules);
    expect(find.text('academia exemplo'), findsOneWidget);

    await tester.tap(find.byKey(CategoryRulesScreen.rowKey('rule-gym')));
    await settle(tester);
    await tester.enterText(find.byKey(CategoryRuleEditor.patternKey), ' ');
    await tester.tap(find.byKey(CategoryRuleEditor.saveKey));
    await settle(tester);
    expect(find.text(l10n.categoryRulePatternMissing), findsOneWidget);

    await tester.enterText(
      find.byKey(CategoryRuleEditor.patternKey),
      'academia nova',
    );
    await _pick(
      tester,
      CategoryRuleEditor.categoryKey,
      CategoryRuleEditor.optionKey('cat-health'),
    );
    await tester.tap(find.byKey(CategoryRuleEditor.saveKey));
    await settle(tester);
    expect(find.text(l10n.categoryRuleSaved), findsOneWidget);
    expect(find.text('academia nova'), findsOneWidget);

    await tester.tap(find.byKey(CategoryRulesScreen.rowKey('rule-gym')));
    await settle(tester);
    await tester.tap(find.byKey(CategoryRuleEditor.deleteKey));
    await settle(tester);
    expect(find.text(l10n.categoryRuleDeleteTitle), findsOneWidget);
    await tester.tap(find.byKey(CategoryRuleEditor.deleteKey));
    await settle(tester);
    expect(find.text(l10n.categoryRuleDeleted), findsOneWidget);
    expect(find.byKey(CategoryRulesScreen.rowKey('rule-gym')), findsNothing);
  });

  testWidgets('rules show empty, failed and refused states', (tester) async {
    final document = categoryRule(pattern: '', document: '11222333000181');
    final repository = _mock();
    final overrides = [
      categoryReviewRepositoryProvider.overrideWithValue(repository),
    ];
    final app = await pumpRoute(
      tester,
      AppRoutes.categoryRules,
      overrides: overrides,
    );
    expect(find.text(l10n.categoryRulesEmptyTitle), findsOneWidget);

    when(repository.rules).thenAnswer((_) async => const Err(ServerFailure()));
    app.router.go(AppRoutes.settings);
    await settle(tester);
    app.router.go(AppRoutes.categoryRules);
    await settle(tester);
    expect(find.byType(CdErrorState), findsOneWidget);

    when(repository.rules).thenAnswer((_) async => Ok([document]));
    when(() => repository.updateRule(any(), any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    when(() => repository.deleteRule(any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    await tester.tap(find.byKey(CdErrorState.retryKey));
    await settle(tester);
    expect(
      find.text(l10n.categoryRuleDocument('11222333000181')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(CategoryRulesScreen.rowKey(document.id)));
    await settle(tester);
    expect(
      find.text(l10n.categoryRuleDocumentHint('11222333000181')),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(CategoryRuleEditor.patternKey), 'loja');
    await tester.tap(find.byKey(CategoryRuleEditor.saveKey));
    await settle(tester);
    expect(find.byKey(CategoryRuleEditor.errorKey), findsOneWidget);

    await tester.tap(find.byKey(CategoryRuleEditor.deleteKey));
    await settle(tester);
    await tester.tap(find.byKey(CategoryRuleEditor.deleteKey));
    await settle(tester);
    expect(find.text(l10n.errorNetwork), findsOneWidget);
  });

  test('labels name reasons, directions and the rule scope', () {
    const categories = [Category(id: 'cat-1', name: 'Pets')];
    expect(
      reviewReasonLabel(l10n, ReviewReason.lowConfidence, null),
      l10n.categoryReviewReasonUnsure,
    );
    expect(
      reviewReasonLabel(l10n, ReviewReason.inconsistent, 0.9),
      l10n.categoryReviewReasonInconsistent,
    );
    expect(
      flowDirectionLabel(l10n, FlowDirection.incoming),
      l10n.categoryRuleIncoming,
    );
    expect(flowDirectionLabel(l10n, null), l10n.categoryRuleAnyDirection);
    expect(categoryLabel(l10n, 'cat-1', categories), 'Pets');
    expect(
      categoryLabel(l10n, 'gone', categories),
      l10n.transactionCategoryUnknown,
    );
    final rule = CategoryRule(
      id: 'r',
      owner: EntityKind.company,
      pattern: '',
      direction: FlowDirection.incoming,
      categoryId: 'cat-1',
      createdAt: testNow,
    );
    expect(ruleMatchLabel(l10n, rule), '');
    expect(
      ruleScopeLine(l10n, rule, categories),
      'Pets · ${l10n.entityCompany} · ${l10n.categoryRuleIncoming}',
    );
    expect(
      ruleScopeLine(l10n, categoryRule(), categories),
      contains(l10n.categoryRuleAnyEntity),
    );
  });
}
