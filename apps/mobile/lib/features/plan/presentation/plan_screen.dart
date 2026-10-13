import 'dart:async';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/charts/cd_line_chart.dart';
import 'package:cashdeck/core/widgets/feedback/cd_haptics.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_icon_tile.dart';
import 'package:cashdeck/core/widgets/layout/cd_key_value_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/goals/domain/goal.dart';
import 'package:cashdeck/features/goals/presentation/goal_editor.dart';
import 'package:cashdeck/features/goals/presentation/goal_ring.dart';
import 'package:cashdeck/features/goals/presentation/goals_controller.dart';
import 'package:cashdeck/features/plan/domain/life_plan.dart';
import 'package:cashdeck/features/plan/presentation/plan_advice_sheet.dart';
import 'package:cashdeck/features/plan/presentation/plan_controller.dart';
import 'package:cashdeck/features/plan/presentation/plan_goal_editor.dart';
import 'package:cashdeck/features/plan/presentation/plan_labels.dart';
import 'package:cashdeck/features/plan/presentation/plan_settings_sheet.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The life goals in their order, each with the month it fits, what it costs
/// the milestones and the caixinha saving for it; the other caixinhas close
/// the list.
class PlanScreen extends ConsumerWidget {
  const new({super.key});

  static const addKey = Key('plan-add');
  static const settingsKey = Key('plan-settings');
  static const adviceKey = Key('plan-advice');
  static const summaryKey = Key('plan-summary');
  static const savingsKey = Key('plan-savings');
  static const recalculatingKey = Key('plan-recalculating');

  static const newCaixinhaKey = Key('plan-caixinha-new');
  static const allCaixinhasKey = Key('plan-caixinhas-all');

  static Key tileKey(String id) => Key('plan-goal-$id');
  static Key handleKey(String id) => Key('plan-goal-handle-$id');
  static Key caixinhaKey(String id) => Key('plan-caixinha-$id');
  static Key createCaixinhaKey(String id) => Key('plan-caixinha-create-$id');
  static Key otherCaixinhaKey(String id) => Key('plan-caixinha-other-$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final plan = ref.watch(planControllerProvider);
    final value = plan.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.planTitle),
        actions: [
          if (value != null && value.goals.isNotEmpty)
            IconButton(
              key: adviceKey,
              tooltip: l10n.planAdviceAction,
              icon: const Icon(Symbols.auto_awesome_rounded),
              onPressed: () => showPlanAdvice(context),
            ),
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

class _PlanBody extends ConsumerStatefulWidget {
  const new({required this.plan});

  final LifePlan plan;

  @override
  ConsumerState<_PlanBody> createState() => _PlanBodyState();
}

class _PlanBodyState extends ConsumerState<_PlanBody> {
  var _saving = 0;

  Future<void> _move(int from, int to, {bool undoable = true}) async {
    if (to == from) return;
    final l10n = AppLocalizations.of(context);
    CdHaptics.confirm();
    setState(() => _saving++);
    final before = ref.read(planControllerProvider).requireValue;
    final failure = await ref
        .read(planControllerProvider.notifier)
        .move(from, to);
    if (!mounted) return;
    setState(() => _saving--);
    if (failure != null) {
      CdHaptics.error();
      await showCdToast(
        context,
        icon: Symbols.error_rounded,
        message: failure.userMessage(l10n),
      );
      return;
    }
    if (!undoable) return;
    final after = ref.read(planControllerProvider).requireValue;
    await showCdToast(
      context,
      icon: Symbols.swap_vert_rounded,
      message: after.datesDiffer(before)
          ? l10n.planReordered
          : l10n.planReorderedSameDates,
      actionLabel: l10n.undoButton,
      onAction: () => unawaited(_move(to, from, undoable: false)),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(goalsControllerProvider);
    await ref
        .refresh(planControllerProvider.future)
        .then<void>((_) {}, onError: (_) {});
  }

  // The lifted card is drawn again as selected: depth here comes from
  // surfaces, not shadows, which the dark theme does not have.
  Widget _lifted(Widget child, int index, Animation<double> animation) {
    final goal = widget.plan.goals[index];
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Transform.scale(
        scale: 1 + 0.02 * Curves.easeOut.transform(animation.value),
        child: child,
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: _GoalTile(goal: goal, index: index, lifted: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final plan = widget.plan;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Summary(key: PlanScreen.summaryKey, plan: plan),
        const SizedBox(height: AppSpacing.xl),
        Text(
          l10n.planOrderTitle,
          style: AppTextStyles.titleSm.copyWith(color: palette.onSurface),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          l10n.planOrderHelp,
          style: AppTextStyles.bodyMd.copyWith(color: palette.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 4,
          child: _saving == 0
              ? null
              : LinearProgressIndicator(
                  key: PlanScreen.recalculatingKey,
                  semanticsLabel: l10n.planRecalculating,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (plan.goals.isEmpty)
          CdEmptyState(
            icon: Symbols.flag_rounded,
            title: l10n.planEmptyTitle,
            message: l10n.planEmptyMessage,
            actionLabel: l10n.planNew,
            actionIcon: Symbols.add_rounded,
            onAction: () => showPlanGoalEditor(context),
          ),
      ],
    );
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ReorderableListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.sm,
          AppSpacing.screenGutter,
          96,
        ),
        header: header,
        footer: _OtherCaixinhas(plan: plan),
        itemCount: plan.goals.length,
        onReorderStart: (_) => CdHaptics.selection(),
        onReorderItem: (from, to) => unawaited(_move(from, to)),
        proxyDecorator: _lifted,
        itemBuilder: (_, index) {
          final goal = plan.goals[index];
          return Padding(
            key: PlanScreen.tileKey(goal.id),
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _GoalTile(goal: goal, index: index),
          );
        },
      ),
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
            l10n.planSavingsLabel,
            style: AppTextStyles.labelLg.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            MoneyFormat.whole(plan.monthlySavings, hide: hide),
            key: PlanScreen.savingsKey,
            style: AppTextStyles.amountLg.copyWith(color: palette.onSurface),
          ),
          Text(
            plan.savingsFromBudget
                ? l10n.planSavingsFromBudget
                : l10n.planSavingsCustom,
            style: secondary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Divider(color: palette.outlineVariant, height: AppSpacing.md),
          CdKeyValueRow(
            label: l10n.planFreeLabel,
            value: Text(
              l10n.planPerMonth(MoneyFormat.whole(plan.free, hide: hide)),
            ),
          ),
          CdKeyValueRow(
            label: l10n.planReserveLabel(plan.reserveMonths),
            value: Text(MoneyFormat.whole(plan.reserve, hide: hide)),
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
  const new({required this.goal, required this.index, this.lifted = false});

  final PlanGoal goal;
  final int index;
  final bool lifted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final hide = ref.watch(hideAmountsProvider);
    final secondary = AppTextStyles.bodyMd.copyWith(
      color: palette.onSurfaceVariant,
    );
    final amount = planAmountLine(l10n, goal, hide: hide);
    final yearly = goal.kind == PlanGoalKind.yearly;
    return CdCard(
      selected: lifted,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.cardPadding,
        AppSpacing.cardPadding,
        0,
        AppSpacing.cardPadding,
      ),
      onTap: () => showPlanGoalEditor(context, goal: goal),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              CdIconTile(
                planGoalIcon(goal),
                circle: false,
                size: 44,
                tone: yearly ? null : context.tone(planStatusTone(goal.status)),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.planPosition(index + 1),
                style: AppTextStyles.labelMd.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goal.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleSm.copyWith(
                    color: palette.onSurface,
                  ),
                ),
                if (!yearly) ...[
                  const SizedBox(height: AppSpacing.xs),
                  CdStatusBadge(
                    tone: planStatusTone(goal.status),
                    label: planStatusLabel(l10n, goal.status),
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(
                  planWhenLine(l10n, goal, hide: hide),
                  style: AppTextStyles.bodyMd.copyWith(
                    color: palette.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (amount != null) Text(amount, style: secondary),
                if (goal.kind == PlanGoalKind.purchase &&
                    goal.payment == PlanPayment.card)
                  Text(l10n.planCardLine(goal.installments), style: secondary),
                for (final delay in goal.delays)
                  Text(planDelayLine(l10n, delay), style: secondary),
                if (goal.kind == PlanGoalKind.milestone)
                  _MilestoneBar(progress: goal.progress),
                if (goal.kind == PlanGoalKind.purchase)
                  _CaixinhaRow(goal: goal),
              ],
            ),
          ),
          _DragHandle(
            key: PlanScreen.handleKey(goal.id),
            index: index,
            name: goal.name,
          ),
        ],
      ),
    );
  }
}

class _MilestoneBar extends StatelessWidget {
  const new({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final label = l10n.planMilestonePercent((progress * 100).floor());
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              backgroundColor: palette.surfaceContainerHigh,
              semanticsLabel: label,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ExcludeSemantics(
            child: Text(
              label,
              style: AppTextStyles.labelMd.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Starts a drag at once, where holding the card waits for a long press.
class _DragHandle extends StatelessWidget {
  const new({required this.index, required this.name, super.key});

  final int index;
  final String name;

  @override
  Widget build(BuildContext context) => Semantics(
    label: AppLocalizations.of(context).planDragHandle(name),
    child: ReorderableDragStartListener(
      index: index,
      child: SizedBox.square(
        dimension: AppSpacing.minTouchTarget,
        child: Icon(
          Symbols.drag_indicator_rounded,
          color: context.palette.onSurfaceVariant,
        ),
      ),
    ),
  );
}

String _progressOf(
  AppLocalizations l10n,
  Goal caixinha, {
  required bool hide,
}) => l10n.planCaixinhaProgress(
  MoneyFormat.whole(caixinha.saved, hide: hide),
  MoneyFormat.whole(caixinha.target, hide: hide),
);

/// The caixinha saving for a purchase, or a way to start one sized to the
/// cash the purchase takes and due by its month.
class _CaixinhaRow extends ConsumerWidget {
  const new({required this.goal});

  final PlanGoal goal;

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final month = goal.month;
    final caixinhas = ref.read(goalsControllerProvider.notifier);
    final plan = ref.read(planControllerProvider.notifier);
    var linked = false;
    await showGoalEditor(
      context,
      initial: GoalDraft(
        name: goal.name,
        target: goal.cash,
        deadline: month == null
            ? null
            : CalendarDate.fromDateTime(
                DateTime(month.year, month.month + 1, 0),
              ),
      ),
      save: (draft) async {
        final outcome = await caixinhas.create(draft);
        final created = outcome.goal;
        if (created == null) return outcome;
        final failure = await plan.save(
          PlanGoalDraft.of(goal).linkedTo(created.id),
          id: goal.id,
        );
        linked = failure == null;
        return outcome;
      },
    );
    if (!linked || !context.mounted) return;
    await showCdToast(
      context,
      icon: Symbols.savings_rounded,
      message: l10n.planCaixinhaLinked,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final hide = ref.watch(hideAmountsProvider);
    final caixinhas = ref.watch(goalsControllerProvider).value;
    if (caixinhas == null) return const SizedBox.shrink();
    final linked = caixinhas
        .where((item) => item.id == goal.goalId)
        .firstOrNull;
    if (linked != null) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: InkWell(
          key: PlanScreen.caixinhaKey(goal.id),
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => context.push(AppRoutes.goal(linked.id)),
          child: Row(
            children: [
              GoalRing(goal: linked, size: 32),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _progressOf(l10n, linked, hide: hide),
                  style: AppTextStyles.bodyMd.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (goal.status == PlanStatus.outOfReach) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: PlanScreen.createCaixinhaKey(goal.id),
        onPressed: () => _create(context, ref),
        icon: const Icon(Symbols.savings_rounded),
        label: Text(l10n.planCaixinhaCreate),
      ),
    );
  }
}

/// The caixinhas no purchase of the plan points at.
class _OtherCaixinhas extends ConsumerWidget {
  const new({required this.plan});

  final LifePlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final hide = ref.watch(hideAmountsProvider);
    final caixinhas = ref.watch(goalsControllerProvider).value;
    if (caixinhas == null) return const SizedBox.shrink();
    final linked = {for (final goal in plan.goals) ?goal.goalId};
    final others = [
      for (final caixinha in caixinhas)
        if (!linked.contains(caixinha.id)) caixinha,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.md),
        CdSectionHeader(
          title: l10n.planCaixinhasTitle,
          actionLabel: caixinhas.isEmpty ? null : l10n.seeAllButton,
          actionKey: PlanScreen.allCaixinhasKey,
          onAction: () => context.push(AppRoutes.goals),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          l10n.planCaixinhasHelp,
          style: AppTextStyles.bodyMd.copyWith(color: palette.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final caixinha in others) ...[
          CdCard(
            key: PlanScreen.otherCaixinhaKey(caixinha.id),
            onTap: () => context.push(AppRoutes.goal(caixinha.id)),
            child: Row(
              children: [
                GoalRing(goal: caixinha, size: 40),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        caixinha.name,
                        style: AppTextStyles.titleSm.copyWith(
                          color: palette.onSurface,
                        ),
                      ),
                      Text(
                        _progressOf(l10n, caixinha, hide: hide),
                        style: AppTextStyles.bodyMd.copyWith(
                          color: palette.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: PlanScreen.newCaixinhaKey,
            onPressed: () => showGoalEditor(
              context,
              save: ref.read(goalsControllerProvider.notifier).create,
            ),
            icon: const Icon(Symbols.add_rounded),
            label: Text(l10n.planCaixinhaNew),
          ),
        ),
      ],
    );
  }
}
