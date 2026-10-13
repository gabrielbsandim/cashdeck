import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/plan/data/api_plan_repository.dart';
import 'package:cashdeck/features/plan/data/fake_plan_repository.dart';
import 'package:cashdeck/features/plan/data/plan_dtos.dart';
import 'package:cashdeck/features/plan/domain/life_plan.dart';
import 'package:cashdeck/features/plan/plan_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';
import '../../../support/stub_http_adapter.dart';
import '../plan_builders.dart';

T _ok<T>(Result<T> result) => (result as Ok<T>).value;

const _car = PlanGoalDraft(
  kind: PlanGoalKind.purchase,
  name: ' Carro ',
  price: Money(9_000_000),
  tradeIn: Money(4_000_000),
  keepsValue: true,
  notBefore: YearMonth(2027, 1),
);

void main() {
  group('dtos', () {
    test('read a plan with every kind of goal', () {
      final plan = lifePlanFromJson(
        lifePlanJson(
          goals: [
            planGoalJson(
              delays: [
                {'milestoneId': 'm', 'name': 'Milhão', 'months': 3},
                {'milestoneId': 'm', 'name': 'Milhão', 'months': null},
              ],
            ),
            planGoalJson(id: 'y', kind: 'YEARLY', month: null),
            planGoalJson(
              id: 'm',
              kind: 'MILESTONE',
              status: 'OUT_OF_REACH',
              month: null,
              metric: 'INVESTED',
            ),
          ],
        ),
      );
      expect(plan.asOf, const YearMonth(2026, 10));
      expect(plan.yearlyYield, 5.5);
      expect(plan.keepInvested, 50);
      expect(planGoalFromJson(planGoalJson()), testPlanGoal);
      expect(plan.goals.first.delays.last.months, isNull);
      expect(plan.goals[1].yearly, const Money(1_200_000));
      expect(plan.goals[2].metric, MilestoneMetric.invested);
      expect(plan.goals[2].status, PlanStatus.outOfReach);
      expect(plan.goals[1].payment, PlanPayment.cash);
      expect(plan.goals[1].installments, 1);
      expect(plan.timeline.last.netWorth, const Money(84_000_000));
    });

    test('a yield that is not a number fails the read', () {
      expect(
        () => lifePlanFromJson({...lifePlanJson(), 'yearlyYield': '5'}),
        throwsFormatException,
      );
    });

    test('write each kind with only its fields', () {
      expect(planGoalToJson(_car), {
        'kind': 'PURCHASE',
        'name': 'Carro',
        'icon': null,
        'price': 9_000_000,
        'tradeIn': 4_000_000,
        'tradeInAssetId': null,
        'financed': 0,
        'monthlyCost': 0,
        'keepsValue': true,
        'payment': 'CASH',
        'installments': 1,
        'goalId': null,
        'notBefore': '2027-01',
        'by': null,
      });
      expect(
        planGoalToJson(
          const PlanGoalDraft(
            kind: PlanGoalKind.yearly,
            name: 'Viagens',
            yearly: Money(1_700_000),
          ),
        ),
        {
          'kind': 'YEARLY',
          'name': 'Viagens',
          'icon': null,
          'yearly': 1_700_000,
        },
      );
      expect(
        planGoalToJson(
          const PlanGoalDraft(
            kind: PlanGoalKind.milestone,
            name: 'Milhão',
            metric: MilestoneMetric.invested,
            target: Money(100_000_000),
            by: YearMonth(2029, 12),
          ),
        ),
        {
          'kind': 'MILESTONE',
          'name': 'Milhão',
          'icon': null,
          'metric': 'INVESTED',
          'target': 100_000_000,
          'by': '2029-12',
        },
      );
      expect(
        planSettingsToJson(
          const PlanSettings(
            reserveMonths: 6,
            yearlyYield: 5.5,
            monthlySavings: Money(100),
          ),
        ),
        {
          'reserveMonths': 6,
          'yearlyYield': 5.5,
          'keepInvested': 0,
          'monthlySavings': 100,
        },
      );
    });
  });

  test('the api calls each route and reads the plan back', () async {
    final dio = stubDio(
      (options) => switch ((options.method, options.path)) {
        ('GET', '/api/v1/plan') ||
        ('POST', '/api/v1/plan/goals') ||
        ('PUT', '/api/v1/plan/goals/g1') ||
        ('DELETE', '/api/v1/plan/goals/g1') ||
        ('PUT', '/api/v1/plan/order') ||
        ('PUT', '/api/v1/plan/arrangement') ||
        (
          'PUT',
          '/api/v1/plan/settings',
        ) => StubResponse(200, {'data': lifePlanJson()}),
        ('POST', '/api/v1/plan/advice') => StubResponse(200, {
          'data': planAdviceJson(goalId: 'g1'),
        }),
        _ => const StubResponse(404),
      },
    );
    final repository = ApiPlanRepository(dio);
    expect(_ok(await repository.load()).goals.single.id, 'g1');
    expect(await repository.create(_car), isA<Ok<LifePlan>>());
    expect(await repository.update('g1', _car), isA<Ok<LifePlan>>());
    expect(await repository.remove('g1'), isA<Ok<LifePlan>>());
    expect(await repository.reorder(['g1']), isA<Ok<LifePlan>>());
    expect(
      await repository.saveSettings(
        const PlanSettings(reserveMonths: 3, yearlyYield: 4),
      ),
      isA<Ok<LifePlan>>(),
    );
    final advice = _ok(await repository.advise(goalId: 'g1'));
    expect(advice.goalId, 'g1');
    expect(await repository.arrange(advice), isA<Ok<LifePlan>>());
    final requests = adapterOf(dio).requests;
    expect(requests[4].data, {
      'ids': ['g1'],
    });
    expect((requests[5].data as Map)['monthlySavings'], isNull);
    expect(requests[6].data, {'goalId': 'g1'});
    expect(requests[7].data, {
      'goals': [
        {'id': 'g1', 'notBefore': null},
      ],
    });
  });

  group('fake', () {
    FakePlanRepository fake() =>
        FakePlanRepository(FixedClock(testNow), latency: Duration.zero);

    test('seeds a plan and spaces the goals out', () async {
      final plan = _ok(await fake().load());
      expect(plan.asOf, const YearMonth(2026, 10));
      expect(plan.goals.map((goal) => goal.kind), [
        PlanGoalKind.yearly,
        PlanGoalKind.purchase,
        PlanGoalKind.milestone,
        PlanGoalKind.purchase,
      ]);
      expect(plan.goals[3].payment, PlanPayment.card);
      expect(plan.goals[3].goalId, 'goal-laptop');
      expect(plan.goals[0].month, isNull);
      expect(plan.goals[0].cash, const Money(125_000));
      expect(plan.goals[1].month, const YearMonth(2027, 10));
      expect(plan.goals[1].cash, const Money(5_000_000));
      expect(plan.goals[2].current, const Money(40_000_000));
      expect(plan.free, const Money(1_375_000));
      expect(plan.timeline, hasLength(11));
    });

    test('adds, edits, reorders, removes and keeps the settings', () async {
      final repository = fake();
      final added = _ok(
        await repository.create(
          const PlanGoalDraft(
            kind: PlanGoalKind.milestone,
            name: 'Investido',
            metric: MilestoneMetric.invested,
            target: Money(1),
          ),
        ),
      );
      final id = added.goals.last.id;
      expect(added.goals.last.current, const Money(15_000_000));
      final edited = _ok(await repository.update(id, _car));
      expect(edited.goals.last.name, 'Carro');
      final reordered = _ok(await repository.reorder([id]));
      expect(reordered.goals.first.id, id);
      final removed = _ok(await repository.remove(id));
      expect(removed.goals, hasLength(4));
      expect(
        (await repository.update(id, _car) as Err).failure,
        const NotFoundFailure(),
      );
      expect(
        (await repository.remove(id) as Err).failure,
        const NotFoundFailure(),
      );
      final custom = _ok(
        await repository.saveSettings(
          const PlanSettings(
            reserveMonths: 2,
            yearlyYield: 4,
            monthlySavings: Money(1_000_000),
          ),
        ),
      );
      expect(custom.savingsFromBudget, isFalse);
      expect(custom.reserve, const Money(4_000_000));
    });

    test('advises the cheaper purchases first, or one goal last', () async {
      final repository = fake();
      final ids = _ok(await repository.load()).goals
          .map((goal) => goal.id)
          .toList();

      final whole = _ok(await repository.advise());
      expect(whole.goalId, isNull);
      expect(whole.goals.map((goal) => goal.kind), [
        PlanGoalKind.yearly,
        PlanGoalKind.milestone,
        PlanGoalKind.purchase,
        PlanGoalKind.purchase,
      ]);
      expect(whole.goals.every((goal) => goal.reason != null), isTrue);

      final one = _ok(await repository.advise(goalId: ids[1]));
      expect(one.goals.last.id, ids[1]);
      expect(one.goals.last.reason, isNotNull);
      expect(one.goals.first.reason, isNull);
      expect(
        (await repository.advise(goalId: 'missing') as Err).failure,
        const NotFoundFailure(),
      );

      final waiting = PlanAdvice(
        summary: '',
        goals: [
          for (final goal in one.goals)
            PlanAdviceGoal(
              id: goal.id,
              kind: goal.kind,
              name: goal.name,
              notBefore: goal.kind == PlanGoalKind.purchase
                  ? const YearMonth(2028, 3)
                  : null,
              status: goal.status,
              proposedStatus: goal.proposedStatus,
            ),
        ],
      );
      final arranged = _ok(await repository.arrange(waiting));
      expect(arranged.goals.last.id, ids[1]);
      expect(arranged.goals.last.notBefore, const YearMonth(2028, 3));
      expect(arranged.goals.first.notBefore, isNull);
    });
  });

  test('the backend picks the repository', () {
    for (final (backend, type) in [
      (Backend.fake, FakePlanRepository),
      (Backend.api, ApiPlanRepository),
    ]) {
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(
            AppConfig(backend: backend, apiBaseUrl: 'https://api.test'),
          ),
          clockProvider.overrideWithValue(FixedClock(testNow)),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(planRepositoryProvider).runtimeType, type);
      expect(container.read(loadPlanProvider), isNotNull);
      expect(container.read(savePlanGoalProvider), isNotNull);
      expect(container.read(removePlanGoalProvider), isNotNull);
      expect(container.read(reorderPlanProvider), isNotNull);
      expect(container.read(advisePlanProvider), isNotNull);
      expect(container.read(applyPlanAdviceProvider), isNotNull);
      expect(container.read(savePlanSettingsProvider), isNotNull);
    }
  });
}
