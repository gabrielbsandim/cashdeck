import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/theme/app_chart_colors.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/inputs/cd_segmented.dart';
import 'package:cashdeck/core/widgets/insights/cd_comparison_pill.dart';
import 'package:cashdeck/core/widgets/insights/cd_flow_bars.dart';
import 'package:cashdeck/core/widgets/insights/cd_insight_card.dart';
import 'package:cashdeck/core/widgets/insights/cd_progress_ring.dart';
import 'package:cashdeck/core/widgets/insights/cd_segment_bar.dart';
import 'package:cashdeck/core/widgets/insights/cd_spend_chart.dart';
import 'package:cashdeck/core/widgets/insights/cd_widget_tile.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/features/home/presentation/home_widgets_controller.dart';
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

/// How many institutions the balance bar names before grouping the rest.
const _namedInstitutions = 4;

/// The cash balance split by institution, the reserve left out as on the
/// total above it.
class InstitutionBar extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final charts = context.charts;
    final accounts =
        ref.watch(transactionAccountsProvider).value ??
        const <TransactionAccount>[];
    final totals = <String, int>{};
    for (final account in accounts) {
      if (!account.isCash || account.isReserve) continue;
      if (account.balance.cents <= 0) continue;
      totals.update(
        account.institution,
        (sum) => sum + account.balance.cents,
        ifAbsent: () => account.balance.cents,
      );
    }
    if (totals.isEmpty) return const SizedBox.shrink();
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final named = sorted.take(_namedInstitutions).toList();
    final rest = sorted
        .skip(_namedInstitutions)
        .fold(0, (sum, entry) => sum + entry.value);
    final parts = [
      for (final (index, entry) in named.indexed)
        (entry.key, entry.value.toDouble(), charts.at(index).fill),
      if (rest > 0) (l10n.homeOtherInstitutions, rest.toDouble(), charts.grid),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CdSegmentBar(
          semanticsLabel: l10n.homeInstitutionsSemantics,
          segments: [
            for (final (_, value, color) in parts) CdBarSegment(value, color),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        CdSegmentLegend(
          entries: [for (final (name, _, color) in parts) (color, name)],
        ),
      ],
    );
  }
}

/// Spending of the chosen period against the one before, then where it went.
class HomeSpendCard extends ConsumerWidget {
  const new({super.key});

  static Key periodKey(InsightPeriod period) =>
      Key('home-period-${period.name}');
  static const retryKey = Key('home-insights-retry');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final period = ref.watch(insightPeriodProvider);
    return CdInsightCard(
      title: l10n.homeSpendTitle,
      trailing: SizedBox(
        width: 200,
        child: CdSegmented<InsightPeriod>(
          segments: [
            for (final value in InsightPeriod.values)
              CdSegment(value, periodLabel(l10n, value), key: periodKey(value)),
          ],
          selected: period,
          onChanged: (value) =>
              ref.read(insightPeriodProvider.notifier).period = value,
        ),
      ),
      child: switch (ref.watch(insightsOverviewProvider)) {
        AsyncData(:final value) => _Spend(overview: value),
        AsyncError() => _Failed(
          onRetry: () => ref.invalidate(insightsOverviewProvider),
        ),
        _ => const _Pending(height: 220),
      },
    );
  }
}

class _Failed extends StatelessWidget {
  const new({required this.onRetry});

  final VoidCallback onRetry;

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
          key: HomeSpendCard.retryKey,
          onPressed: onRetry,
          child: Text(l10n.retryButton),
        ),
      ],
    );
  }
}

class _Pending extends StatelessWidget {
  const new({required this.height});

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

class _Spend extends StatelessWidget {
  const new({required this.overview});

  final InsightsOverview overview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spend = overview.spend;
    final change = spend.changePercent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CdAmount(
          spend.total,
          size: CdAmountSize.lg,
          textAlign: TextAlign.start,
        ),
        if (change != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: CdComparisonPill(
              direction: change.sign,
              value: l10n.insightsPercent(change.abs()),
              label: l10n.homeSpendVsPrevious,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        CdSpendChart(
          semanticsLabel: l10n.homeSpendSemantics,
          todayLabel: l10n.relativeToday,
          current: [
            for (final point in spend.series) point.cumulative.cents / 100,
          ],
          previous: [
            for (final point in spend.previousSeries)
              point.cumulative.cents / 100,
          ],
          xLabels: [overview.range.from.dayMonth, overview.range.to.dayMonth],
        ),
        if (spend.topMerchants.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.homeTopMerchants,
            style: AppTextStyles.labelLg.copyWith(
              color: context.palette.onSurfaceVariant,
            ),
          ),
          for (final merchant in spend.topMerchants)
            CdListRow(
              title: merchant.name,
              subtitle: l10n.homeMerchantCount(merchant.count),
              icon: Symbols.storefront_rounded,
              padding: EdgeInsets.zero,
              trailing: CdAmount(merchant.total, size: CdAmountSize.row),
            ),
        ],
      ],
    );
  }
}

/// Where the period's spending went, one slice per category.
class HomeCategoryCard extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final overview = ref.watch(insightsOverviewProvider).value;
    if (overview == null || overview.categories.isEmpty) {
      return const SizedBox.shrink();
    }
    final palette = context.palette;
    final charts = context.charts;
    Color colorOf(int index, CategoryShare share) =>
        share.categoryId == null ? charts.grid : charts.at(index).fill;
    String nameOf(CategoryShare share) {
      final id = share.categoryId;
      final name = share.name;
      if (id == null || name == null) return l10n.transactionUncategorized;
      return categoryName(l10n, Category(id: id, key: share.key, name: name));
    }

    return CdInsightCard(
      title: l10n.homeCategoryTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CdSegmentBar(
            semanticsLabel: l10n.homeCategorySemantics,
            segments: [
              for (final (index, share) in overview.categories.indexed)
                CdBarSegment(
                  share.total.cents.toDouble(),
                  colorOf(index, share),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          for (final (index, share) in overview.categories.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colorOf(index, share),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      nameOf(share),
                      style: AppTextStyles.bodyMd.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    l10n.insightsPercent(share.sharePercent),
                    style: AppTextStyles.labelMd.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  CdAmount(share.total, size: CdAmountSize.sm),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Income against spending in the period and what was left.
class HomeFlowCard extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final overview = ref.watch(insightsOverviewProvider).value;
    if (overview == null) return const SizedBox.shrink();
    final flow = overview.flow;
    final hide = ref.watch(hideAmountsProvider);
    final result = MoneyFormat.format(
      flow.result,
      hide: hide,
    ).replaceFirst(MoneyFormat.minus, '');
    final left = flow.result.cents >= 0;
    return CdInsightCard(
      title: l10n.homeFlowTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CdFlowBars(
            income: flow.income.cents / 100,
            expenses: flow.expenses.cents / 100,
            incomeLabel: l10n.insightsIncome,
            expensesLabel: l10n.insightsExpenses,
            incomeAmount: CdAmount(flow.income, size: CdAmountSize.sm),
            expensesAmount: CdAmount(flow.expenses, size: CdAmountSize.sm),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            left ? l10n.homeFlowLeft(result) : l10n.homeFlowShort(result),
            style: AppTextStyles.titleSm.copyWith(
              color: left ? context.money.paid : context.money.overdue,
            ),
          ),
        ],
      ),
    );
  }
}

/// The summary grid, two tiles a row, in the order the user picked.
class HomeSummaryGrid extends ConsumerWidget {
  const new({required this.reserve, super.key});

  static const editKey = Key('home-edit-widgets');
  static Key tileKey(HomeWidget widget) => Key('home-tile-${widget.name}');
  static Key toggleKey(HomeWidget widget) =>
      Key('home-tile-toggle-${widget.name}');

  final Money? reserve;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final visible = ref.watch(homeWidgetsProvider).visible;
    final tiles = [
      for (final widget in visible) _tile(context, ref, l10n, widget),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CdSectionHeader(
          title: l10n.homeSummaryTitle,
          actionLabel: l10n.homeEditWidgets,
          actionKey: editKey,
          onAction: () => _editWidgets(context),
        ),
        const SizedBox(height: AppSpacing.md),
        for (var start = 0; start < tiles.length; start += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: tiles[start]),
                  const SizedBox(width: AppSpacing.md),
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

  Widget _tile(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    HomeWidget widget,
  ) {
    final charts = context.charts;
    final overview = ref.watch(insightsOverviewProvider).value;
    final cards = overview?.cards;
    void open(String route) => context.push(route).ignore();
    Widget amount(Money? value) => value == null
        ? const _Pending(height: 24)
        : CdAmount(value, textAlign: TextAlign.start);
    return switch (widget) {
      HomeWidget.cardBill => CdWidgetTile(
        key: tileKey(widget),
        icon: Symbols.credit_card_rounded,
        colors: charts.at(0),
        title: l10n.homeWidgetCardBill,
        value: amount(overview == null ? null : cards?.bill ?? const Money(0)),
        caption: switch (cards?.dueOn) {
          final due? => l10n.cardsBillDue(due.dayMonth),
          _ => l10n.cardsNoDates,
        },
        onTap: () => open(AppRoutes.cards),
      ),
      HomeWidget.installments => CdWidgetTile(
        key: tileKey(widget),
        icon: Symbols.event_repeat_rounded,
        colors: charts.at(1),
        title: l10n.homeWidgetInstallments,
        value: amount(switch (ref.watch(installmentsProvider)) {
          AsyncData(:final value) =>
            value.months.firstOrNull?.$2 ?? const Money(0),
          _ => null,
        }),
        caption: l10n.homeNextMonth,
        onTap: () => open(AppRoutes.installments),
      ),
      HomeWidget.subscriptions => CdWidgetTile(
        key: tileKey(widget),
        icon: Symbols.autorenew_rounded,
        colors: charts.at(2),
        title: l10n.homeWidgetSubscriptions,
        value: amount(
          ref.watch(subscriptionsControllerProvider).value?.monthly,
        ),
        caption: l10n.subscriptionsPerMonth,
        onTap: () => open(AppRoutes.subscriptions),
      ),
      HomeWidget.creditUsed => CdWidgetTile(
        key: tileKey(widget),
        icon: Symbols.donut_large_rounded,
        colors: charts.at(3),
        title: l10n.homeWidgetCreditUsed,
        value: Text(
          l10n.insightsPercent(cards?.usedPercent ?? 0),
          style: AppTextStyles.titleMd.copyWith(
            color: context.palette.onSurface,
          ),
        ),
        caption: l10n.cardsUsedOfTotal,
        visual: CdProgressRing(
          size: 36,
          stroke: 5,
          semanticsLabel: l10n.cardsLimitSemantics(cards?.usedPercent ?? 0),
          parts: [((cards?.usedPercent ?? 0) / 100, charts.at(3).fill)],
        ),
        onTap: () => open(AppRoutes.cards),
      ),
      HomeWidget.billsDue => CdWidgetTile(
        key: tileKey(widget),
        icon: Symbols.event_upcoming_rounded,
        colors: charts.at(4),
        title: l10n.homeWidgetBillsDue,
        value: amount(overview?.billsDue.total),
        caption: l10n.homeBillsDueCaption(
          overview?.billsDue.count ?? 0,
          overview?.billsDue.days ?? 7,
        ),
        onTap: () => context.go(AppRoutes.bills),
      ),
      HomeWidget.reserve => CdWidgetTile(
        key: tileKey(widget),
        icon: Symbols.savings_rounded,
        colors: charts.at(5),
        title: l10n.homeWidgetReserve,
        value: amount(reserve ?? const Money(0)),
        caption: l10n.homeReserveCaption,
        onTap: () => open(AppRoutes.balances),
      ),
    };
  }
}

String homeWidgetLabel(AppLocalizations l10n, HomeWidget widget) =>
    switch (widget) {
      HomeWidget.cardBill => l10n.homeWidgetCardBill,
      HomeWidget.installments => l10n.homeWidgetInstallments,
      HomeWidget.subscriptions => l10n.homeWidgetSubscriptions,
      HomeWidget.creditUsed => l10n.homeWidgetCreditUsed,
      HomeWidget.billsDue => l10n.homeWidgetBillsDue,
      HomeWidget.reserve => l10n.homeWidgetReserve,
    };

Future<void> _editWidgets(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showCdBottomSheet<void>(
    context,
    title: l10n.homeEditWidgets,
    builder: (_) => const _WidgetEditor(),
  );
}

class _WidgetEditor extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final layout = ref.watch(homeWidgetsProvider);
    final controller = ref.read(homeWidgetsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.homeEditWidgetsHint,
          style: AppTextStyles.bodyMd.copyWith(
            color: context.palette.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: controller.move,
          children: [
            for (final (index, widget) in layout.order.indexed)
              CdListRow(
                key: ValueKey(widget),
                title: homeWidgetLabel(l10n, widget),
                padding: EdgeInsets.zero,
                leading: ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Symbols.drag_indicator_rounded),
                ),
                trailing: Switch(
                  key: HomeSummaryGrid.toggleKey(widget),
                  value: !layout.hidden.contains(widget),
                  onChanged: (_) => controller.toggle(widget),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
