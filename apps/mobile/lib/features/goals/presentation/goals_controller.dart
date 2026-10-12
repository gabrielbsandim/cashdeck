import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/goals/domain/goal.dart';
import 'package:cashdeck/features/goals/goals_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

/// What a change to a goal led to: the failure, or whether it just reached
/// its target and deserves a celebration.
typedef GoalOutcome = ({AppFailure? failure, Goal? goal, bool reached});

GoalOutcome _outcome(Result<Goal> result, Goal? before) => switch (result) {
  Ok(:final value) => (
    failure: null,
    goal: value,
    reached: justReached(before, value),
  ),
  Err(:final failure) => (failure: failure, goal: null, reached: false),
};

CalendarDate _today(Ref ref) =>
    CalendarDate.brazilToday(ref.read(clockProvider).now());

class GoalsController extends AsyncNotifier<List<Goal>> {
  @override
  Future<List<Goal>> build() async =>
      (await ref.watch(listGoalsProvider).call()).orThrow;

  Future<GoalOutcome> create(GoalDraft draft) async {
    final result = await ref
        .read(saveGoalProvider)
        .call(draft, today: _today(ref));
    final outcome = _outcome(result, null);
    final goal = outcome.goal;
    if (goal != null) {
      state = AsyncData([...?state.value, goal]);
    }
    return outcome;
  }
}

final AsyncNotifierProvider<GoalsController, List<Goal>>
goalsControllerProvider =
    AsyncNotifierProvider.autoDispose<GoalsController, List<Goal>>(
      GoalsController.new,
      retry: noRetry,
    );

class GoalDetailController extends AsyncNotifier<Goal> {
  new(this.id);

  final String id;

  @override
  Future<Goal> build() async =>
      (await ref.watch(getGoalProvider).call(id)).orThrow;

  Future<GoalOutcome> _apply(Future<Result<Goal>> change) async {
    final before = state.value;
    final outcome = _outcome(await change, before);
    final goal = outcome.goal;
    if (goal == null) return outcome;
    state = AsyncData(goal);
    ref.invalidate(goalsControllerProvider);
    return outcome;
  }

  Future<GoalOutcome> save(GoalDraft draft) => _apply(
    ref.read(saveGoalProvider).call(draft, today: _today(ref), id: id),
  );

  Future<GoalOutcome> contribute(Money amount, {String? note}) =>
      _apply(ref.read(contributeToGoalProvider).call(id, amount, note: note));

  Future<GoalOutcome> removeContribution(String contributionId) =>
      _apply(ref.read(removeContributionProvider).call(id, contributionId));

  Future<GoalOutcome> archive() =>
      _apply(ref.read(archiveGoalProvider).call(id));

  Future<AppFailure?> delete() async {
    final result = await ref.read(deleteGoalProvider).call(id);
    if (result case Err(:final failure)) return failure;
    ref.invalidate(goalsControllerProvider);
    return null;
  }
}

final AsyncNotifierProviderFamily<GoalDetailController, Goal, String>
goalDetailControllerProvider = AsyncNotifierProvider.autoDispose
    .family<GoalDetailController, Goal, String>(
      GoalDetailController.new,
      retry: noRetry,
    );
