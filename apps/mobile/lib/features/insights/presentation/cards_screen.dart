import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/theme/app_chart_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/insights/cd_insight_card.dart';
import 'package:cashdeck/core/widgets/insights/cd_institution_logo.dart';
import 'package:cashdeck/core/widgets/insights/cd_progress_ring.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The current bill of each card and how much of each limit is in use.
class CardsScreen extends ConsumerWidget {
  const new({super.key});

  static const billsTabKey = Key('cards-tab-bills');
  static const limitsTabKey = Key('cards-tab-limits');
  static Key cardKey(String id) => Key('cards-card-$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final accounts = ref.watch(transactionAccountsProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.cardsTitle),
          bottom: TabBar(
            tabs: [
              Tab(key: billsTabKey, text: l10n.cardsBills),
              Tab(key: limitsTabKey, text: l10n.cardsLimits),
            ],
          ),
        ),
        body: switch (accounts) {
          AsyncData(:final value) => _cardsOf(l10n, value),
          AsyncError(:final error) => CdErrorState(
            failure: failureOf(error),
            onRetry: () => ref.invalidate(transactionAccountsProvider),
          ),
          _ => const CdSkeleton(),
        },
      ),
    );
  }

  Widget _cardsOf(AppLocalizations l10n, List<TransactionAccount> accounts) {
    final cards = [
      for (final account in accounts)
        if (account.type == AccountType.creditCard) account,
    ];
    if (cards.isEmpty) {
      return CdEmptyState(
        icon: Symbols.credit_card_rounded,
        title: l10n.cardsEmpty,
        message: l10n.cardsEmptyMessage,
      );
    }
    return TabBarView(
      children: [
        _Bills(cards: cards),
        _Limits(cards: cards),
      ],
    );
  }
}

String _cardName(TransactionAccount card) {
  final suffix = card.numberSuffix;
  return suffix == null ? card.name : '${card.name} •• $suffix';
}

EdgeInsets get _listPadding => const EdgeInsets.fromLTRB(
  AppSpacing.screenGutter,
  AppSpacing.md,
  AppSpacing.screenGutter,
  AppSpacing.xxl,
);

class _Bills extends StatelessWidget {
  const new({required this.cards});

  final List<TransactionAccount> cards;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final charts = context.charts;
    return ListView.separated(
      padding: _listPadding,
      itemCount: cards.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        final card = cards[index];
        final credit = card.credit;
        final closes = credit?.closesOn;
        final due = credit?.dueOn;
        final dates = switch ((closes, due)) {
          (final closes?, final due?) => l10n.cardsBillDates(
            closes.dayMonth,
            due.dayMonth,
          ),
          (_, final due?) => l10n.cardsBillDue(due.dayMonth),
          _ => l10n.cardsNoDates,
        };
        return CdInsightCard(
          key: CardsScreen.cardKey(card.id),
          child: Row(
            children: [
              CdInstitutionLogo(
                name: card.institution,
                colors: charts.at(index),
                imageUrl: card.logo?.imageUrl,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _cardName(card),
                      style: AppTextStyles.titleSm.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      dates,
                      style: AppTextStyles.bodyMd.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    l10n.cardsCurrentBill,
                    style: AppTextStyles.labelMd.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                  CdAmount(
                    Money(card.balance.cents.abs()),
                    size: CdAmountSize.row,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Limits extends ConsumerWidget {
  const new({required this.cards});

  final List<TransactionAccount> cards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final charts = context.charts;
    final hide = ref.watch(hideAmountsProvider);
    final lines = [for (final card in cards) ?card.credit];
    final limit = lines.fold(0, (sum, line) => sum + line.limit.cents);
    final used = lines.fold(0, (sum, line) => sum + line.used.cents);
    final percent = limit > 0 ? (used * 100 / limit).round() : 0;
    return ListView(
      padding: _listPadding,
      children: [
        CdInsightCard(
          child: Row(
            children: [
              CdProgressRing(
                size: 96,
                stroke: 10,
                semanticsLabel: l10n.cardsLimitSemantics(percent),
                parts: [
                  for (final (index, card) in cards.indexed)
                    if (card.credit case final credit? when limit > 0)
                      (credit.used.cents / limit, charts.at(index).fill),
                ],
                center: Text(
                  l10n.insightsPercent(percent),
                  style: AppTextStyles.titleMd.copyWith(
                    color: palette.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CdAmount(
                      Money(used),
                      size: CdAmountSize.lg,
                      textAlign: TextAlign.start,
                    ),
                    Text(
                      l10n.cardsUsedOfTotal,
                      style: AppTextStyles.bodyMd.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        for (final (index, card) in cards.indexed) ...[
          const SizedBox(height: AppSpacing.md),
          CdInsightCard(
            title: _cardName(card),
            child: _limitOf(context, l10n, card, index, hide: hide),
          ),
        ],
      ],
    );
  }

  Widget _limitOf(
    BuildContext context,
    AppLocalizations l10n,
    TransactionAccount card,
    int index, {
    required bool hide,
  }) {
    final palette = context.palette;
    final credit = card.credit;
    final muted = AppTextStyles.bodyMd.copyWith(
      color: palette.onSurfaceVariant,
    );
    if (credit == null || credit.limit.cents <= 0) {
      return Text(l10n.cardsNoLimit, style: muted);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: LinearProgressIndicator(
            value: (credit.used.cents / credit.limit.cents).clamp(0, 1),
            minHeight: 8,
            color: context.charts.at(index).fill,
            backgroundColor: palette.surfaceContainerHigh,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.cardsUsed(
            MoneyFormat.format(credit.used, hide: hide),
            MoneyFormat.format(credit.limit, hide: hide),
          ),
          style: AppTextStyles.labelLg.copyWith(color: palette.onSurface),
        ),
        Text(
          l10n.cardsAvailable(MoneyFormat.format(credit.available, hide: hide)),
          style: muted,
        ),
      ],
    );
  }
}
