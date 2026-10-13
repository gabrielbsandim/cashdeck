import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:equatable/equatable.dart';

enum PlanGoalKind { purchase, yearly, milestone }

enum PlanStatus { now, planned, late, outOfReach }

enum MilestoneMetric { netWorth, invested }

/// On the card, the cash leaves with the bills after the purchase.
enum PlanPayment { cash, card }

const maxPlanInstallments = 24;

/// How many months a goal pushes a milestone; null when it keeps the
/// milestone out of reach.
final class MilestoneDelay extends Equatable {
  const new({
    required this.milestoneId,
    required this.name,
    required this.months,
  });

  final String milestoneId;
  final String name;
  final int? months;

  @override
  List<Object?> get props => [milestoneId, name, months];
}

/// A goal of the plan and when it fits. Fields of the other kinds are null.
final class PlanGoal extends Equatable {
  const new({
    required this.id,
    required this.kind,
    required this.name,
    required this.status,
    required this.cash,
    this.icon,
    this.month,
    this.delays = const [],
    this.price,
    this.tradeIn,
    this.tradeInAssetId,
    this.tradeInAssetName,
    this.financed,
    this.monthlyCost,
    this.keepsValue = false,
    this.payment = PlanPayment.cash,
    this.installments = 1,
    this.goalId,
    this.notBefore,
    this.by,
    this.yearly,
    this.metric,
    this.target,
    this.current,
  });

  final String id;
  final PlanGoalKind kind;
  final String name;
  final String? icon;
  final PlanStatus status;

  /// When it happens or is reached.
  final YearMonth? month;

  /// What leaves savings: once for a purchase, every month for a yearly goal.
  final Money cash;
  final List<MilestoneDelay> delays;
  final Money? price;
  final Money? tradeIn;
  final String? tradeInAssetId;
  final String? tradeInAssetName;
  final Money? financed;
  final Money? monthlyCost;
  final bool keepsValue;
  final PlanPayment payment;
  final int installments;

  /// The caixinha saving for it.
  final String? goalId;
  final YearMonth? notBefore;
  final YearMonth? by;
  final Money? yearly;
  final MilestoneMetric? metric;
  final Money? target;

  /// Where a milestone stands today.
  final Money? current;

  /// 0 to 1, for a milestone's ring.
  double get progress {
    final target = this.target;
    final current = this.current;
    if (target == null || current == null || target.cents <= 0) return 0;
    return (current.cents / target.cents).clamp(0, 1).toDouble();
  }

  @override
  List<Object?> get props => [
    id,
    kind,
    name,
    icon,
    status,
    month,
    cash,
    delays,
    price,
    tradeIn,
    tradeInAssetId,
    tradeInAssetName,
    financed,
    monthlyCost,
    keepsValue,
    payment,
    installments,
    goalId,
    notBefore,
    by,
    yearly,
    metric,
    target,
    current,
  ];
}

final class PlanPoint extends Equatable {
  const new({
    required this.month,
    required this.netWorth,
    required this.invested,
  });

  final YearMonth month;
  final Money netWorth;
  final Money invested;

  @override
  List<Object?> get props => [month, netWorth, invested];
}

/// The family's goals laid out month by month from today's savings.
final class LifePlan extends Equatable {
  const new({
    required this.asOf,
    required this.monthlySavings,
    required this.savingsFromBudget,
    required this.monthlySpending,
    required this.reserveMonths,
    required this.reserve,
    required this.yearlyYield,
    required this.keepInvested,
    required this.netWorth,
    required this.invested,
    required this.yearlyProvision,
    required this.free,
    required this.goals,
    required this.timeline,
  });

  final YearMonth asOf;
  final Money monthlySavings;

  /// The savings follow the target of the monthly plan.
  final bool savingsFromBudget;
  final Money monthlySpending;
  final int reserveMonths;
  final Money reserve;

  /// Real yield a year, in percent.
  final double yearlyYield;

  /// Percent of the savings a month's purchases must leave invested.
  final int keepInvested;
  final Money netWorth;
  final Money invested;
  final Money yearlyProvision;

  /// The savings left once the yearly goals take their share.
  final Money free;
  final List<PlanGoal> goals;
  final List<PlanPoint> timeline;

  /// The same plan with the goal at [from] in place [to]. Months and statuses
  /// stay as they were until the server lays the new order out.
  LifePlan moving(int from, int to) {
    final ordered = [...goals];
    ordered.insert(to, ordered.removeAt(from));
    return LifePlan(
      asOf: asOf,
      monthlySavings: monthlySavings,
      savingsFromBudget: savingsFromBudget,
      monthlySpending: monthlySpending,
      reserveMonths: reserveMonths,
      reserve: reserve,
      yearlyYield: yearlyYield,
      keepInvested: keepInvested,
      netWorth: netWorth,
      invested: invested,
      yearlyProvision: yearlyProvision,
      free: free,
      goals: List.unmodifiable(ordered),
      timeline: timeline,
    );
  }

  PlanSettings get settings => PlanSettings(
    reserveMonths: reserveMonths,
    yearlyYield: yearlyYield,
    keepInvested: keepInvested,
    monthlySavings: savingsFromBudget ? null : monthlySavings,
  );

  @override
  List<Object?> get props => [
    asOf,
    monthlySavings,
    savingsFromBudget,
    monthlySpending,
    reserveMonths,
    reserve,
    yearlyYield,
    keepInvested,
    netWorth,
    invested,
    yearlyProvision,
    free,
    goals,
    timeline,
  ];
}

final class PlanSettings extends Equatable {
  const new({
    required this.reserveMonths,
    required this.yearlyYield,
    this.keepInvested = 0,
    this.monthlySavings,
  });

  final int reserveMonths;
  final double yearlyYield;
  final int keepInvested;

  /// Null follows the savings target of the monthly plan.
  final Money? monthlySavings;

  PlanSettingsProblem? get problem {
    if (reserveMonths < 0 || reserveMonths > 24) {
      return PlanSettingsProblem.reserve;
    }
    if (yearlyYield < 0 || yearlyYield > 20) return PlanSettingsProblem.yield;
    if (keepInvested < 0 || keepInvested > 100) {
      return PlanSettingsProblem.keepInvested;
    }
    return null;
  }

  @override
  List<Object?> get props => [
    reserveMonths,
    yearlyYield,
    keepInvested,
    monthlySavings,
  ];
}

enum PlanSettingsProblem { reserve, yield, keepInvested }

/// What the editor sends; only the fields of its kind are read.
final class PlanGoalDraft extends Equatable {
  const new({
    required this.kind,
    required this.name,
    this.icon,
    this.price = const Money(0),
    this.tradeIn = const Money(0),
    this.tradeInAssetId,
    this.financed = const Money(0),
    this.monthlyCost = const Money(0),
    this.keepsValue = false,
    this.payment = PlanPayment.cash,
    this.installments = 1,
    this.goalId,
    this.notBefore,
    this.by,
    this.yearly = const Money(0),
    this.metric = MilestoneMetric.netWorth,
    this.target = const Money(0),
  });

  factory of(PlanGoal goal) => PlanGoalDraft(
    kind: goal.kind,
    name: goal.name,
    icon: goal.icon,
    price: goal.price ?? const Money(0),
    tradeIn: goal.tradeIn ?? const Money(0),
    tradeInAssetId: goal.tradeInAssetId,
    financed: goal.financed ?? const Money(0),
    monthlyCost: goal.monthlyCost ?? const Money(0),
    keepsValue: goal.keepsValue,
    payment: goal.payment,
    installments: goal.installments,
    goalId: goal.goalId,
    notBefore: goal.notBefore,
    by: goal.by,
    yearly: goal.yearly ?? const Money(0),
    metric: goal.metric ?? MilestoneMetric.netWorth,
    target: goal.target ?? const Money(0),
  );

  final PlanGoalKind kind;
  final String name;
  final String? icon;
  final Money price;
  final Money tradeIn;
  final String? tradeInAssetId;
  final Money financed;
  final Money monthlyCost;
  final bool keepsValue;
  final PlanPayment payment;
  final int installments;
  final String? goalId;
  final YearMonth? notBefore;
  final YearMonth? by;
  final Money yearly;
  final MilestoneMetric metric;
  final Money target;

  /// The same goal saved by the caixinha [goalId].
  PlanGoalDraft linkedTo(String goalId) => PlanGoalDraft(
    kind: kind,
    name: name,
    icon: icon,
    price: price,
    tradeIn: tradeIn,
    tradeInAssetId: tradeInAssetId,
    financed: financed,
    monthlyCost: monthlyCost,
    keepsValue: keepsValue,
    payment: payment,
    installments: installments,
    goalId: goalId,
    notBefore: notBefore,
    by: by,
    yearly: yearly,
    metric: metric,
    target: target,
  );

  Money get _amount => switch (kind) {
    PlanGoalKind.purchase => price,
    PlanGoalKind.yearly => yearly,
    PlanGoalKind.milestone => target,
  };

  PlanGoalProblem? get problem {
    if (name.trim().isEmpty) return PlanGoalProblem.name;
    if (_amount.cents <= 0) return PlanGoalProblem.amount;
    if (installments < 1 || installments > maxPlanInstallments) {
      return PlanGoalProblem.installments;
    }
    final notBefore = this.notBefore;
    final by = this.by;
    final purchase = kind == PlanGoalKind.purchase;
    if (purchase &&
        notBefore != null &&
        by != null &&
        notBefore.compareTo(by) > 0) {
      return PlanGoalProblem.window;
    }
    return null;
  }

  @override
  List<Object?> get props => [
    kind,
    name,
    icon,
    price,
    tradeIn,
    tradeInAssetId,
    financed,
    monthlyCost,
    keepsValue,
    payment,
    installments,
    goalId,
    notBefore,
    by,
    yearly,
    metric,
    target,
  ];
}

enum PlanGoalProblem { name, amount, installments, window }

abstract interface class PlanRepository {
  Future<Result<LifePlan>> load();
  Future<Result<LifePlan>> create(PlanGoalDraft draft);
  Future<Result<LifePlan>> update(String id, PlanGoalDraft draft);
  Future<Result<LifePlan>> remove(String id);
  Future<Result<LifePlan>> reorder(List<String> ids);
  Future<Result<LifePlan>> saveSettings(PlanSettings settings);
}
