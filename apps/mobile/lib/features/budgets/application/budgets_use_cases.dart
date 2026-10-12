import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/budgets/domain/budget.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';

Future<Result<T>> _refused<T>() =>
    Future.value(Err<T>(const UnexpectedFailure()));

final class LoadBudgetMonth {
  const new(this._repository);

  final BudgetsRepository _repository;

  Future<Result<BudgetMonth>> call(EntityKind entity, YearMonth month) =>
      _repository.month(entity, month);
}

/// Sets a limit for a category, or changes the budget with `id`. A limit
/// of zero never reaches the server.
final class SetBudgetLimit {
  const new(this._repository);

  final BudgetsRepository _repository;

  Future<Result<BudgetMonth>> call({
    required EntityKind entity,
    required YearMonth month,
    required String categoryId,
    required Money limit,
    required bool rollover,
    String? id,
  }) {
    if (limit.cents <= 0) return _refused();
    if (id == null) {
      return _repository.create(
        entity,
        month,
        categoryId,
        limit,
        rollover: rollover,
      );
    }
    return _repository.update(id, limit: limit, rollover: rollover);
  }
}

final class DeleteBudget {
  const new(this._repository);

  final BudgetsRepository _repository;

  Future<Result<BudgetMonth>> call(String id) => _repository.delete(id);
}

final class CopyBudgets {
  const new(this._repository);

  final BudgetsRepository _repository;

  Future<Result<BudgetMonth>> call(EntityKind entity, YearMonth from) =>
      _repository.copyToNext(entity, from);
}

final class SuggestBudgets {
  const new(this._repository);

  final BudgetsRepository _repository;

  Future<Result<BudgetSuggestions>> call(EntityKind entity, YearMonth month) =>
      _repository.suggestions(entity, month);
}

/// Sets every chosen limit at once; nothing chosen sends nothing.
final class AcceptBudgetSuggestions {
  const new(this._repository);

  final BudgetsRepository _repository;

  Future<Result<BudgetMonth>> call(
    EntityKind entity,
    YearMonth month,
    List<BudgetLimit> limits,
  ) {
    if (limits.isEmpty) return _refused();
    return _repository.accept(entity, month, limits);
  }
}
