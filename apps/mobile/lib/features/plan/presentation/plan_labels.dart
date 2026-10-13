import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/goals/presentation/goal_appearance.dart';
import 'package:cashdeck/features/insights/presentation/insights_labels.dart';
import 'package:cashdeck/features/plan/domain/life_plan.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

String planMonth(AppLocalizations l10n, YearMonth month) =>
    monthTitle(l10n, month);

/// When the goal happens, in one line.
String planWhenLine(AppLocalizations l10n, PlanGoal goal, {bool hide = false}) {
  if (goal.kind == PlanGoalKind.yearly) {
    return l10n.planYearlyLine(MoneyFormat.whole(goal.cash, hide: hide));
  }
  final month = goal.month;
  if (month == null) return l10n.planOutOfReach;
  final label = planMonth(l10n, month);
  final milestone = goal.kind == PlanGoalKind.milestone;
  return switch (goal.status) {
    PlanStatus.now => milestone ? l10n.planMilestoneNow : l10n.planPurchaseNow,
    PlanStatus.late =>
      milestone ? l10n.planMilestoneLate(label) : l10n.planPurchaseLate(label),
    _ => milestone ? l10n.planMilestoneOn(label) : l10n.planPurchaseOn(label),
  };
}

/// What it takes from or adds to savings, or where a milestone stands.
String? planAmountLine(
  AppLocalizations l10n,
  PlanGoal goal, {
  bool hide = false,
}) {
  switch (goal.kind) {
    case PlanGoalKind.yearly:
      return null;
    case PlanGoalKind.milestone:
      final current = goal.current;
      final target = goal.target;
      if (current == null || target == null) return null;
      return l10n.planMilestoneProgress(
        MoneyFormat.whole(current, hide: hide),
        MoneyFormat.whole(target, hide: hide),
      );
    case PlanGoalKind.purchase:
      final cash = goal.cash;
      if (cash.cents < 0) {
        return l10n.planCashIn(MoneyFormat.whole(cash.abs, hide: hide));
      }
      return l10n.planCashOut(MoneyFormat.whole(cash, hide: hide));
  }
}

String planDelayLine(AppLocalizations l10n, MilestoneDelay delay) {
  final months = delay.months;
  if (months == null) return l10n.planBlocks(delay.name);
  return l10n.planDelay(delay.name, months);
}

MoneyTone planStatusTone(PlanStatus status) => switch (status) {
  PlanStatus.now => MoneyTone.paid,
  PlanStatus.planned => MoneyTone.scheduled,
  PlanStatus.late => MoneyTone.pending,
  PlanStatus.outOfReach => MoneyTone.failed,
};

IconData planKindIcon(PlanGoalKind kind) => switch (kind) {
  PlanGoalKind.purchase => Symbols.shopping_bag_rounded,
  PlanGoalKind.yearly => Symbols.event_repeat_rounded,
  PlanGoalKind.milestone => Symbols.flag_rounded,
};

String planKindLabel(AppLocalizations l10n, PlanGoalKind kind) =>
    switch (kind) {
      PlanGoalKind.purchase => l10n.planKindPurchase,
      PlanGoalKind.yearly => l10n.planKindYearly,
      PlanGoalKind.milestone => l10n.planKindMilestone,
    };

String planProblemMessage(AppLocalizations l10n, PlanGoalProblem problem) =>
    switch (problem) {
      PlanGoalProblem.name => l10n.planNameMissing,
      PlanGoalProblem.amount => l10n.planAmountMissing,
      PlanGoalProblem.installments => l10n.planInstallmentsInvalid,
      PlanGoalProblem.window => l10n.planWindowInvalid,
    };

IconData planGoalIcon(PlanGoal goal) =>
    goalIcons[goal.icon] ?? planKindIcon(goal.kind);

String planStatusLabel(AppLocalizations l10n, PlanStatus status) =>
    switch (status) {
      PlanStatus.now => l10n.planStatusNow,
      PlanStatus.planned => l10n.planStatusPlanned,
      PlanStatus.late => l10n.planStatusLate,
      PlanStatus.outOfReach => l10n.planStatusOutOfReach,
    };

/// A percent the way it is typed: `6` or `5,5`.
String planRate(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString().replaceAll('.', ',');
