import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/plan/domain/life_plan.dart';
import 'package:cashdeck/features/plan/plan_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The plan, replaced by the one the server answers after every change.
class PlanController extends AsyncNotifier<LifePlan> {
  var _moves = 0;

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

  /// Puts the goal at [from] in place [to] at once, so the dropped card
  /// stays where it fell while the server lays the plan out again.
  Future<AppFailure?> move(int from, int to) async {
    final before = state.requireValue;
    final moved = before.moving(from, to);
    state = AsyncData(moved);
    _moves++;
    final result = await ref.read(reorderPlanProvider).call([
      for (final goal in moved.goals) goal.id,
    ]);
    _moves--;
    final (plan, failure) = switch (result) {
      Ok(:final value) => (value, null),
      Err(:final failure) => (before, failure),
    };
    // A later drag already sent the whole order; its answer is the one to show.
    if (!ref.mounted || _moves > 0) return failure;
    state = AsyncData(plan);
    return failure;
  }

  Future<AppFailure?> applyAdvice(PlanAdvice advice) =>
      _apply(ref.read(applyPlanAdviceProvider).call(advice));

  Future<AppFailure?> saveSettings(PlanSettings settings) =>
      _apply(ref.read(savePlanSettingsProvider).call(settings));
}

final AsyncNotifierProvider<PlanController, LifePlan> planControllerProvider =
    AsyncNotifierProvider.autoDispose<PlanController, LifePlan>(
      PlanController.new,
      retry: noRetry,
    );
