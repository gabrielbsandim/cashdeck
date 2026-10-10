import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/theme/app_chart_colors.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/insights/cd_institution_logo.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_key_value_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_refresh.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/investments/domain/investments.dart';
import 'package:cashdeck/features/investments/presentation/investment_performance.dart';
import 'package:cashdeck/features/investments/presentation/investments_controller.dart';
import 'package:cashdeck/features/investments/presentation/investments_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// One position: what it is and what it pays, how the chosen window went and
/// every movement, newest first.
class InvestmentDetailScreen extends ConsumerWidget {
  const new({required this.positionId, super.key});

  static const balanceKey = Key('investment-balance');
  static const rateKey = Key('investment-rate');
  static Key movementKey(String id) => Key('investment-movement-$id');

  final String positionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final provider = investmentDetailProvider(positionId);
    final detail = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(
        title: Text(detail.value?.position.name ?? l10n.investmentsTitle),
      ),
      body: switch (detail) {
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(provider),
        ),
        AsyncValue(:final value?) => CdRefresh(
          providers: [provider],
          child: _Detail(
            detail: value,
            performance: detail.whenData((value) => value.performance),
            onRetry: () => ref.invalidate(provider),
          ),
        ),
        _ => const CdSkeleton(),
      },
    );
  }
}

class _Detail extends StatelessWidget {
  const new({
    required this.detail,
    required this.performance,
    required this.onRetry,
  });

  final InvestmentDetail detail;
  final AsyncValue<InvestmentPerformance> performance;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final position = detail.position;
    final muted = AppTextStyles.bodyMd.copyWith(
      color: palette.onSurfaceVariant,
    );
    const gutter = EdgeInsets.fromLTRB(
      AppSpacing.screenGutter,
      AppSpacing.lg,
      AppSpacing.screenGutter,
      0,
    );
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.md,
            AppSpacing.screenGutter,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CdInstitutionLogo(
                    name: position.institution,
                    imageUrl: position.logo?.imageUrl,
                    colors: context.charts.at(0),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          position.name,
                          style: AppTextStyles.titleSm.copyWith(
                            color: palette.onSurface,
                          ),
                        ),
                        Text(
                          [
                            position.institution,
                            investmentKindLabel(l10n, position.kind),
                            ?investmentSubtypeLabel(l10n, position.subtype),
                          ].join(' · '),
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(l10n.investmentDetailBalance, style: muted),
              const SizedBox(height: AppSpacing.xs),
              CdAmount(
                position.balance,
                key: InvestmentDetailScreen.balanceKey,
                size: CdAmountSize.xl,
                textAlign: TextAlign.start,
              ),
            ],
          ),
        ),
        Padding(
          padding: gutter,
          child: CdCard(child: _Facts(position: position)),
        ),
        Padding(
          padding: gutter,
          child: InvestmentPerformanceCard(
            performance: performance,
            onRetry: onRetry,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.lg,
            AppSpacing.screenGutter,
            AppSpacing.xs,
          ),
          child: CdSectionHeader(title: l10n.investmentMovements, small: true),
        ),
        if (detail.movements.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenGutter,
            ),
            child: Text(l10n.investmentNoMovements, style: muted),
          ),
        for (final movement in detail.movements)
          _MovementRow(movement: movement),
      ],
    );
  }
}

class _Facts extends StatelessWidget {
  const new({required this.position});

  final InvestmentPosition position;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final issuer = position.issuer;
    final rate = investmentRateLabel(l10n, position.rate);
    final invested = position.invested;
    final profit = position.profit;
    final quantity = position.quantity;
    final lastMonth = position.lastMonthRate;
    final twelveMonths = position.lastTwelveMonthsRate;
    final due = position.dueOn;
    final valued = position.valuedOn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (invested != null)
          CdKeyValueRow(
            label: l10n.investmentsInvested,
            value: CdAmount(invested, size: CdAmountSize.row),
          ),
        if (profit != null)
          CdKeyValueRow(
            label: l10n.investmentDetailProfitTotal,
            value: InvestmentYield(
              amount: profit,
              percent: position.profitPercent,
            ),
          ),
        if (rate != null)
          CdKeyValueRow(
            key: InvestmentDetailScreen.rateKey,
            label: l10n.investmentDetailRate,
            value: Text(rate),
          ),
        if (due != null)
          CdKeyValueRow(
            label: l10n.investmentDetailDueOn,
            value: Text(due.display),
          ),
        if (issuer != null)
          CdKeyValueRow(
            label: l10n.investmentDetailIssuer,
            value: Text(issuer),
          ),
        if (quantity != null)
          CdKeyValueRow(
            label: l10n.investmentDetailQuantity,
            value: Text(plainNumber(l10n, quantity)),
          ),
        if (lastMonth != null)
          CdKeyValueRow(
            label: l10n.investmentDetailLastMonth,
            value: Text(signedPercent(l10n, lastMonth)),
          ),
        if (twelveMonths != null)
          CdKeyValueRow(
            label: l10n.investmentDetailTwelveMonths,
            value: Text(signedPercent(l10n, twelveMonths)),
          ),
        if (valued != null)
          CdKeyValueRow(
            label: l10n.investmentDetailValuedOn,
            value: Text(valued.display),
          ),
        if (position.pending)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              l10n.investmentsPending,
              style: AppTextStyles.labelMd.copyWith(
                color: context.money.pending,
              ),
            ),
          ),
      ],
    );
  }
}

class _MovementRow extends StatelessWidget {
  const new({required this.movement});

  final InvestmentMovement movement;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final quantity = movement.quantity;
    final (icon, kind) = switch (movement.kind) {
      InvestmentMovementKind.buy => (Symbols.add_rounded, CdAmountKind.plain),
      InvestmentMovementKind.sell => (
        Symbols.remove_rounded,
        CdAmountKind.plain,
      ),
      InvestmentMovementKind.income => (
        Symbols.payments_rounded,
        CdAmountKind.income,
      ),
      InvestmentMovementKind.tax => (
        Symbols.receipt_long_rounded,
        CdAmountKind.expense,
      ),
      InvestmentMovementKind.transfer => (
        Symbols.sync_alt_rounded,
        CdAmountKind.transfer,
      ),
      InvestmentMovementKind.other => (
        Symbols.more_horiz_rounded,
        CdAmountKind.plain,
      ),
    };
    return CdListRow(
      key: InvestmentDetailScreen.movementKey(movement.id),
      icon: icon,
      title: movementKindLabel(l10n, movement.kind),
      subtitle: [
        movement.occurredOn.display,
        if (quantity != null)
          l10n.investmentMovementQuantity(plainNumber(l10n, quantity)),
      ].join(' · '),
      trailing: CdAmount(movement.amount, size: CdAmountSize.row, kind: kind),
    );
  }
}
