import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/charts/cd_line_chart.dart';
import 'package:cashdeck/core/widgets/inputs/cd_segmented.dart';
import 'package:cashdeck/core/widgets/insights/cd_insight_card.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/features/investments/domain/investments.dart';
import 'package:cashdeck/features/investments/presentation/investments_controller.dart';
import 'package:cashdeck/features/investments/presentation/investments_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The 1s, 1m and 1a toggle every performance view shares.
class PerformancePeriodToggle extends ConsumerWidget {
  const new({super.key});

  static Key periodKey(PerformancePeriod period) =>
      Key('investments-period-${period.name}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: 156,
      child: CdSegmented<PerformancePeriod>(
        segments: [
          for (final value in PerformancePeriod.values)
            CdSegment(
              value,
              performancePeriodLabel(l10n, value),
              key: periodKey(value),
            ),
        ],
        selected: ref.watch(performancePeriodProvider),
        onChanged: (value) =>
            ref.read(performancePeriodProvider.notifier).period = value,
      ),
    );
  }
}

/// A gain in the income color with a plus, a loss in the expense color, and
/// the percent beside it when known.
class InvestmentYield extends StatelessWidget {
  const new({
    required this.amount,
    this.percent,
    this.size = CdAmountSize.row,
    super.key,
  });

  final Money amount;
  final double? percent;
  final CdAmountSize size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = amount.isNegative
        ? context.money.expense
        : context.money.income;
    final percent = this.percent;
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xs,
      children: [
        CdAmount(
          amount,
          size: size,
          kind: amount.isNegative ? CdAmountKind.plain : CdAmountKind.income,
          color: color,
        ),
        if (percent != null)
          Text(
            '(${signedPercent(l10n, percent)})',
            style: AppTextStyles.labelMd.copyWith(color: color),
          ),
      ],
    );
  }
}

/// The portfolio value across the window, its first and last day below.
class PerformanceChart extends ConsumerWidget {
  const new({required this.performance, this.height = 112, super.key});

  final InvestmentPerformance performance;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hide = ref.watch(hideAmountsProvider);
    if (performance.series.length < 2) return const SizedBox.shrink();
    return CdLineChart(
      height: height,
      values: [for (final point in performance.series) point.value.cents / 100],
      xLabels: [performance.from.dayMonth, performance.to.dayMonth],
      semanticsLabel: l10n.investmentsChartSemantics(
        MoneyFormat.format(performance.start, hide: hide),
        MoneyFormat.format(performance.end, hide: hide),
      ),
    );
  }
}

/// What the window earned in reais and percent, against the CDI, and what
/// went in and out, two tiles a row.
class PerformanceStats extends StatelessWidget {
  const new({required this.performance, super.key});

  static const yieldKey = Key('investments-stat-yield');
  static const percentKey = Key('investments-stat-percent');
  static const cdiKey = Key('investments-stat-cdi');
  static const contributionsKey = Key('investments-stat-contributions');
  static const withdrawalsKey = Key('investments-stat-withdrawals');

  final InvestmentPerformance performance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final percent = performance.yieldPercent;
    final cdi = performance.cdiPercent;
    final ofCdi = performance.ofCdi;
    final strong = AppTextStyles.titleSm.copyWith(color: palette.onSurface);
    final tiles = [
      _Stat(
        key: yieldKey,
        label: l10n.investmentsProfit,
        value: InvestmentYield(amount: performance.yieldAmount),
      ),
      if (percent != null)
        _Stat(
          key: percentKey,
          label: l10n.investmentsStatYieldPercent,
          value: Text(
            signedPercent(l10n, percent),
            style: strong.copyWith(
              color: percent < 0 ? context.money.expense : context.money.income,
            ),
          ),
        ),
      if (cdi != null)
        _Stat(
          key: cdiKey,
          label: l10n.investmentsStatVsCdi,
          value: Text(switch (ofCdi) {
            null => l10n.investmentsCdi(unsignedPercent(l10n, cdi)),
            final share => l10n.investmentRatePercentOf('$share', 'CDI'),
          }, style: strong),
          caption: ofCdi == null
              ? null
              : l10n.investmentsCdi(unsignedPercent(l10n, cdi)),
        ),
      _Stat(
        key: contributionsKey,
        label: l10n.investmentsStatContributions,
        value: CdAmount(performance.contributions, size: CdAmountSize.row),
      ),
      _Stat(
        key: withdrawalsKey,
        label: l10n.investmentsStatWithdrawals,
        value: CdAmount(performance.withdrawals, size: CdAmountSize.row),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var start = 0; start < tiles.length; start += 2)
          Padding(
            padding: EdgeInsets.only(top: start == 0 ? 0 : AppSpacing.sm),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: tiles[start]),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: start + 1 < tiles.length
                        ? tiles[start + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    this.caption,
    super.key,
  });

  final String label;
  final Widget value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final muted = AppTextStyles.labelMd.copyWith(
      color: palette.onSurfaceVariant,
    );
    final caption = this.caption;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: muted),
            const SizedBox(height: AppSpacing.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: value,
            ),
            if (caption != null) Text(caption, style: muted),
          ],
        ),
      ),
    );
  }
}

/// Says the history before today comes from market prices.
class EstimatedHint extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = context.palette.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Symbols.info_rounded, size: 16, color: muted),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            l10n.investmentsEstimatedHint,
            style: AppTextStyles.labelMd.copyWith(color: muted),
          ),
        ),
      ],
    );
  }
}

/// A short line saying the section did not load, with a retry.
class PerformanceFailed extends StatelessWidget {
  const new({required this.onRetry, required this.retryKey, super.key});

  final VoidCallback onRetry;
  final Key retryKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.homeSectionFailed,
            style: AppTextStyles.bodyMd.copyWith(
              color: context.palette.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(
          key: retryKey,
          onPressed: onRetry,
          child: Text(l10n.retryButton),
        ),
      ],
    );
  }
}

/// The placeholder a performance shows while it loads.
class PerformancePending extends StatelessWidget {
  const new({required this.height, super.key});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.palette.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),
  );
}

/// The window toggle over the chart, the stats and the estimate hint, as the
/// investments screen and a position show them.
class InvestmentPerformanceCard extends StatelessWidget {
  const new({required this.performance, required this.onRetry, super.key});

  static const retryKey = Key('investments-performance-retry');

  final AsyncValue<InvestmentPerformance> performance;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CdInsightCard(
      title: l10n.investmentsPerformance,
      trailing: const PerformancePeriodToggle(),
      child: switch (performance) {
        AsyncData(:final value) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PerformanceChart(performance: value),
            const SizedBox(height: AppSpacing.md),
            PerformanceStats(performance: value),
            if (value.estimated) ...[
              const SizedBox(height: AppSpacing.md),
              const EstimatedHint(),
            ],
          ],
        ),
        AsyncError() => PerformanceFailed(onRetry: onRetry, retryKey: retryKey),
        _ => const PerformancePending(height: 260),
      },
    );
  }
}
