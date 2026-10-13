import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/plan/application/plan_use_cases.dart';
import 'package:cashdeck/features/plan/data/api_plan_repository.dart';
import 'package:cashdeck/features/plan/data/fake_plan_repository.dart';
import 'package:cashdeck/features/plan/domain/life_plan.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final planRepositoryProvider = Provider<PlanRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakePlanRepository(ref.watch(clockProvider)),
    Backend.api => ApiPlanRepository(ref.watch(dioProvider)),
  };
});

final loadPlanProvider = Provider<LoadPlan>(
  (ref) => LoadPlan(ref.watch(planRepositoryProvider)),
);

final savePlanGoalProvider = Provider<SavePlanGoal>(
  (ref) => SavePlanGoal(ref.watch(planRepositoryProvider)),
);

final removePlanGoalProvider = Provider<RemovePlanGoal>(
  (ref) => RemovePlanGoal(ref.watch(planRepositoryProvider)),
);

final reorderPlanProvider = Provider<ReorderPlan>(
  (ref) => ReorderPlan(ref.watch(planRepositoryProvider)),
);

final savePlanSettingsProvider = Provider<SavePlanSettings>(
  (ref) => SavePlanSettings(ref.watch(planRepositoryProvider)),
);
