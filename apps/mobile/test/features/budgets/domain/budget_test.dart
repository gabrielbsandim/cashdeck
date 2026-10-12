import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/features/budgets/domain/budget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../budget_builders.dart';

const _pets = SpendCategory(id: 'cat-pets', name: 'Pet');
const _transport = SpendCategory(
  id: 'cat-transport',
  key: 'transport',
  name: 'Transporte',
);

void main() {
  test('a usage past the limit is over', () {
    expect(usageAt(120).over, isTrue);
    expect(usageAt(100).over, isFalse);
    expect(usageAt(50), usageAt(50));
    expect(itemAt(50), itemAt(50));
    expect(
      UnbudgetedSpend(category: _pets, spent: Money(usageAt(10).spent.cents)),
      isNot(const UnbudgetedSpend(category: _pets, spent: Money(1))),
    );
  });

  test('a month lists the fullest categories near the limit', () {
    final month = BudgetMonth(
      month: october,
      total: usageAt(70),
      items: [
        itemAt(130, id: 'a'),
        itemAt(100, id: 'b'),
        itemAt(90, id: 'c'),
        itemAt(85, id: 'd'),
        itemAt(20, id: 'e'),
      ],
    );
    expect(month.isEmpty, isFalse);
    expect(month.nearLimit().map((item) => item.id), ['a', 'b', 'c']);
    expect(month.nearLimit(count: 9).map((item) => item.id), [
      'a',
      'b',
      'c',
      'd',
    ]);
    final empty = BudgetMonth(
      month: october,
      total: usageAt(0),
      items: const [],
    );
    expect(empty.isEmpty, isTrue);
    expect(empty.unbudgeted, isEmpty);
    expect(
      empty,
      BudgetMonth(month: october, total: usageAt(0), items: const []),
    );
  });

  test('the chosen limits keep the adjustments and drop zeros', () {
    final suggestions = BudgetSuggestions(
      month: october,
      basedOn: const [],
      items: [
        suggestionFor(groceries, 70_000, current: 60_000),
        suggestionFor(_transport, 30_000),
        suggestionFor(_pets, 10_000),
      ],
    );
    expect(
      suggestions,
      isNot(
        BudgetSuggestions(
          month: october,
          basedOn: const [],
          items: [suggestionFor(groceries, 1)],
        ),
      ),
    );
    expect(
      suggestions.items.first,
      suggestionFor(groceries, 70_000, current: 60_000),
    );
    expect(
      chosenLimits(
        suggestions,
        chosen: {'cat-groceries', 'cat-transport', 'cat-pets'},
        adjusted: {
          'cat-transport': const Money(35_000),
          'cat-pets': const Money(0),
        },
      ),
      [
        (categoryId: 'cat-groceries', limit: const Money(70_000)),
        (categoryId: 'cat-transport', limit: const Money(35_000)),
      ],
    );
    expect(chosenLimits(suggestions, chosen: {'cat-pets'}), [
      (categoryId: 'cat-pets', limit: const Money(10_000)),
    ]);
    expect(chosenLimits(suggestions, chosen: const {}), isEmpty);
  });
}
