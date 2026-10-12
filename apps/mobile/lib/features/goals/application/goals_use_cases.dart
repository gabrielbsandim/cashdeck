import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/goals/domain/goal.dart';

final class ListGoals {
  const new(this._repository);

  final GoalsRepository _repository;

  Future<Result<List<Goal>>> call() => _repository.list();
}

final class GetGoal {
  const new(this._repository);

  final GoalsRepository _repository;

  Future<Result<Goal>> call(String id) => _repository.get(id);
}

/// Creates a goal, or changes the one with `id`. A draft that breaks a rule
/// never reaches the server.
final class SaveGoal {
  const new(this._repository);

  final GoalsRepository _repository;

  Future<Result<Goal>> call(
    GoalDraft draft, {
    required CalendarDate today,
    String? id,
  }) {
    if (draft.problemOn(today) != null) {
      return Future.value(const Err(UnexpectedFailure()));
    }
    if (id == null) return _repository.create(draft);
    return _repository.update(id, draft);
  }
}

final class ArchiveGoal {
  const new(this._repository);

  final GoalsRepository _repository;

  Future<Result<Goal>> call(String id) => _repository.archive(id);
}

final class DeleteGoal {
  const new(this._repository);

  final GoalsRepository _repository;

  Future<Result<void>> call(String id) => _repository.delete(id);
}

/// Puts money in, or takes it out with a negative amount; zero is refused.
final class ContributeToGoal {
  const new(this._repository);

  final GoalsRepository _repository;

  Future<Result<Goal>> call(String id, Money amount, {String? note}) {
    if (amount.cents == 0) {
      return Future.value(const Err(UnexpectedFailure()));
    }
    final trimmed = note?.trim();
    return _repository.contribute(
      id,
      amount,
      note: trimmed == null || trimmed.isEmpty ? null : trimmed,
    );
  }
}

final class RemoveContribution {
  const new(this._repository);

  final GoalsRepository _repository;

  Future<Result<Goal>> call(String id, String contributionId) =>
      _repository.removeContribution(id, contributionId);
}
