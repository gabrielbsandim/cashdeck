import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/budgets/domain/budget.dart';

const october = YearMonth(2026, 10);

const groceries = SpendCategory(
  id: 'cat-groceries',
  key: 'groceries',
  name: 'Mercado',
);

BudgetUsage usageAt(int percent, {int available = 10_000}) {
  final spent = available * percent ~/ 100;
  return BudgetUsage(
    available: Money(available),
    spent: Money(spent),
    remaining: Money(available - spent),
    percent: percent,
    level: switch (percent) {
      >= 100 => BudgetLevel.reached,
      >= 80 => BudgetLevel.near,
      _ => BudgetLevel.ok,
    },
  );
}

BudgetItem itemAt(
  int percent, {
  String id = 'budget-1',
  SpendCategory category = groceries,
}) => BudgetItem(
  id: id,
  category: category,
  limit: const Money(10_000),
  carried: const Money(0),
  rollover: false,
  usage: usageAt(percent),
);

BudgetSuggestion suggestionFor(
  SpendCategory category,
  int suggested, {
  int? current,
}) => BudgetSuggestion(
  category: category,
  months: [Money(suggested), Money(suggested)],
  suggested: Money(suggested),
  current: current == null ? null : Money(current),
);
