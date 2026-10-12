import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/category_review/application/category_review_use_cases.dart';
import 'package:cashdeck/features/category_review/domain/category_review.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/mocks.dart';
import '../review_fixtures.dart';

void main() {
  late MockCategoryReviewRepository repository;

  setUpAll(() => registerFallbackValue(const CategoryRuleChange()));

  setUp(() => repository = MockCategoryReviewRepository());

  test('the queue follows the entity in view', () async {
    const queue = ReviewQueue(pending: 0);
    when(() => repository.queue(entity: any(named: 'entity')))
        .thenAnswer((_) async => const Ok(queue));
    final load = LoadReviewQueue(repository);

    for (final scope in EntityScope.values) {
      expect(await load(scope), const Ok(queue));
    }

    verify(() => repository.queue(entity: EntityKind.personal)).called(1);
    verify(() => repository.queue(entity: EntityKind.company)).called(1);
    verify(() => repository.queue()).called(1);
  });

  test('a group goes with a rule only when it can make one', () async {
    const outcome = CategorizeOutcome(updated: 2);
    when(
      () => repository.categorize(
        any(),
        any(),
        createRule: any(named: 'createRule'),
      ),
    ).thenAnswer((_) async => const Ok(outcome));
    final categorize = CategorizeGroup(repository);

    await categorize(reviewGroup('a'), 'cat-1', createRule: true);
    await categorize(
      reviewGroup('b', canCreateRule: false),
      'cat-1',
      createRule: true,
    );
    await categorize(reviewGroup('c'), 'cat-1', createRule: false);

    verify(
      () => repository.categorize(['a-0', 'a-1'], 'cat-1', createRule: true),
    ).called(1);
    verify(
      () => repository.categorize(['b-0', 'b-1'], 'cat-1', createRule: false),
    ).called(1);
    verify(
      () => repository.categorize(['c-0', 'c-1'], 'cat-1', createRule: false),
    ).called(1);
  });

  test('suggestions and rules forward to the repository', () async {
    final rule = categoryRule();
    final outcome = CategorizeOutcome(updated: 0, rule: rule);
    when(() => repository.acceptSuggestion(suggestion.id))
        .thenAnswer((_) async => Ok(outcome));
    when(() => repository.dismissSuggestion(suggestion.id))
        .thenAnswer((_) async => const Ok(null));
    when(repository.rules).thenAnswer((_) async => Ok([rule]));
    when(() => repository.deleteRule(rule.id))
        .thenAnswer((_) async => const Ok(null));

    expect(await AcceptRuleSuggestion(repository)(suggestion), Ok(outcome));
    expect(
      await DismissRuleSuggestion(repository)(suggestion),
      const Ok<void>(null),
    );
    expect(await ListCategoryRules(repository)(), Ok([rule]));
    expect(await DeleteCategoryRule(repository)(rule), const Ok<void>(null));
  });

  test('a rule change skips empty and blank edits', () async {
    final rule = categoryRule();
    final renamed = categoryRule(pattern: 'academia nova');
    const change = CategoryRuleChange(pattern: 'academia nova');
    when(() => repository.updateRule(rule.id, change))
        .thenAnswer((_) async => Ok(renamed));
    final update = UpdateCategoryRule(repository);

    expect(await update(rule, change), Ok(renamed));
    expect(await update(rule, const CategoryRuleChange()), Ok(rule));
    expect(
      await update(rule, const CategoryRuleChange(pattern: '  ')),
      const Err<CategoryRule>(UnexpectedFailure()),
    );
    verify(() => repository.updateRule(any(), any())).called(1);
  });
}
