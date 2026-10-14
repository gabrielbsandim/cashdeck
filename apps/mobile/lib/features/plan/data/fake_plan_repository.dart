import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/plan/domain/life_plan.dart';

const _savings = 1_500_000;
const _spending = 2_000_000;
const _netWorth = 40_000_000;
const _invested = 15_000_000;

/// A fictional plan in memory. It spaces the goals out instead of running
/// the server's month by month search, enough for the screens offline.
final class FakePlanRepository implements PlanRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 300)});

  final Clock _clock;
  final Duration latency;
  var _settings = const PlanSettings(reserveMonths: 6, yearlyYield: 6);
  var _next = 0;
  late final List<(String, PlanGoalDraft)> _goals = [
    _seed(
      const PlanGoalDraft(
        kind: PlanGoalKind.yearly,
        name: 'Viagens do ano',
        icon: 'flight',
        yearly: Money(1_500_000),
      ),
    ),
    _seed(
      const PlanGoalDraft(
        kind: PlanGoalKind.purchase,
        name: 'Trocar de carro',
        icon: 'directions_car',
        price: Money(9_000_000),
        tradeIn: Money(4_000_000),
        keepsValue: true,
      ),
    ),
    _seed(
      const PlanGoalDraft(
        kind: PlanGoalKind.milestone,
        name: 'Patrimônio de 1 milhão',
        target: Money(100_000_000),
      ),
    ),
    _seed(
      const PlanGoalDraft(
        kind: PlanGoalKind.purchase,
        name: 'Notebook novo',
        icon: 'devices',
        price: Money(600_000),
        payment: PlanPayment.card,
        installments: 10,
        cashDiscount: 5,
        goalId: 'goal-laptop',
      ),
    ),
  ];

  (String, PlanGoalDraft) _seed(PlanGoalDraft draft) =>
      ('plan-${_next++}', draft);

  YearMonth get _month => YearMonth.of(CalendarDate.brazilToday(_clock.now()));

  PlanGoal _goal(String id, PlanGoalDraft draft, int turn, YearMonth asOf) {
    final cash = switch (draft.kind) {
      PlanGoalKind.purchase => Money(
        draft.price.cents - draft.tradeIn.cents - draft.financed.cents,
      ),
      PlanGoalKind.yearly => Money((draft.yearly.cents / 12).round()),
      PlanGoalKind.milestone => const Money(0),
    };
    final milestone = draft.kind == PlanGoalKind.milestone;
    return PlanGoal(
      id: id,
      kind: draft.kind,
      name: draft.name.trim(),
      icon: draft.icon,
      status: PlanStatus.planned,
      month: draft.kind == PlanGoalKind.yearly ? null : asOf.add(6 * turn),
      cash: cash,
      price: draft.kind == PlanGoalKind.purchase ? draft.price : null,
      tradeIn: draft.kind == PlanGoalKind.purchase ? draft.tradeIn : null,
      financed: draft.kind == PlanGoalKind.purchase ? draft.financed : null,
      monthlyCost: draft.kind == PlanGoalKind.purchase
          ? draft.monthlyCost
          : null,
      keepsValue: draft.keepsValue,
      payment: draft.payment,
      installments: draft.installments,
      cashDiscount: draft.cashDiscount,
      goalId: draft.goalId,
      notBefore: draft.notBefore,
      by: draft.by,
      yearly: draft.kind == PlanGoalKind.yearly ? draft.yearly : null,
      metric: milestone ? draft.metric : null,
      target: milestone ? draft.target : null,
      current: milestone
          ? Money(
              draft.metric == MilestoneMetric.netWorth ? _netWorth : _invested,
            )
          : null,
    );
  }

  LifePlan _plan() {
    final asOf = _month;
    final provision = _goals.fold<int>(
      0,
      (total, goal) => goal.$2.kind == PlanGoalKind.yearly
          ? total + (goal.$2.yearly.cents / 12).round()
          : total,
    );
    final savings = _settings.monthlySavings?.cents ?? _savings;
    return LifePlan(
      asOf: asOf,
      monthlySavings: Money(savings),
      savingsFromBudget: _settings.monthlySavings == null,
      monthlySpending: const Money(_spending),
      reserveMonths: _settings.reserveMonths,
      reserve: Money(_settings.reserveMonths * _spending),
      yearlyYield: _settings.yearlyYield,
      keepInvested: _settings.keepInvested,
      netWorth: const Money(_netWorth),
      invested: const Money(_invested),
      yearlyProvision: Money(provision),
      free: Money(savings - provision),
      goals: [
        for (final (index, (id, draft)) in _goals.indexed)
          _goal(id, draft, index + 1, asOf),
      ],
      timeline: [
        for (var year = 0; year <= 10; year++)
          PlanPoint(
            month: asOf.add(year * 12),
            netWorth: Money(_netWorth + year * 12 * (savings - provision)),
            invested: Money(_invested + year * 12 * (savings - provision)),
          ),
      ],
    );
  }

  Future<Result<LifePlan>> _answer() async {
    await Future<void>.delayed(latency);
    return Ok(_plan());
  }

  int _indexOf(String id) => _goals.indexWhere((goal) => goal.$1 == id);

  @override
  Future<Result<LifePlan>> load() => _answer();

  @override
  Future<Result<LifePlan>> create(PlanGoalDraft draft) {
    _goals.add(_seed(draft));
    return _answer();
  }

  @override
  Future<Result<LifePlan>> update(String id, PlanGoalDraft draft) {
    final index = _indexOf(id);
    if (index < 0) return Future.value(const Err(NotFoundFailure()));
    _goals[index] = (id, draft);
    return _answer();
  }

  @override
  Future<Result<LifePlan>> remove(String id) {
    final index = _indexOf(id);
    if (index < 0) return Future.value(const Err(NotFoundFailure()));
    _goals.removeAt(index);
    return _answer();
  }

  @override
  Future<Result<LifePlan>> reorder(List<String> ids) {
    int rank((String, PlanGoalDraft) goal) {
      final index = ids.indexOf(goal.$1);
      return index < 0 ? ids.length : index;
    }

    _goals.sort((a, b) => rank(a).compareTo(rank(b)));
    return _answer();
  }

  /// Offline the advice puts the cheaper purchases first, or the goal
  /// [goalId] last, so the screens have a change to show.
  @override
  Future<Result<PlanAdvice>> advise({String? goalId}) async {
    await Future<void>.delayed(latency);
    final before = _plan();
    final target = goalId == null ? null : _indexOf(goalId);
    if (target == -1) return const Err(NotFoundFailure());
    final ordered = [..._goals];
    if (target == null) {
      int priceOf((String, PlanGoalDraft) goal) =>
          goal.$2.kind == PlanGoalKind.purchase ? goal.$2.price.cents : 0;
      ordered.sort((a, b) => priceOf(a).compareTo(priceOf(b)));
    } else {
      ordered.add(ordered.removeAt(target));
    }
    final now = {for (final goal in before.goals) goal.id: goal};
    final asOf = before.asOf;
    return Ok(
      PlanAdvice(
        goalId: goalId,
        summary: 'Sugestão de exemplo, feita sem conexão.',
        goals: [
          for (final (index, (id, draft)) in ordered.indexed)
            PlanAdviceGoal(
              id: id,
              kind: draft.kind,
              name: draft.name,
              notBefore: draft.notBefore,
              reason: goalId == null || goalId == id
                  ? 'Exemplo sem conexão.'
                  : null,
              month: now[id]!.month,
              status: now[id]!.status,
              proposedMonth: _goal(id, draft, index + 1, asOf).month,
              proposedStatus: PlanStatus.planned,
              payment: _payment(draft),
            ),
        ],
      ),
    );
  }

  /// A rough stand-in: the installments lose 4% of their worth meanwhile.
  PlanPaymentAdvice? _payment(PlanGoalDraft draft) {
    if (draft.kind != PlanGoalKind.purchase || draft.installments < 2) {
      return null;
    }
    final price = draft.price.cents;
    final cash = (price * (100 - draft.cashDiscount) / 100).round();
    final card = (price * 0.96).round();
    return PlanPaymentAdvice(
      installments: draft.installments,
      cash: Money(cash),
      cardToday: Money(card),
      better: cash <= card ? PlanPayment.cash : PlanPayment.card,
      gain: Money((card - cash).abs()),
      breakEvenPercent: 4,
    );
  }

  @override
  Future<Result<LifePlan>> arrange(PlanAdvice advice) {
    final drafts = {for (final (id, draft) in _goals) id: draft};
    _goals
      ..clear()
      ..addAll([
        for (final goal in advice.goals)
          if (drafts[goal.id] case final draft?)
            (
              goal.id,
              draft.kind == PlanGoalKind.purchase
                  ? draft.waitingUntil(goal.notBefore)
                  : draft,
            ),
      ]);
    return _answer();
  }

  @override
  Future<Result<LifePlan>> saveSettings(PlanSettings settings) {
    _settings = settings;
    return _answer();
  }
}
