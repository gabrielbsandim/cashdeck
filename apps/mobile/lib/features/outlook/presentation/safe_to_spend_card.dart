import 'dart:async';

import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/insights/cd_insight_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/features/investments/presentation/investment_performance.dart';
import 'package:cashdeck/features/outlook/domain/safe_to_spend.dart';
import 'package:cashdeck/features/outlook/presentation/count_up_amount.dart';
import 'package:cashdeck/features/outlook/presentation/outlook_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The one number up top: what can be spent each day until the next income
/// without touching what is already owed. Tapping it explains the number.
class SafeToSpendCard extends ConsumerWidget {
  const new({super.key});

  static const cardKey = Key('home-safe-to-spend');
  static const retryKey = Key('home-safe-to-spend-retry');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final free = ref.watch(safeToSpendProvider);
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
          onRetry: () => ref.invalidate(safeToSpendProvider),
        ),
        _ => const PerformancePending(height: 112),
      },
    );
  }

  void _openBreakdown(BuildContext context, SafeToSpend free) {
    unawaited(HapticFeedback.selectionClick());
    unawaited(
      showCdBottomSheet<void>(
        context,
        title: AppLocalizations.of(context).safeToSpendBreakdownTitle,
        builder: (_) => SafeToSpendBreakdown(free: free),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (free.isShort) ...[
          Text(
            l10n.safeToSpendShort(until),
            style: AppTextStyles.titleMd.copyWith(color: context.money.overdue),
          ),
          const SizedBox(height: AppSpacing.xs),
          CdPrivateText(
            (hide) => l10n.safeToSpendShortBy(
              MoneyFormat.format(free.shortBy, hide: hide),
            ),
            style: muted,
          ),
        ] else ...[
          CountUpAmount(free.daily),
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
        if (income == null)
          Text(l10n.safeToSpendNoIncome, style: muted)
        else
          CdPrivateText(
            (hide) => l10n.safeToSpendIncome(
              MoneyFormat.format(income.amount, hide: hide),
              income.on.dayMonth,
            ),
            style: muted,
          ),
      ],
    );
  }
}

String safeToSpendKindLabel(AppLocalizations l10n, SafeToSpendLineKind kind) =>
    switch (kind) {
      SafeToSpendLineKind.bill => l10n.safeToSpendLineBill,
      SafeToSpendLineKind.fixed => l10n.safeToSpendLineFixed,
      SafeToSpendLineKind.subscription => l10n.safeToSpendLineSubscription,
      SafeToSpendLineKind.card => l10n.safeToSpendLineCard,
      SafeToSpendLineKind.reserve => l10n.safeToSpendLineReserve,
    };

/// From the checking balance, line by line, to what is free.
class SafeToSpendBreakdown extends StatelessWidget {
  const new({required this.free, super.key});

  static const totalKey = Key('safe-to-spend-total');
  static Key lineKey(int index) => Key('safe-to-spend-line-$index');

  final SafeToSpend free;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Line(label: l10n.safeToSpendCash, amount: CdAmount(free.cash)),
        for (final (index, line) in free.lines.indexed)
          _Line(
            key: lineKey(index),
            label: line.label.isEmpty
                ? safeToSpendKindLabel(l10n, line.kind)
                : line.label,
            caption: switch (line.on) {
              final on? => l10n.safeToSpendLineDue(
                safeToSpendKindLabel(l10n, line.kind),
                on.dayMonth,
              ),
              null => null,
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
    super.key,
  });

  final String label;
  final String? caption;
  final Widget amount;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final caption = this.caption;
    return Padding(
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
  }
}
