import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/core/widgets/inputs/cd_filter_chip.dart';
import 'package:cashdeck/core/widgets/insights/cd_column_bars.dart';
import 'package:cashdeck/core/widgets/insights/cd_insight_card.dart';
import 'package:cashdeck/core/widgets/insights/cd_timeline.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/core/widgets/layout/cd_key_value_row.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:cashdeck/features/insights/presentation/insights_controller.dart';
import 'package:cashdeck/features/insights/presentation/insights_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

class InstallmentsScreen extends ConsumerWidget {
  const new({super.key});

  static const allKey = Key('installments-filter-all');
  static const endingKey = Key('installments-filter-ending');
  static Key planKey(String key) => Key('installments-plan-$key');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.installmentsTitle)),
      body: switch (ref.watch(installmentsProvider)) {
        AsyncData(:final value) when value.plans.isEmpty => CdEmptyState(
          icon: Symbols.event_repeat_rounded,
          title: l10n.installmentsEmpty,
          message: l10n.installmentsEmptyMessage,
        ),
        AsyncData(:final value) => _Plans(installments: value),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(installmentsProvider),
        ),
        _ => const CdSkeleton(),
      },
    );
  }
}

/// Plans with two installments or fewer to go.
const _endingWithin = 2;

class _Plans extends StatefulWidget {
  const new({required this.installments});

  final Installments installments;

  @override
  State<_Plans> createState() => _PlansState();
}

class _PlansState extends State<_Plans> {
  int _month = 0;
  bool _ending = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final months = widget.installments.months;
    final selected = months.elementAtOrNull(_month);
    final plans = [
      for (final plan in widget.installments.plans)
        if (!_ending || plan.left <= _endingWithin) plan,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sm,
        AppSpacing.screenGutter,
        AppSpacing.xxl,
      ),
      children: [
        if (selected != null)
          CdInsightCard(
            title: l10n.installmentsCommitted(monthName(l10n, selected.$1)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CdAmount(
                  selected.$2,
                  size: CdAmountSize.lg,
                  textAlign: TextAlign.start,
                ),
                const SizedBox(height: AppSpacing.md),
                CdColumnBars(
                  height: 96,
                  semanticsLabel: l10n.installmentsCommittedSemantics,
                  selected: _month,
                  onSelect: (index) => setState(() => _month = index),
                  columns: [
                    for (final (month, total) in months)
                      CdBarColumn(
                        label: shortMonth(l10n, month),
                        bars: [(total.cents / 100, palette.primary)],
                      ),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            CdFilterChip(
              key: InstallmentsScreen.allKey,
              label: l10n.installmentsFilterAll,
              selected: !_ending,
              onTap: () => setState(() => _ending = false),
            ),
            CdFilterChip(
              key: InstallmentsScreen.endingKey,
              label: l10n.installmentsFilterEnding,
              selected: _ending,
              onTap: () => setState(() => _ending = true),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        for (final plan in plans) ...[
          _PlanCard(plan: plan),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

String _cardLabel(InstallmentPlan plan) {
  final suffix = plan.cardSuffix;
  return suffix == null ? plan.card : '${plan.card} •• $suffix';
}

class _PlanCard extends StatelessWidget {
  const new({required this.plan});

  final InstallmentPlan plan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return CdInsightCard(
      key: InstallmentsScreen.planKey(plan.key),
      title: plan.name,
      onTap: () => _showPlan(context, plan),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _cardLabel(plan),
                  style: AppTextStyles.bodyMd.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ),
              CdAmount(plan.amount, size: CdAmountSize.row),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              value: plan.number / plan.count,
              minHeight: 8,
              color: palette.primary,
              backgroundColor: palette.surfaceContainerHigh,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(
                l10n.installmentsProgress(plan.number, plan.count),
                style: AppTextStyles.labelLg.copyWith(color: palette.onSurface),
              ),
              const Spacer(),
              Text(
                l10n.installmentsEnds(shortMonth(l10n, plan.finalMonth)),
                style: AppTextStyles.labelMd.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _showPlan(BuildContext context, InstallmentPlan plan) {
  final l10n = AppLocalizations.of(context);
  final purchase = plan.purchaseOn;
  final last = YearMonth.of(plan.lastBilledOn);
  return showCdBottomSheet<void>(
    context,
    title: plan.name,
    builder: (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _cardLabel(plan),
          style: AppTextStyles.bodyMd.copyWith(
            color: context.palette.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (purchase != null)
          CdKeyValueRow(
            label: l10n.installmentsPurchase,
            value: Text(purchase.display),
          ),
        CdKeyValueRow(
          label: l10n.installmentsTotal,
          value: CdAmount(plan.total, size: CdAmountSize.row),
        ),
        CdKeyValueRow(
          label: l10n.installmentsPaid,
          value: CdAmount(plan.paid, size: CdAmountSize.row),
        ),
        CdKeyValueRow(
          label: l10n.installmentsLeft,
          strong: true,
          value: CdAmount(plan.remaining, size: CdAmountSize.row),
        ),
        const SizedBox(height: AppSpacing.lg),
        CdTimeline(
          entries: [
            for (var number = 1; number <= plan.count; number++)
              CdTimelineEntry(
                title: l10n.installmentsNumber(number),
                subtitle: monthTitle(l10n, last.add(number - plan.number)),
                trailing: CdAmount(plan.amount, size: CdAmountSize.row),
                state: switch (number.compareTo(plan.number)) {
                  -1 => CdTimelineState.done,
                  0 => CdTimelineState.current,
                  _ => CdTimelineState.future,
                },
              ),
          ],
        ),
      ],
    ),
  );
}
