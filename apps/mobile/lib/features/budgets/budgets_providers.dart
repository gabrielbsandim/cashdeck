import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/budgets/application/budgets_use_cases.dart';
import 'package:cashdeck/features/budgets/data/api_budgets_repository.dart';
import 'package:cashdeck/features/budgets/data/fake_budgets_repository.dart';
import 'package:cashdeck/features/budgets/domain/budget.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final budgetsRepositoryProvider = Provider<BudgetsRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeBudgetsRepository(ref.watch(clockProvider)),
    Backend.api => ApiBudgetsRepository(ref.watch(dioProvider)),
  };
});

final loadBudgetMonthProvider = Provider<LoadBudgetMonth>(
  (ref) => LoadBudgetMonth(ref.watch(budgetsRepositoryProvider)),
);

final setBudgetLimitProvider = Provider<SetBudgetLimit>(
  (ref) => SetBudgetLimit(ref.watch(budgetsRepositoryProvider)),
);

final deleteBudgetProvider = Provider<DeleteBudget>(
  (ref) => DeleteBudget(ref.watch(budgetsRepositoryProvider)),
);

final copyBudgetsProvider = Provider<CopyBudgets>(
  (ref) => CopyBudgets(ref.watch(budgetsRepositoryProvider)),
);

final suggestBudgetsProvider = Provider<SuggestBudgets>(
  (ref) => SuggestBudgets(ref.watch(budgetsRepositoryProvider)),
);

final acceptBudgetSuggestionsProvider = Provider<AcceptBudgetSuggestions>(
  (ref) => AcceptBudgetSuggestions(ref.watch(budgetsRepositoryProvider)),
);
