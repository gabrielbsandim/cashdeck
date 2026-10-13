import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/charts/cd_line_chart.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/plan/domain/life_plan.dart';
import 'package:cashdeck/features/plan/presentation/plan_controller.dart';
import 'package:cashdeck/features/plan/presentation/plan_goal_editor.dart';
import 'package:cashdeck/features/plan/presentation/plan_labels.dart';
import 'package:cashdeck/features/plan/presentation/plan_settings_sheet.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The life goals in their order, each with the month it fits and what it
/// costs the milestones.
class PlanScreen extends ConsumerWidget {
  const new({super.key});

  static const addKey = Key('plan-add');
  static const settingsKey = Key('plan-settings');
  static const summaryKey = Key('plan-summary');

  static Key tileKey(String id) => Key('plan-goal-$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final plan = ref.watch(planControllerProvider);
    final value = plan.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.planTitle),
        actions: [
          if (value != null)
            IconButton(
              key: settingsKey,
              tooltip: l10n.planSettingsTitle,
              icon: const Icon(Symbols.tune_rounded),
              onPressed: () => showPlanSettings(context, value),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: addKey,
        onPressed: () => showPlanGoalEditor(context),
        icon: const Icon(Symbols.add_rounded),
        label: Text(l10n.planNew),
      ),
      body: switch (plan) {
        AsyncValue(:final value?, hasError: false) => _PlanBody(plan: value),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(planControllerProvider),
        ),
        _ => const CdSkeleton(parts: [CdSkeletonCards(height: 96)]),
      },
    );
  }
}

class _PlanBody extends ConsumerWidget {
  const new({required this.plan});

  final LifePlan plan;

  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    int from,
    int to,
  ) async {
    final l10n = AppLocalizations.of(context);
    if (to == from) return;
    final failure = await ref
        .read(planControllerProvider.notifier)
        .move(from, to);
    if (failure == null || !context.mounted) return;
    await showCdToast(
      context,
      icon: Symbols.error_rounded,
      message: failure.userMessage(l10n),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Summary(key: PlanScreen.summaryKey, plan: plan),
        const SizedBox(height: AppSpacing.lg),
        Text(
          l10n.planOrderTitle,
          style: AppTextStyles.titleSm.copyWith(
            color: context.palette.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          l10n.planOrderHelp,
          style: AppTextStyles.bodyMd.copyWith(
            color: context.palette.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (plan.goals.isEmpty)
          CdEmptyState(
            icon: Symbols.flag_rounded,
            title: l10n.planEmptyTitle,
            message: l10n.planEmptyMessage,
          ),
      ],
    );
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sm,
        AppSpacing.screenGutter,
        96,
      ),
      header: header,
      itemCount: plan.goals.length,
      onReorderItem: (from, to) => _move(context, ref, from, to),
      itemBuilder: (_, index) {
        final goal = plan.goals[index];
        return Padding(
          key: PlanScreen.tileKey(goal.id),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _GoalTile(goal: goal),
        );
      },
    );
  }
}

class _Summary extends ConsumerWidget {
  const new({required this.plan, super.key});

  final LifePlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final hide = ref.watch(hideAmountsProvider);
    final secondary = AppTextStyles.bodyMd.copyWith(
      color: palette.onSurfaceVariant,
    );
    final timeline = plan.timeline;
    return CdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.planSavings(
              MoneyFormat.whole(plan.monthlySavings, hide: hide),
            ),
            style: AppTextStyles.titleSm.copyWith(color: palette.onSurface),
          ),
          Text(
            plan.savingsFromBudget
                ? l10n.planSavingsFromBudget
                : l10n.planSavingsCustom,
            style: secondary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.planFree(MoneyFormat.whole(plan.free, hide: hide)),
            style: secondary,
          ),
          Text(
            l10n.planReserve(
              MoneyFormat.whole(plan.reserve, hide: hide),
              plan.reserveMonths,
            ),
            style: secondary,
          ),
          if (plan.keepInvested > 0)
            Text(l10n.planKeep(plan.keepInvested), style: secondary),
          if (timeline.length > 1) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.planChartTitle,
              style: AppTextStyles.labelLg.copyWith(color: palette.onSurface),
            ),
            const SizedBox(height: AppSpacing.sm),
            CdLineChart(
              values: [
                for (final point in timeline) point.netWorth.cents.toDouble(),
              ],
              xLabels: [
                timeline.first.month.year.toString(),
                timeline.last.month.year.toString(),
              ],
              semanticsLabel: l10n.planChartSemantics(
                MoneyFormat.whole(timeline.first.netWorth, hide: hide),
                MoneyFormat.whole(timeline.last.netWorth, hide: hide),
              ),
              pointLabel: (index) {
                final point = timeline[index];
                return '${point.month.year}: '
                    '${MoneyFormat.compact(point.netWorth, hide: hide)}';
              },
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.planAssumptions(planRate(plan.yearlyYield)),
            style: AppTextStyles.labelMd.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalTile extends ConsumerWidget {
  const new({required this.goal});

  final PlanGoal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final hide = ref.watch(hideAmountsProvider);
    final secondary = AppTextStyles.bodyMd.copyWith(
      color: palette.onSurfaceVariant,
    );
    final amount = planAmountLine(l10n, goal, hide: hide);
    return CdCard(
      onTap: () => showPlanGoalEditor(context, goal: goal),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(planGoalIcon(goal), color: palette.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goal.name,
                  style: AppTextStyles.titleSm.copyWith(
                    color: palette.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(planWhenLine(l10n, goal, hide: hide), style: secondary),
                if (amount != null) Text(amount, style: secondary),
                for (final delay in goal.delays)
                  Text(planDelayLine(l10n, delay), style: secondary),
                if (goal.kind == PlanGoalKind.milestone) ...[
                  const SizedBox(height: AppSpacing.xs),
                  LinearProgressIndicator(value: goal.progress),
                ],
                if (goal.kind != PlanGoalKind.yearly) ...[
                  const SizedBox(height: AppSpacing.xs),
                  CdStatusBadge(
                    tone: planStatusTone(goal.status),
                    label: planStatusLabel(l10n, goal.status),
                  ),
                ],
              ],
            ),
          ),
          Icon(Symbols.drag_indicator_rounded, color: palette.onSurfaceVariant),
        ],
      ),
    );
  }
}
