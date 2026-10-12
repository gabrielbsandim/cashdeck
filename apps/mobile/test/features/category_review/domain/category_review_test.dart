import 'package:cashdeck/features/category_review/domain/category_review.dart';
import 'package:flutter_test/flutter_test.dart';

import '../review_fixtures.dart';

void main() {
  test('a queue loses a settled group and a decided suggestion', () {
    final queue = ReviewQueue(
      pending: 5,
      groups: [reviewGroup('a', count: 3), reviewGroup('b')],
      suggestions: const [suggestion],
    );

    final withoutA = queue.withoutGroup('a');
    expect(withoutA.pending, 2);
    expect(withoutA.groups.single.id, 'b');
    expect(withoutA.suggestions, [suggestion]);
    expect(queue.withoutGroup('none'), queue);
    expect(
      ReviewQueue(pending: 1, groups: [reviewGroup('a')]).withoutGroup('a'),
      const ReviewQueue(pending: 0),
    );

    final decided = withoutA.withoutGroup('b').withoutSuggestion(suggestion.id);
    expect(decided.isEmpty, isTrue);
    expect(queue.isEmpty, isFalse);
    expect(const ReviewQueue(pending: 0).isEmpty, isTrue);
  });

  test('a rule shows its words or its document', () {
    expect(categoryRule().matches, 'academia');
    expect(
      categoryRule(pattern: '', document: '11222333000181').matches,
      '11222333000181',
    );
    expect(categoryRule(pattern: '').matches, '');
    expect(categoryRule(), categoryRule());
  });

  test('a rule change knows when it is empty or blank', () {
    expect(const CategoryRuleChange().isEmpty, isTrue);
    expect(const CategoryRuleChange().isValid, isTrue);
    expect(const CategoryRuleChange(categoryId: 'cat-1').isEmpty, isFalse);
    expect(const CategoryRuleChange(pattern: ' ').isValid, isFalse);
    expect(const CategoryRuleChange(pattern: 'x').isValid, isTrue);
    expect(const CategoryRuleChange(pattern: 'x').props, ['x', null]);
  });

  test('values compare by their fields', () {
    expect(reviewGroup('a'), reviewGroup('a'));
    expect(reviewGroup('a'), isNot(reviewGroup('b')));
    expect(suggestion.props, hasLength(8));
    expect(
      CategorizeOutcome(updated: 1, rule: categoryRule()),
      CategorizeOutcome(updated: 1, rule: categoryRule()),
    );
  });
}
