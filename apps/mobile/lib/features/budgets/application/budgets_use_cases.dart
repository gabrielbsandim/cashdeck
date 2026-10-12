import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/budgets/domain/budget.dart';

Future<Result<T>> _refused<T>() =>
    Future.value(Err<T>(const UnexpectedFailure()));

final class LoadBudgetMonth {
  const new(this._repository);

  final BudgetsRepository _repository;

  Future<Result<BudgetMonth>> call(YearMonth month) => _repository.month(month);
}

/// Sets a limit for a category, or changes the budget with `id`. A limit
/// of zero never reaches the server.
final class SetBudgetLimit {
  const new(this._repository);

  final BudgetsRepository _repository;

  Future<Result<BudgetMonth>> call({
    required YearMonth month,
    required String categoryId,
    required Money limit,
    required bool rollover,
    String? id,
  }) {
    if (limit.cents <= 0) return _refused();
    if (id == null) {
      return _repository.create(month, categoryId, limit, rollover: rollover);
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

  Future<Result<BudgetMonth>> call(YearMonth from) =>
      _repository.copyToNext(from);
}

final class SuggestBudgets {
  const new(this._repository);

  final BudgetsRepository _repository;

  Future<Result<BudgetSuggestions>> call(YearMonth month) =>
      _repository.suggestions(month);
}

/// Sets every chosen limit at once; nothing chosen sends nothing.
final class AcceptBudgetSuggestions {
  const new(this._repository);

  final BudgetsRepository _repository;

  Future<Result<BudgetMonth>> call(YearMonth month, List<BudgetLimit> limits) {
    if (limits.isEmpty) return _refused();
    return _repository.accept(month, limits);
  }
}
