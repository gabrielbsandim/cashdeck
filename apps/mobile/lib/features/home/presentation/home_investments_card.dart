import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/insights/cd_comparison_pill.dart';
import 'package:cashdeck/core/widgets/insights/cd_insight_card.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/features/investments/domain/investments.dart';
import 'package:cashdeck/features/investments/presentation/investment_performance.dart';
import 'package:cashdeck/features/investments/presentation/investments_controller.dart';
import 'package:cashdeck/features/investments/presentation/investments_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// What the investments are worth and what they earned in the chosen window
/// against the CDI, with the curve; opens the investments screen. Hidden
/// without positions.
class HomeInvestmentsCard extends ConsumerWidget {
  const new({super.key});

  static const cardKey = Key('home-investments');
  static const retryKey = Key('home-investments-retry');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final performance = ref.watch(investmentPerformanceProvider);
    if (performance case AsyncData(:final value) when value.positions.isEmpty) {
      return const SizedBox.shrink();
    }
    return CdInsightCard(
      key: cardKey,
      title: l10n.investmentsTitle,
      trailing: const PerformancePeriodToggle(),
      onTap: () => context.push(AppRoutes.investments).ignore(),
      child: switch (performance) {
        AsyncData(:final value) => _Invested(performance: value),
        AsyncError() => PerformanceFailed(
          retryKey: retryKey,
          onRetry: () => ref.invalidate(investmentPerformanceProvider),
        ),
        _ => const PerformancePending(height: 180),
      },
    );
  }
}

class _Invested extends StatelessWidget {
  const new({required this.performance});

  final InvestmentPerformance performance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final percent = performance.yieldPercent;
    final cdi = performance.cdiPercent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CdAmount(
          performance.end,
          size: CdAmountSize.lg,
          textAlign: TextAlign.start,
        ),
        if (percent != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: CdComparisonPill(
              direction: percent.compareTo(0),
              value: unsignedPercent(l10n, percent),
              goodWhen: GoodWhen.up,
              label: l10n.investmentsInPeriod,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        CdPrivateText(
          (hide) => [
            l10n.investmentsPeriodYield(
              MoneyFormat.format(
                performance.yieldAmount,
                hide: hide,
                sign: MoneySign.plus,
              ),
            ),
            if (cdi != null) l10n.investmentsCdi(unsignedPercent(l10n, cdi)),
          ].join(' · '),
          style: AppTextStyles.bodyMd.copyWith(
            color: context.palette.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        PerformanceChart(performance: performance, height: 72),
      ],
    );
  }
}
