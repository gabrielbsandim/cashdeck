import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_entity_badge.dart';
import 'package:cashdeck/core/widgets/layout/cd_icon_tile.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/entities/presentation/entity_switcher.dart';
import 'package:cashdeck/features/transactions/domain/internal_transfer.dart';
import 'package:cashdeck/features/transactions/transactions_providers.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

final FutureProviderFamily<TransferDetail, String> transferProvider =
    FutureProvider.autoDispose.family<TransferDetail, String>(
      (ref, id) async =>
          (await ref.watch(transfersRepositoryProvider).transfer(id)).orThrow,
      retry: noRetry,
    );

/// A transfer between the entities and how each view counts it.
class TransferDetailScreen extends ConsumerWidget {
  const new({required this.transferId, super.key});

  static const documentKey = Key('transfer-document');

  final String transferId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfer = ref.watch(transferProvider(transferId));
    return Scaffold(
      appBar: AppBar(),
      body: switch (transfer) {
        AsyncData(:final value) => _Detail(transfer: value),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(transferProvider(transferId)),
        ),
        _ => const CdSkeleton(rows: 3),
      },
    );
  }
}

class _Detail extends StatelessWidget {
  const new({required this.transfer});

  final TransferDetail transfer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final local = transfer.at.toUtc().subtract(const Duration(hours: 3));
    final weekday = DateFormat.E(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(local).replaceAll('.', '');
    final day = CalendarDate.brazilToday(transfer.at);
    final title = switch (transfer.kind) {
      TransferKind.profitDistribution => l10n.transferProfitDistribution,
      TransferKind.proLabore => l10n.transferProLabore,
    };
    final secondary = AppTextStyles.bodyMd.copyWith(
      color: palette.onSurfaceVariant,
    );
    final views = [
      (
        EntityTone.company,
        l10n.entityCompanyShort,
        l10n.entityCompany,
        transfer.neutral
            ? l10n.countsCompanyNeutral
            : l10n.countsCompanyExpense,
      ),
      (
        EntityTone.personal,
        l10n.entityPersonalShort,
        l10n.entityPersonal,
        transfer.neutral
            ? l10n.countsPersonalNeutral
            : l10n.countsPersonalIncome,
      ),
      (
        EntityTone.consolidated,
        null,
        l10n.entityConsolidated,
        l10n.countsConsolidated,
      ),
    ];
    final document = transfer.document;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      children: [
        Center(
          child: CdIconTile(
            Symbols.sync_alt_rounded,
            size: 56,
            tone: context.tone(MoneyTone.transfer),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTextStyles.titleMd.copyWith(color: palette.onSurface),
        ),
        CdAmount(
          transfer.amount,
          size: CdAmountSize.lg,
          kind: CdAmountKind.transfer,
          textAlign: TextAlign.center,
        ),
        Text(
          l10n.transferWhen(
            weekday,
            day.dayMonth,
            brazilTime(transfer.at),
            transfer.rail,
          ),
          textAlign: TextAlign.center,
          style: secondary,
        ),
        const SizedBox(height: AppSpacing.xl),
        CdCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Party(party: transfer.from),
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm),
                child: Icon(
                  Symbols.south_rounded,
                  size: 20,
                  color: palette.onSurfaceVariant,
                ),
              ),
              _Party(party: transfer.to),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        CdSectionHeader(title: l10n.howItCounts, small: true),
        for (final (tone, short, name, line) in views)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                CdEntityBadge(entity: tone, label: short),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: AppTextStyles.titleSm.copyWith(
                          color: palette.onSurface,
                        ),
                      ),
                      Text(line, style: secondary),
                    ],
                  ),
                ),
                CdStatusBadge(
                  tone: MoneyTone.transfer,
                  label: transfer.neutral
                      ? l10n.neutralBadge
                      : l10n.countedBadge,
                ),
              ],
            ),
          ),
        const Divider(height: AppSpacing.xl),
        Row(
          children: [
            Icon(
              Symbols.category_rounded,
              size: 20,
              color: palette.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(l10n.categoryLabel, style: secondary)),
            Icon(
              Symbols.lock_rounded,
              size: 16,
              color: palette.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelLg.copyWith(color: palette.onSurface),
              ),
            ),
          ],
        ),
        if (document != null) ...[
          const SizedBox(height: AppSpacing.lg),
          CdCard(
            key: TransferDetailScreen.documentKey,
            onTap: () => showCdToast(
              context,
              icon: Symbols.picture_as_pdf_rounded,
              message: l10n.shareSoon,
            ),
            child: Row(
              children: [
                const CdIconTile(Symbols.picture_as_pdf_rounded, circle: false),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        document,
                        style: AppTextStyles.titleSm.copyWith(
                          color: palette.onSurface,
                        ),
                      ),
                      Text(l10n.distributionTaxFree, style: secondary),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Party extends StatelessWidget {
  const new({required this.party});

  final TransferParty party;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          EntityKindBadge(kind: party.owner),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  party.holder,
                  style: AppTextStyles.titleSm.copyWith(
                    color: palette.onSurface,
                  ),
                ),
                Text(
                  party.account,
                  style: AppTextStyles.bodyMd.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
