import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/plan/data/plan_dtos.dart';
import 'package:cashdeck/features/plan/domain/life_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import '../plan_builders.dart';

void main() {
  test('a draft names its problem', () {
    const ok = PlanGoalDraft(
      kind: PlanGoalKind.purchase,
      name: 'Celular',
      price: Money(500_000),
      notBefore: YearMonth(2027, 1),
      by: YearMonth(2027, 6),
    );
    expect(ok.problem, isNull);
    expect(
      const PlanGoalDraft(kind: PlanGoalKind.purchase, name: ' ').problem,
      PlanGoalProblem.name,
    );
    expect(
      const PlanGoalDraft(kind: PlanGoalKind.yearly, name: 'Viagens').problem,
      PlanGoalProblem.amount,
    );
    expect(
      const PlanGoalDraft(
        kind: PlanGoalKind.milestone,
        name: 'Milhão',
        target: Money(1),
        notBefore: YearMonth(2028, 1),
        by: YearMonth(2027, 1),
      ).problem,
      isNull,
    );
    expect(
      const PlanGoalDraft(
        kind: PlanGoalKind.purchase,
        name: 'Filho',
        price: Money(1),
        notBefore: YearMonth(2028, 1),
        by: YearMonth(2027, 1),
      ).problem,
      PlanGoalProblem.window,
    );
    for (final installments in [0, maxPlanInstallments + 1]) {
      expect(
        PlanGoalDraft(
          kind: PlanGoalKind.purchase,
          name: 'Celular',
          price: const Money(1),
          payment: PlanPayment.card,
          installments: installments,
        ).problem,
        PlanGoalProblem.installments,
      );
    }
  });

  test('a draft starts from a goal and a milestone shows its progress', () {
    final draft = PlanGoalDraft.of(testPlanGoal);
    expect(draft.price, const Money(9_000_000));
    expect(draft.tradeIn, const Money(4_000_000));
    expect(draft.keepsValue, isTrue);
    expect(draft.by, const YearMonth(2028, 1));
    expect(draft.metric, MilestoneMetric.netWorth);
    expect(draft.yearly, const Money(0));
    expect(draft.payment, PlanPayment.card);
    expect(draft.installments, 10);
    expect(draft.goalId, 'goal-car');
    expect(draft.props, hasLength(17));
    expect(draft.linkedTo('goal-new').goalId, 'goal-new');
    expect(
      draft.linkedTo('goal-car'),
      draft,
      reason: 'linking keeps every other field',
    );

    const blank = PlanGoal(
      id: 'm',
      kind: PlanGoalKind.milestone,
      name: 'Milhão',
      status: PlanStatus.planned,
      cash: Money(0),
    );
    final fromBlank = PlanGoalDraft.of(blank);
    expect(fromBlank.price, const Money(0));
    expect(fromBlank.target, const Money(0));
    expect(blank.progress, 0);
    const half = PlanGoal(
      id: 'm',
      kind: PlanGoalKind.milestone,
      name: 'Milhão',
      status: PlanStatus.planned,
      cash: Money(0),
      metric: MilestoneMetric.invested,
      target: Money(200),
      current: Money(100),
    );
    expect(half.progress, 0.5);
    expect(testPlanGoal.props, hasLength(24));
  });

  test('settings name their problem and come from the plan', () {
    expect(
      const PlanSettings(reserveMonths: 6, yearlyYield: 6).problem,
      isNull,
    );
    expect(
      const PlanSettings(reserveMonths: 25, yearlyYield: 6).problem,
      PlanSettingsProblem.reserve,
    );
    expect(
      const PlanSettings(reserveMonths: -1, yearlyYield: 6).problem,
      PlanSettingsProblem.reserve,
    );
    expect(
      const PlanSettings(reserveMonths: 6, yearlyYield: 21).problem,
      PlanSettingsProblem.yield,
    );
    expect(
      const PlanSettings(reserveMonths: 6, yearlyYield: -1).problem,
      PlanSettingsProblem.yield,
    );
    expect(
      const PlanSettings(
        reserveMonths: 6,
        yearlyYield: 6,
        keepInvested: 101,
      ).problem,
      PlanSettingsProblem.keepInvested,
    );
    expect(
      const PlanSettings(
        reserveMonths: 6,
        yearlyYield: 6,
        keepInvested: -1,
      ).problem,
      PlanSettingsProblem.keepInvested,
    );
    const point = PlanPoint(
      month: YearMonth(2026, 10),
      netWorth: Money(1),
      invested: Money(1),
    );
    const delay = MilestoneDelay(milestoneId: 'm', name: 'Milhão', months: 2);
    LifePlan plan({required bool fromBudget}) => LifePlan(
      asOf: const YearMonth(2026, 10),
      monthlySavings: const Money(100),
      savingsFromBudget: fromBudget,
      monthlySpending: const Money(50),
      reserveMonths: 3,
      reserve: const Money(150),
      yearlyYield: 5,
      keepInvested: 0,
      netWorth: const Money(1),
      invested: const Money(1),
      yearlyProvision: const Money(0),
      free: const Money(100),
      goals: const [testPlanGoal],
      timeline: const [point],
    );
    expect(
      plan(fromBudget: true).settings,
      const PlanSettings(reserveMonths: 3, yearlyYield: 5),
    );
    expect(plan(fromBudget: false).settings.monthlySavings, const Money(100));
    expect(plan(fromBudget: true).props, hasLength(14));
    expect(point.props, hasLength(3));
    expect(delay.props, ['m', 'Milhão', 2]);
  });

  test('moving a goal keeps the rest of the plan', () {
    final plan = lifePlanFromJson(
      lifePlanJson(
        goals: [
          planGoalJson(),
          planGoalJson(id: 'g2', kind: 'YEARLY', month: null),
          planGoalJson(id: 'g3', kind: 'MILESTONE', metric: 'NET_WORTH'),
        ],
      ),
    );

    final moved = plan.moving(0, 2);

    expect([for (final goal in moved.goals) goal.id], ['g2', 'g3', 'g1']);
    expect(moved.moving(2, 0), plan);
    expect(moved.datesDiffer(plan), isFalse);
  });

  test('a goal in another month or status makes the dates differ', () {
    LifePlan planWith(String? month, String status) => lifePlanFromJson(
      lifePlanJson(
        goals: [planGoalJson(month: month, status: status)],
      ),
    );
    final plan = planWith('2027-05', 'PLANNED');

    expect(planWith('2027-06', 'PLANNED').datesDiffer(plan), isTrue);
    expect(planWith('2027-05', 'LATE').datesDiffer(plan), isTrue);
    expect(planWith('2027-05', 'PLANNED').datesDiffer(plan), isFalse);
  });

  test('an advice tells which goals move and a draft can wait', () {
    final advice = planAdviceFromJson(
      planAdviceJson(
        goals: [
          planAdviceGoalJson(notBefore: '2027-08'),
          planAdviceGoalJson(id: 'g2', proposedMonth: '2027-05', reason: null),
        ],
      ),
    );
    expect(advice.goals.map((goal) => goal.moves), [true, false]);
    expect(advice.goals.first.notBefore, const YearMonth(2027, 8));
    expect(advice.props, [null, 'O carro espera o marco.', advice.goals]);
    expect(advice.goals.last.props.first, 'g2');

    const draft = PlanGoalDraft(kind: PlanGoalKind.purchase, name: 'Carro');
    final waiting = draft.waitingUntil(const YearMonth(2028, 1));
    expect(waiting.notBefore, const YearMonth(2028, 1));
    expect(waiting.waitingUntil(null), draft);
  });
}
