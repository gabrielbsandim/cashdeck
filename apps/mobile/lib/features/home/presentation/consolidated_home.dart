import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/charts/cd_donut.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/money/cd_transaction_row.dart';
import 'package:cashdeck/features/bills/application/bills_use_cases.dart';
import 'package:cashdeck/features/bills/presentation/bills_controller.dart';
import 'package:cashdeck/features/home/domain/home_summary.dart';
import 'package:cashdeck/features/home/presentation/home_labels.dart';
import 'package:cashdeck/features/home/presentation/home_sections.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Início for both entities: the split of the balance, the month counted
/// once, the transfers between them and everything due soon.
class ConsolidatedHome extends ConsumerWidget {
  const new({required this.summary, super.key});

  static Key transferKey(String id) => Key('home-transfer-$id');

  final ConsolidatedSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final today = homeToday(ref);
    final bills = ref.watch(billsControllerProvider).value?.bills ?? const [];
    final entities = context.entities;
    return HomeScroll(
      children: [
        const PausedBanner(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BalanceHeader(
              label: l10n.consolidatedBalance,
              balance: summary.total,
              syncLine: null,
            ),
            const SizedBox(height: AppSpacing.md),
            CdSplitBar(
              parts: [
                (summary.personalShare, entities.personal),
                (1 - summary.personalShare, entities.company),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.xs,
              children: [
                _Legend(
                  color: entities.personal,
                  label: l10n.entityPersonal,
                  amount: summary.personal,
                ),
                _Legend(
                  color: entities.company,
                  label: l10n.entityCompany,
                  amount: summary.company,
                ),
              ],
            ),
          ],
        ),
        _MonthCard(summary: summary, month: monthName(context, today)),
        if (summary.transfers.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CdSectionHeader(title: l10n.betweenEntities),
              const SizedBox(height: AppSpacing.xs),
              for (final transfer in summary.transfers)
                CdTransactionRow(
                  key: transferKey(transfer.id),
                  icon: Symbols.sync_alt_rounded,
                  title: switch (transfer.kind) {
                    InternalTransferKind.profitDistribution =>
                      l10n.transferProfitDistribution,
                    InternalTransferKind.proLabore => l10n.transferProLabore,
                  },
                  subtitle: switch (transfer.kind) {
                    InternalTransferKind.profitDistribution =>
                      l10n.transferProfitSubtitle(transfer.on.dayMonth),
                    InternalTransferKind.proLabore =>
                      l10n.transferProLaboreSubtitle(transfer.on.dayMonth),
                  },
                  amount: transfer.amount,
                  kind: CdAmountKind.transfer,
                  onTap: () => context.go(AppRoutes.transfer(transfer.id)),
                ),
            ],
          ),
        DueSoonSection(
          bills: billsDueWithin(bills, today, 7),
          today: today,
          showEntity: true,
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const new({required this.color, required this.label, required this.amount});

  final Color color;
  final String label;
  final Money amount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: AppTextStyles.bodyMd.copyWith(
            color: context.palette.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        CdAmount(amount, size: CdAmountSize.sm),
      ],
    );
  }
}

class _MonthCard extends StatelessWidget {
  const new({required this.summary, required this.month});

  final ConsolidatedSummary summary;
  final String month;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final net = summary.net;
    return CdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.consolidatedMonthTitle(capitalized(month)),
            style: AppTextStyles.titleSm.copyWith(color: palette.onSurface),
          ),
          const SizedBox(height: AppSpacing.sm),
          _FlowRow(
            icon: Symbols.south_west_rounded,
            label: l10n.externalIn,
            amount: CdAmount(
              summary.externalIn,
              size: CdAmountSize.row,
              kind: CdAmountKind.income,
            ),
          ),
          _FlowRow(
            icon: Symbols.north_east_rounded,
            label: l10n.externalOut,
            amount: CdAmount(summary.externalOut, size: CdAmountSize.row),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: _FlowRow(
              icon: Symbols.sync_alt_rounded,
              label: l10n.betweenEntitiesOutside,
              amount: CdAmount(
                summary.internal,
                size: CdAmountSize.row,
                kind: CdAmountKind.transfer,
              ),
            ),
          ),
          const Divider(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.monthResult,
                  style: AppTextStyles.titleSm.copyWith(
                    color: palette.onSurface,
                  ),
                ),
              ),
              CdAmount(
                net,
                size: CdAmountSize.sm,
                kind: net.isNegative ? CdAmountKind.plain : CdAmountKind.income,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FlowRow extends StatelessWidget {
  const new({required this.icon, required this.label, required this.amount});

  final IconData icon;
  final String label;
  final Widget amount;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: palette.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodyMd.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
          ),
          amount,
        ],
      ),
    );
  }
}
