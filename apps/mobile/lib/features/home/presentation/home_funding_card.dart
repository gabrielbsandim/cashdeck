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

/// What the Asaas balance pays in the next 30 days, line by line, and what to
/// send now so it can. Hidden when nothing is coming.
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
        _Verdict(
          text: (hide) => short
              ? l10n.fundingTopUp(MoneyFormat.format(plan.topUp, hide: hide))
              : l10n.fundingCovered,
          short: short,
        ),
        const SizedBox(height: AppSpacing.xs),
        CdPrivateText((hide) {
          final needed = MoneyFormat.format(plan.needed, hide: hide);
          return switch (plan.balance) {
            null => l10n.fundingNeedsUnknown(needed),
            final balance => l10n.fundingNeeds(
              needed,
              MoneyFormat.format(balance, hide: hide),
            ),
          };
        }, style: muted),
        const SizedBox(height: AppSpacing.sm),
        for (final line in plan.lines) _Line(line: line),
        const SizedBox(height: AppSpacing.sm),
        CdPrivateText(
          (hide) =>
              l10n.fundingMonthly(MoneyFormat.format(plan.needed, hide: hide)),
          style: muted,
        ),
        if (plan.debit case final debit?) ...[
          const SizedBox(height: AppSpacing.md),
          CdPrivateText(
            (hide) => l10n.fundingDebit(
              debit.name,
              MoneyFormat.format(debit.total, hide: hide),
              MoneyFormat.format(debit.balance, hide: hide),
            ),
            style: muted,
          ),
          const SizedBox(height: AppSpacing.xs),
          _Verdict(
            text: (hide) => debit.topUp.cents > 0
                ? l10n.fundingDebitTopUp(
                    MoneyFormat.format(debit.topUp, hide: hide),
                    debit.name,
                  )
                : l10n.fundingDebitCovered(debit.name),
            short: debit.topUp.cents > 0,
          ),
        ],
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const new({required this.line});

  final FundingLine line;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const style = AppTextStyles.bodyMd;
    final name = switch (line.kind) {
      FundingLineKind.pix => l10n.fundingLinePix,
      FundingLineKind.expected => l10n.fundingLineExpected(line.name),
      FundingLineKind.bill || FundingLineKind.fixed => line.name,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              line.on.dayMonth,
              style: style.copyWith(color: context.palette.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(name, style: style, overflow: TextOverflow.ellipsis),
          ),
          CdPrivateText(
            (hide) => MoneyFormat.format(line.amount, hide: hide),
            style: style,
          ),
        ],
      ),
    );
  }
}

class _Verdict extends StatelessWidget {
  const new({required this.text, required this.short});

  // Passed through to CdPrivateText, which takes the flag the same way.
  // ignore: avoid_positional_boolean_parameters
  final String Function(bool hide) text;
  final bool short;

  @override
  Widget build(BuildContext context) => CdPrivateText(
    text,
    style: AppTextStyles.bodyMd.copyWith(
      color: short ? context.money.pending : context.money.income,
      fontWeight: FontWeight.w600,
    ),
  );
}
