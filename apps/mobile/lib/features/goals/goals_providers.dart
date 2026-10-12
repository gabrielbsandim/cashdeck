import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/goals/application/goals_use_cases.dart';
import 'package:cashdeck/features/goals/data/api_goals_repository.dart';
import 'package:cashdeck/features/goals/data/fake_goals_repository.dart';
import 'package:cashdeck/features/goals/domain/goal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final goalsRepositoryProvider = Provider<GoalsRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeGoalsRepository(ref.watch(clockProvider)),
    Backend.api => ApiGoalsRepository(ref.watch(dioProvider)),
  };
});

final listGoalsProvider = Provider<ListGoals>(
  (ref) => ListGoals(ref.watch(goalsRepositoryProvider)),
);

final getGoalProvider = Provider<GetGoal>(
  (ref) => GetGoal(ref.watch(goalsRepositoryProvider)),
);

final saveGoalProvider = Provider<SaveGoal>(
  (ref) => SaveGoal(ref.watch(goalsRepositoryProvider)),
);

final archiveGoalProvider = Provider<ArchiveGoal>(
  (ref) => ArchiveGoal(ref.watch(goalsRepositoryProvider)),
);

final deleteGoalProvider = Provider<DeleteGoal>(
  (ref) => DeleteGoal(ref.watch(goalsRepositoryProvider)),
);

final contributeToGoalProvider = Provider<ContributeToGoal>(
  (ref) => ContributeToGoal(ref.watch(goalsRepositoryProvider)),
);

final removeContributionProvider = Provider<RemoveContribution>(
  (ref) => RemoveContribution(ref.watch(goalsRepositoryProvider)),
);
