import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/plan/application/plan_use_cases.dart';
import 'package:cashdeck/features/plan/data/plan_dtos.dart';
import 'package:cashdeck/features/plan/domain/life_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../plan_builders.dart';

class MockPlanRepository extends Mock implements PlanRepository;

const _phone = PlanGoalDraft(
  kind: PlanGoalKind.purchase,
  name: 'Celular',
  price: Money(500_000),
);

const _settings = PlanSettings(reserveMonths: 6, yearlyYield: 6);

void main() {
  setUpAll(() {
    registerFallbackValue(_phone);
    registerFallbackValue(_settings);
  });

  test('every use case reaches the repository', () async {
    final repository = MockPlanRepository();
    final plan = Ok(lifePlanFromJson(lifePlanJson()));
    when(repository.load).thenAnswer((_) async => plan);
    when(() => repository.create(any())).thenAnswer((_) async => plan);
    when(() => repository.update(any(), any())).thenAnswer((_) async => plan);
    when(() => repository.remove(any())).thenAnswer((_) async => plan);
    when(() => repository.reorder(any())).thenAnswer((_) async => plan);
    when(() => repository.saveSettings(any())).thenAnswer((_) async => plan);
    final advice = Ok(planAdviceFromJson(planAdviceJson()));
    when(() => repository.advise(goalId: any(named: 'goalId')))
        .thenAnswer((_) async => advice);
    when(() => repository.arrange(advice.value)).thenAnswer((_) async => plan);

    expect(await LoadPlan(repository).call(), plan);
    expect(await SavePlanGoal(repository).call(_phone), plan);
    expect(await SavePlanGoal(repository).call(_phone, id: 'g1'), plan);
    expect(await RemovePlanGoal(repository).call('g1'), plan);
    expect(await ReorderPlan(repository).call(['g1']), plan);
    expect(await SavePlanSettings(repository).call(_settings), plan);
    expect(await AdvisePlan(repository).call(goalId: 'g1'), advice);
    expect(await ApplyPlanAdvice(repository).call(advice.value), plan);
    verify(() => repository.update('g1', _phone)).called(1);
    verify(() => repository.advise(goalId: 'g1')).called(1);
  });

  test('a draft or settings with a problem never leave the app', () async {
    final repository = MockPlanRepository();
    const nameless = PlanGoalDraft(kind: PlanGoalKind.yearly, name: '');
    expect(
      (await SavePlanGoal(repository).call(nameless) as Err).failure,
      isA<UnexpectedFailure>(),
    );
    expect(
      (await SavePlanSettings(repository).call(
        const PlanSettings(reserveMonths: 30, yearlyYield: 6),
      ) as Err).failure,
      isA<UnexpectedFailure>(),
    );
    verifyZeroInteractions(repository);
  });
}
