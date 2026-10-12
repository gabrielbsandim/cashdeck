import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/goals/domain/goal.dart';
import 'package:cashdeck/features/insights/presentation/insights_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';

String goalStatusLabel(AppLocalizations l10n, GoalStatus status) =>
    switch (status) {
      GoalStatus.done => l10n.goalStatusDone,
      GoalStatus.onTrack => l10n.goalStatusOnTrack,
      GoalStatus.behind => l10n.goalStatusBehind,
    };

MoneyTone goalStatusTone(GoalStatus status) => switch (status) {
  GoalStatus.done => MoneyTone.paid,
  GoalStatus.onTrack => MoneyTone.scheduled,
  GoalStatus.behind => MoneyTone.pending,
};

/// The ring colour: the brand while on track, a warning when behind.
Color goalColor(BuildContext context, GoalStatus status) => switch (status) {
  GoalStatus.done => context.money.paid,
  GoalStatus.onTrack => context.palette.primary,
  GoalStatus.behind => context.money.pending,
};

String goalProblemMessage(AppLocalizations l10n, GoalProblem problem) =>
    switch (problem) {
      GoalProblem.nameMissing => l10n.goalNameMissing,
      GoalProblem.targetMissing => l10n.goalTargetMissing,
      GoalProblem.deadlinePast => l10n.goalDeadlinePast,
    };

/// `R$ 1.200 de R$ 3.000`.
String goalProgressLine(
  AppLocalizations l10n,
  Goal goal, {
  bool hide = false,
}) => l10n.goalProgress(
  MoneyFormat.whole(goal.saved, hide: hide),
  MoneyFormat.whole(goal.target, hide: hide),
);

/// `Outubro 2027`, the month the projection lands on.
String goalMonth(AppLocalizations l10n, CalendarDate day) =>
    monthTitle(l10n, YearMonth.of(day));

/// What the pace says about reaching the target, in one sentence.
String goalProjectionLine(
  AppLocalizations l10n,
  Goal goal, {
  bool hide = false,
}) {
  if (goal.isDone) return l10n.goalProjectionDone;
  final pace = goal.monthlyPace;
  final projected = goal.projectedOn;
  if (pace == null || projected == null) return l10n.goalProjectionUnknown;
  return l10n.goalProjection(
    MoneyFormat.whole(pace, hide: hide),
    goalMonth(l10n, projected),
  );
}

/// How much a month needs to meet the deadline, or null without one.
String? goalRequiredLine(
  AppLocalizations l10n,
  Goal goal, {
  bool hide = false,
}) {
  final required = goal.requiredMonthly;
  final deadline = goal.deadline;
  if (goal.isDone || required == null || deadline == null) return null;
  return l10n.goalRequired(
    MoneyFormat.whole(required, hide: hide),
    deadline.display,
  );
}
