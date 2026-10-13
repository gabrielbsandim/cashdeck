import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/plan/domain/life_plan.dart';

final class LoadPlan {
  const new(this._repository);

  final PlanRepository _repository;

  Future<Result<LifePlan>> call() => _repository.load();
}

/// Adds a goal, or replaces the one with `id`. A draft with a problem never
/// reaches the server.
final class SavePlanGoal {
  const new(this._repository);

  final PlanRepository _repository;

  Future<Result<LifePlan>> call(PlanGoalDraft draft, {String? id}) {
    if (draft.problem != null) {
      return Future.value(const Err(UnexpectedFailure()));
    }
    if (id == null) return _repository.create(draft);
    return _repository.update(id, draft);
  }
}

final class RemovePlanGoal {
  const new(this._repository);

  final PlanRepository _repository;

  Future<Result<LifePlan>> call(String id) => _repository.remove(id);
}

final class ReorderPlan {
  const new(this._repository);

  final PlanRepository _repository;

  Future<Result<LifePlan>> call(List<String> ids) => _repository.reorder(ids);
}

/// Asks the model where one goal fits, or how to arrange them all.
final class AdvisePlan {
  const new(this._repository);

  final PlanRepository _repository;

  Future<Result<PlanAdvice>> call({String? goalId}) =>
      _repository.advise(goalId: goalId);
}

final class ApplyPlanAdvice {
  const new(this._repository);

  final PlanRepository _repository;

  Future<Result<LifePlan>> call(PlanAdvice advice) =>
      _repository.arrange(advice);
}

final class SavePlanSettings {
  const new(this._repository);

  final PlanRepository _repository;

  Future<Result<LifePlan>> call(PlanSettings settings) {
    if (settings.problem != null) {
      return Future.value(const Err(UnexpectedFailure()));
    }
    return _repository.saveSettings(settings);
  }
}
