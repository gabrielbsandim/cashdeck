import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/budgets/budgets_providers.dart';
import 'package:cashdeck/features/budgets/domain/budget.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

/// The month the clock is in, in Brazil.
final Provider<YearMonth> currentBudgetMonthProvider = Provider<YearMonth>(
  (ref) =>
      YearMonth.of(CalendarDate.brazilToday(ref.watch(clockProvider).now())),
);

/// Budgets follow the home scope; the consolidated view keeps the person's,
/// since a budget always belongs to one entity.
final Provider<EntityKind> budgetEntityProvider = Provider<EntityKind>(
  (ref) => switch (ref.watch(entityScopeProvider)) {
    EntityScope.company => EntityKind.company,
    EntityScope.personal || EntityScope.consolidated => EntityKind.personal,
  },
);

class BudgetMonthController extends AsyncNotifier<BudgetMonth> {
  new(this.month);

  final YearMonth month;

  EntityKind get _entity => ref.read(budgetEntityProvider);

  @override
  Future<BudgetMonth> build() async =>
      (await ref
              .watch(loadBudgetMonthProvider)
              .call(ref.watch(budgetEntityProvider), month))
          .orThrow;

  /// Keeps the new view of [Ok] results; returns the failure otherwise.
  AppFailure? _keep(Result<BudgetMonth> result) {
    switch (result) {
      case Ok(:final value):
        state = AsyncData(value);
        return null;
      case Err(:final failure):
        return failure;
    }
  }

  /// Sets a limit for [categoryId], or changes the budget with [id].
  Future<AppFailure?> setLimit({
    required String categoryId,
    required Money limit,
    required bool rollover,
    String? id,
  }) async => _keep(
    await ref
        .read(setBudgetLimitProvider)
        .call(
          entity: _entity,
          month: month,
          categoryId: categoryId,
          limit: limit,
          rollover: rollover,
          id: id,
        ),
  );

  Future<AppFailure?> delete(String id) async =>
      _keep(await ref.read(deleteBudgetProvider).call(id));

  Future<AppFailure?> accept(List<BudgetLimit> limits) async => _keep(
    await ref
        .read(acceptBudgetSuggestionsProvider)
        .call(_entity, month, limits),
  );

  /// Copies this month into the next one, whose view refreshes.
  Future<AppFailure?> copyToNext() async {
    final result = await ref.read(copyBudgetsProvider).call(_entity, month);
    if (result case Err(:final failure)) return failure;
    ref.invalidate(budgetMonthControllerProvider(month.add(1)));
    return null;
  }
}

final AsyncNotifierProviderFamily<BudgetMonthController, BudgetMonth, YearMonth>
budgetMonthControllerProvider = AsyncNotifierProvider.autoDispose
    .family<BudgetMonthController, BudgetMonth, YearMonth>(
      BudgetMonthController.new,
      retry: noRetry,
    );

final FutureProviderFamily<BudgetSuggestions, YearMonth>
budgetSuggestionsProvider = FutureProvider.autoDispose
    .family<BudgetSuggestions, YearMonth>(
      (ref, month) async =>
          (await ref
                  .watch(suggestBudgetsProvider)
                  .call(ref.watch(budgetEntityProvider), month))
              .orThrow,
      retry: noRetry,
    );
