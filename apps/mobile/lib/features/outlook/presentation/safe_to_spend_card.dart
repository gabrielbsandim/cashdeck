import 'dart:async';

import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/feedback/cd_haptics.dart';
import 'package:cashdeck/core/widgets/insights/cd_insight_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/investments/presentation/investment_performance.dart';
import 'package:cashdeck/features/outlook/domain/safe_to_spend.dart';
import 'package:cashdeck/features/outlook/presentation/income_sources_sheet.dart';
import 'package:cashdeck/features/outlook/presentation/outlook_controller.dart';
import 'package:cashdeck/features/outlook/presentation/savings_target_sheet.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The one number up top: what can be spent each day for the rest of the
/// month, or until the next income on cash, without touching what is already
/// owed. Tapping it explains the number.
class SafeToSpendCard extends ConsumerWidget {
  const new({this.entity = EntityKind.personal, super.key});

  static const cardKey = Key('home-safe-to-spend');
  static const retryKey = Key('home-safe-to-spend-retry');

  final EntityKind entity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final provider = safeToSpendOfProvider(entity);
    final free = ref.watch(provider);
    return CdInsightCard(
      key: cardKey,
      title: l10n.safeToSpendTitle,
      onTap: switch (free) {
        AsyncData(:final value) => () => _openBreakdown(context, value),
        _ => null,
      },
      child: switch (free) {
        AsyncData(:final value) => _Free(free: value),
        AsyncError() => PerformanceFailed(
          retryKey: retryKey,
          onRetry: () => ref.invalidate(provider),
        ),
        _ => const PerformancePending(height: 112),
      },
    );
  }

  void _openBreakdown(BuildContext context, SafeToSpend free) {
    CdHaptics.selection();
    final plan = free.plan;
    unawaited(
      showCdBottomSheet<void>(
        context,
        title: AppLocalizations.of(context).safeToSpendBreakdownTitle,
        builder: (sheet) {
          void then(Future<void> Function() open) {
            Navigator.of(sheet).pop();
            unawaited(open());
          }

          return SafeToSpendBreakdown(
            free: free,
            onEditSavings: plan == null
                ? null
                : () => then(() => showSavingsTargetSheet(context, plan)),
            onEditIncome: plan == null
                ? null
                : () => then(() => showIncomeSourcesSheet(context)),
          );
        },
      ),
    );
  }
}

class _Free extends StatelessWidget {
  const new({required this.free});

  final SafeToSpend free;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = AppTextStyles.bodyMd.copyWith(
      color: context.palette.onSurfaceVariant,
    );
    final until = free.until.dayMonth;
    final income = free.income;
    final plan = free.plan;
    final onMonth = free.basis == SafeToSpendBasis.month;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (free.isShort) ...[
          Text(
            l10n.safeToSpendShort(until),
            style: AppTextStyles.titleMd.copyWith(color: context.money.overdue),
          ),
          const SizedBox(height: AppSpacing.xs),
          CdPrivateText((hide) {
            final amount = MoneyFormat.format(free.shortBy, hide: hide);
            return onMonth
                ? l10n.safeToSpendOverBy(amount)
                : l10n.safeToSpendShortBy(amount);
          }, style: muted),
        ] else ...[
          CdAmount(
            free.daily,
            size: CdAmountSize.xl,
            textAlign: TextAlign.start,
            countUp: true,
          ),
          Text(l10n.safeToSpendPerDay(until), style: muted),
          const SizedBox(height: AppSpacing.xs),
          CdPrivateText(
            (hide) => l10n.safeToSpendTotal(
              MoneyFormat.format(free.total, hide: hide),
              free.days,
            ),
            style: muted,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        switch ((plan, income)) {
          (final plan?, _) => CdPrivateText(
            (hide) => l10n.safeToSpendPlan(
              MoneyFormat.format(plan.income, hide: hide),
              MoneyFormat.format(plan.savings, hide: hide),
            ),
            style: muted,
          ),
          (null, final income?) => CdPrivateText(
            (hide) => l10n.safeToSpendIncome(
              MoneyFormat.format(income.amount, hide: hide),
              income.on.dayMonth,
            ),
            style: muted,
          ),
          (null, null) => Text(l10n.safeToSpendNoIncome, style: muted),
        },
        if (onMonth && free.isCashShort) ...[
          const SizedBox(height: AppSpacing.xs),
          CdPrivateText(
            (hide) => l10n.safeToSpendCashShort(
              MoneyFormat.format(free.cashShortBy, hide: hide),
            ),
            style: AppTextStyles.bodyMd.copyWith(color: context.money.overdue),
          ),
        ],
      ],
    );
  }
}

String safeToSpendKindLabel(AppLocalizations l10n, SafeToSpendLineKind kind) =>
    switch (kind) {
      SafeToSpendLineKind.income => l10n.safeToSpendLineIncome,
      SafeToSpendLineKind.savings => l10n.safeToSpendLineSavings,
      SafeToSpendLineKind.spentCard => l10n.safeToSpendLineSpentCard,
      SafeToSpendLineKind.spentAccount => l10n.safeToSpendLineSpentAccount,
      SafeToSpendLineKind.bill => l10n.safeToSpendLineBill,
      SafeToSpendLineKind.fixed => l10n.safeToSpendLineFixed,
      SafeToSpendLineKind.subscription => l10n.safeToSpendLineSubscription,
      SafeToSpendLineKind.card => l10n.safeToSpendLineCard,
      SafeToSpendLineKind.budget => l10n.safeToSpendLineBudget,
      SafeToSpendLineKind.reserve => l10n.safeToSpendLineReserve,
      SafeToSpendLineKind.loan => l10n.safeToSpendLineLoan,
    };

/// From the typical income, or the checking balance on cash, line by line to
/// what is free.
class SafeToSpendBreakdown extends StatelessWidget {
  const new({
    required this.free,
    this.onEditSavings,
    this.onEditIncome,
    super.key,
  });

  static const totalKey = Key('safe-to-spend-total');
  static Key lineKey(int index) => Key('safe-to-spend-line-$index');

  final SafeToSpend free;

  /// Opens the savings target; null keeps the savings line read only.
  final VoidCallback? onEditSavings;

  /// Opens the income sources; null keeps the income line read only.
  final VoidCallback? onEditIncome;

  String? _caption(AppLocalizations l10n, SafeToSpendLine line) => switch ((
    line.on,
    line.kind,
    free.plan,
  )) {
    (final on?, _, _) => l10n.safeToSpendLineDue(
      safeToSpendKindLabel(l10n, line.kind),
      on.dayMonth,
    ),
    (null, SafeToSpendLineKind.budget, _) => l10n.safeToSpendLineBudgetReserved,
    (null, SafeToSpendLineKind.income, final plan?) =>
      plan.fromReceived
          ? l10n.safeToSpendLineIncomeReceived
          : l10n.safeToSpendLineIncomeMedian(plan.months),
    (null, SafeToSpendLineKind.savings, final plan?) =>
      plan.savingsSet
          ? l10n.safeToSpendLineSavingsSet
          : l10n.safeToSpendLineSavingsTypical,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (free.basis == SafeToSpendBasis.cash)
          _Line(label: l10n.safeToSpendCash, amount: CdAmount(free.cash)),
        for (final (index, line) in free.lines.indexed)
          _Line(
            key: lineKey(index),
            label: line.label.isEmpty
                ? safeToSpendKindLabel(l10n, line.kind)
                : line.label,
            caption: _caption(l10n, line),
            onTap: switch (line.kind) {
              SafeToSpendLineKind.savings => onEditSavings,
              SafeToSpendLineKind.income => onEditIncome,
              _ => null,
            },
            amount: CdAmount(
              line.amount,
              size: CdAmountSize.row,
              kind: line.amount.isNegative
                  ? CdAmountKind.plain
                  : CdAmountKind.income,
            ),
          ),
        const Divider(height: AppSpacing.xl),
        _Line(
          key: totalKey,
          label: l10n.safeToSpendFree(free.until.dayMonth),
          strong: true,
          amount: CdAmount(
            free.total,
            color: free.total.isNegative ? context.money.overdue : null,
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const new({
    required this.label,
    required this.amount,
    this.caption,
    this.strong = false,
    this.onTap,
    super.key,
  });

  final String label;
  final String? caption;
  final Widget amount;
  final bool strong;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final caption = this.caption;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: (strong ? AppTextStyles.titleSm : AppTextStyles.bodyLg)
                      .copyWith(color: palette.onSurface),
                ),
                if (caption != null)
                  Text(
                    caption,
                    style: AppTextStyles.bodyMd.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          amount,
        ],
      ),
    );
    final onTap = this.onTap;
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}
