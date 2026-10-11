import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/insights/cd_insight_card.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/features/home/domain/home_summary.dart';
import 'package:cashdeck/features/home/home_providers.dart';
import 'package:cashdeck/features/investments/presentation/investment_performance.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final FutureProvider<FundingPlan> fundingPlanProvider =
    FutureProvider.autoDispose<FundingPlan>(
      (ref) async => (await ref.watch(loadFundingPlanProvider)()).orThrow,
      retry: noRetry,
    );

/// How much the bills paid from Asaas take a month, to size a recurring
/// transfer, and what to send now for the next 30 days. Hidden without bills.
class HomeFundingCard extends ConsumerWidget {
  const new({super.key});

  static const cardKey = Key('home-funding');
  static const retryKey = Key('home-funding-retry');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final plan = ref.watch(fundingPlanProvider);
    if (plan case AsyncData(:final value) when value.isEmpty) {
      return const SizedBox.shrink();
    }
    return CdInsightCard(
      key: cardKey,
      title: l10n.fundingTitle,
      child: switch (plan) {
        AsyncData(:final value) => _Plan(plan: value),
        AsyncError() => PerformanceFailed(
          retryKey: retryKey,
          onRetry: () => ref.invalidate(fundingPlanProvider),
        ),
        _ => const PerformancePending(height: 96),
      },
    );
  }
}

class _Plan extends StatelessWidget {
  const new({required this.plan});

  final FundingPlan plan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = AppTextStyles.bodyMd.copyWith(
      color: context.palette.onSurfaceVariant,
    );
    final short = plan.topUp.cents > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CdAmount(
          plan.monthlyAverage,
          size: CdAmountSize.lg,
          textAlign: TextAlign.start,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(l10n.fundingAverage(plan.months), style: muted),
        const SizedBox(height: AppSpacing.sm),
        CdPrivateText(
          (hide) => l10n.fundingUpcoming(
            MoneyFormat.format(plan.upcoming, hide: hide),
            MoneyFormat.format(plan.expected, hide: hide),
            MoneyFormat.format(plan.pixReserve, hide: hide),
          ),
          style: muted,
        ),
        if (plan.balance case final balance?) ...[
          const SizedBox(height: AppSpacing.xs),
          CdPrivateText(
            (hide) =>
                l10n.fundingBalance(MoneyFormat.format(balance, hide: hide)),
            style: muted,
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        CdPrivateText(
          (hide) => short
              ? l10n.fundingTopUp(MoneyFormat.format(plan.topUp, hide: hide))
              : l10n.fundingCovered,
          style: AppTextStyles.bodyMd.copyWith(
            color: short ? context.money.pending : context.money.income,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
