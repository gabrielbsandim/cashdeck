import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/theme/app_chart_colors.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/core/widgets/inputs/cd_filter_chip.dart';
import 'package:cashdeck/core/widgets/insights/cd_column_bars.dart';
import 'package:cashdeck/core/widgets/insights/cd_insight_card.dart';
import 'package:cashdeck/core/widgets/insights/cd_progress_ring.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/money/cd_transaction_row.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:cashdeck/features/insights/presentation/insights_controller.dart';
import 'package:cashdeck/features/insights/presentation/insights_labels.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transaction_labels.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The bills of each card, newest first, and how much of each limit is in
/// use.
class CardsScreen extends ConsumerWidget {
  const new({super.key});

  static const billsTabKey = Key('cards-tab-bills');
  static const limitsTabKey = Key('cards-tab-limits');
  static const seeInBillsKey = Key('cards-see-in-bills');
  static const importKey = Key('cards-import');
  static const chargesRetryKey = Key('cards-charges-retry');
  static Key cardKey(String id) => Key('cards-card-$id');
  static Key chargeKey(String id) => Key('cards-charge-$id');

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
        const _Bills(),
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

class _Bills extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_Bills> createState() => _BillsState();
}

class _BillsState extends ConsumerState<_Bills> {
  int _card = 0;
  int? _bill;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (ref.watch(cardBillsProvider)) {
      AsyncData(:final value) when value.isEmpty => ListView(
        padding: _listPadding,
        children: [
          CdEmptyState(
            icon: Symbols.receipt_long_rounded,
            title: l10n.cardsBills,
            message: l10n.cardsNoBills,
          ),
          const _ImportLink(),
        ],
      ),
      AsyncData(:final value) => _billsOf(
        context,
        value[_card.clamp(0, value.length - 1)],
        value,
      ),
      AsyncError(:final error) => CdErrorState(
        failure: failureOf(error),
        onRetry: () => ref.invalidate(cardBillsProvider),
      ),
      _ => const CdSkeleton(),
    };
  }

  Widget _billsOf(BuildContext context, CardBills card, List<CardBills> cards) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final index = _bill ?? card.focus;
    final bill = index == null ? null : card.bills[index];
    return ListView(
      padding: _listPadding,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final (position, item) in cards.indexed)
              CdFilterChip(
                key: CardsScreen.cardKey(item.accountId),
                label: _billCardName(item),
                selected: position == _card,
                onTap: () => setState(() {
                  _card = position;
                  _bill = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (bill == null || index == null)
          Text(
            l10n.cardsNoBills,
            style: AppTextStyles.bodyMd.copyWith(
              color: palette.onSurfaceVariant,
            ),
          )
        else ...[
          _BillCard(
            card: card,
            bill: bill,
            selected: index,
            onSelect: (picked) => setState(() => _bill = picked),
          ),
          const SizedBox(height: AppSpacing.lg),
          CdSectionHeader(title: l10n.cardsCharges, small: true),
          const SizedBox(height: AppSpacing.xs),
          _Charges(charges: (accountId: card.accountId, range: bill.range)),
        ],
        const SizedBox(height: AppSpacing.md),
        const _ImportLink(),
      ],
    );
  }
}

String _billCardName(CardBills card) {
  final suffix = card.suffix;
  return suffix == null ? card.name : '${card.name} •• $suffix';
}

class _BillCard extends ConsumerWidget {
  const new({
    required this.card,
    required this.bill,
    required this.selected,
    required this.onSelect,
  });

  final CardBills card;
  final CardBill bill;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final hide = ref.watch(hideAmountsProvider);
    final today = CalendarDate.brazilToday(ref.watch(clockProvider).now());
    final month = monthName(l10n, YearMonth.of(bill.dueOn));
    final state = switch (bill.state) {
      CardBillState.open => l10n.cardsStateOpen,
      CardBillState.closed => l10n.cardsStateClosed,
      CardBillState.past => l10n.cardsStatePast,
    };
    final closes = bill.closesOn?.dayMonth;
    final due = bill.dueOn.dayMonth;
    final (headline, dates) = switch (bill.state) {
      CardBillState.closed => (
        l10n.cardsDueIn(today.daysUntil(bill.dueOn)),
        closes == null ? null : l10n.cardsClosedDates(closes, due),
      ),
      CardBillState.open => (
        closes == null
            ? l10n.cardsBillDue(due)
            : l10n.cardsBillDates(closes, due),
        null,
      ),
      CardBillState.past => (l10n.cardsPastDue(due), null),
    };
    final tone = bill.state == CardBillState.closed
        ? context.money.pending
        : palette.onSurfaceVariant;
    final history = card.bills.reversed.toList();
    final average = card.average();
    final muted = AppTextStyles.bodyMd.copyWith(
      color: palette.onSurfaceVariant,
    );
    return CdInsightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${l10n.cardsBillOf(month)} · $state',
            style: AppTextStyles.labelMd.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          CdAmount(
            bill.total,
            size: CdAmountSize.lg,
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Icon(Symbols.schedule_rounded, size: 16, color: tone),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  headline,
                  style: AppTextStyles.labelLg.copyWith(color: tone),
                ),
              ),
            ],
          ),
          if (dates != null) Text(dates, style: muted),
          if (history.length > 1) ...[
            const SizedBox(height: AppSpacing.md),
            CdColumnBars(
              height: 96,
              semanticsLabel: l10n.cardsHistorySemantics,
              selected: history.length - 1 - selected,
              onSelect: (picked) => onSelect(history.length - 1 - picked),
              columns: [
                for (final item in history)
                  CdBarColumn(
                    label: shortMonth(l10n, YearMonth.of(item.dueOn)),
                    bars: [(item.total.cents / 100, palette.primary)],
                  ),
              ],
            ),
          ],
          if (average != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.cardsAverage(
                card.averaged(),
                MoneyFormat.format(average, hide: hide),
              ),
              style: muted,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            key: CardsScreen.seeInBillsKey,
            onPressed: () => context.go(AppRoutes.bills),
            icon: const Icon(Symbols.event_upcoming_rounded),
            label: Text(l10n.cardsSeeInBills),
          ),
        ],
      ),
    );
  }
}

class _Charges extends ConsumerWidget {
  const new({required this.charges});

  final BillCharges charges;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final muted = AppTextStyles.bodyMd.copyWith(
      color: context.palette.onSurfaceVariant,
    );
    final categories = ref.watch(categoriesProvider).value;
    return switch (ref.watch(billChargesProvider(charges))) {
      AsyncData(:final value) when value.isEmpty => Text(
        l10n.cardsNoCharges,
        style: muted,
      ),
      AsyncData(:final value) => Column(
        children: [
          for (final transaction in value)
            CdTransactionRow(
              key: CardsScreen.chargeKey(transaction.id),
              icon: categoryIcon(
                categoryOf(transaction, categories ?? const []),
              ),
              title: transaction.displayName,
              subtitle: [
                transactionCategoryLabel(l10n, transaction, categories),
                ?transaction.installment?.label,
              ].join(' · '),
              amount: transaction.amount,
              kind: amountKindOf(transaction),
              onTap: () => context.push(
                AppRoutes.transaction(transaction.id),
                extra: transaction,
              ),
            ),
        ],
      ),
      AsyncError() => Row(
        children: [
          Expanded(child: Text(l10n.homeSectionFailed, style: muted)),
          TextButton(
            key: CardsScreen.chargesRetryKey,
            onPressed: () => ref.invalidate(billChargesProvider(charges)),
            child: Text(l10n.retryButton),
          ),
        ],
      ),
      _ => const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

class _ImportLink extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return CdInsightCard(
      key: CardsScreen.importKey,
      onTap: () => context.push(AppRoutes.cardImport),
      child: Row(
        children: [
          Icon(Symbols.upload_file_rounded, color: palette.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.cardsImportTitle,
                  style: AppTextStyles.titleSm.copyWith(
                    color: palette.onSurface,
                  ),
                ),
                Text(
                  l10n.cardsImportMessage,
                  style: AppTextStyles.bodyMd.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(Symbols.chevron_right_rounded, color: palette.onSurfaceVariant),
        ],
      ),
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
