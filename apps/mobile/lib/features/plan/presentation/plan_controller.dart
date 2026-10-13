import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/plan/domain/life_plan.dart';
import 'package:cashdeck/features/plan/plan_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The plan, replaced by the one the server answers after every change.
class PlanController extends AsyncNotifier<LifePlan> {
  @override
  Future<LifePlan> build() async =>
      (await ref.watch(loadPlanProvider).call()).orThrow;

  Future<AppFailure?> _apply(Future<Result<LifePlan>> change) async {
    switch (await change) {
      case Ok(:final value):
        state = AsyncData(value);
        return null;
      case Err(:final failure):
        return failure;
    }
  }

  Future<AppFailure?> save(PlanGoalDraft draft, {String? id}) =>
      _apply(ref.read(savePlanGoalProvider).call(draft, id: id));

  Future<AppFailure?> remove(String id) =>
      _apply(ref.read(removePlanGoalProvider).call(id));

  /// Puts the goal at [from] in place [to]; the server answers the new plan.
  Future<AppFailure?> move(int from, int to) {
    final plan = state.requireValue;
    final ids = [for (final goal in plan.goals) goal.id];
    final moved = ids.removeAt(from);
    ids.insert(to, moved);
    return _apply(ref.read(reorderPlanProvider).call(ids));
  }

  Future<AppFailure?> saveSettings(PlanSettings settings) =>
      _apply(ref.read(savePlanSettingsProvider).call(settings));
}

final AsyncNotifierProvider<PlanController, LifePlan> planControllerProvider =
    AsyncNotifierProvider.autoDispose<PlanController, LifePlan>(
      PlanController.new,
      retry: noRetry,
    );
