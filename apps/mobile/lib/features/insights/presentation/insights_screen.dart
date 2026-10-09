import 'dart:math' as math;

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/app/shell/tab_app_bar.dart';
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
import 'package:cashdeck/core/widgets/inputs/cd_segmented.dart';
import 'package:cashdeck/core/widgets/insights/cd_column_bars.dart';
import 'package:cashdeck/core/widgets/insights/cd_comparison_pill.dart';
import 'package:cashdeck/core/widgets/insights/cd_insight_card.dart';
import 'package:cashdeck/core/widgets/insights/cd_insight_row.dart';
import 'package:cashdeck/core/widgets/insights/cd_progress_ring.dart';
import 'package:cashdeck/core/widgets/insights/cd_segment_bar.dart';
import 'package:cashdeck/core/widgets/layout/cd_key_value_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_refresh.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:cashdeck/features/insights/presentation/insights_controller.dart';
import 'package:cashdeck/features/insights/presentation/insights_labels.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transaction_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Análises: one month against the months before it.
class InsightsScreen extends ConsumerWidget {
  const new({super.key});

  static const previousKey = Key('insights-previous-month');
  static const nextKey = Key('insights-next-month');
  static const sixKey = Key('insights-months-6');
  static const twelveKey = Key('insights-months-12');
  static Key linkKey(String route) => Key('insights-link-$route');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = YearMonth.of(
      CalendarDate.brazilToday(ref.watch(clockProvider).now()),
    );
    final window = ref.watch(monthWindowProvider);
    final month = window.month ?? current;
    final controller = ref.read(monthWindowProvider.notifier);
    return Scaffold(
      appBar: const TabAppBar(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              children: [
                IconButton(
                  key: previousKey,
                  tooltip: l10n.insightsPreviousMonth,
                  icon: const Icon(Symbols.chevron_left_rounded),
                  onPressed: () =>
                      controller.show(month.add(-1), current: current),
                ),
                Expanded(
                  child: Text(
                    monthTitle(l10n, month),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.titleMd.copyWith(
                      color: context.palette.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  key: nextKey,
                  tooltip: l10n.insightsNextMonth,
                  icon: const Icon(Symbols.chevron_right_rounded),
                  onPressed: month.compareTo(current) < 0
                      ? () => controller.show(month.add(1), current: current)
                      : null,
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (ref.watch(monthlyInsightsProvider)) {
              AsyncData(:final value) => CdRefresh(
                providers: [monthlyInsightsProvider],
                child: _Analysis(insights: value, count: window.count),
              ),
              AsyncError(:final error) => CdErrorState(
                failure: failureOf(error),
                onRetry: () => ref.invalidate(monthlyInsightsProvider),
              ),
              _ => const CdSkeleton(),
            },
          ),
        ],
      ),
    );
  }
}

class _Analysis extends ConsumerWidget {
  const new({required this.insights, required this.count});

  final MonthlyInsights insights;
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final left = insights.leftThisMonth;
    final company = insights.companyToPersonal;
    final cards = <Widget>[
      _FlowCard(insights: insights, count: count),
      _SavingsCard(savings: insights.savings),
      _ChangesCard(rose: insights.rose, fell: insights.fell),
      _FixedCostCard(cost: insights.fixedCost),
      if (left != null) _LeftCard(left: left),
      if (company != null) _CompanyCard(company: company),
      if (insights.insights.isNotEmpty)
        CdInsightCard(
          title: l10n.insightsListTitle,
          child: Column(
            children: [
              for (final insight in insights.insights)
                _InsightLine(insight: insight),
            ],
          ),
        ),
      CdInsightCard(
        title: l10n.insightsMore,
        child: Column(
          children: [
            for (final (route, title, icon) in [
              (
                AppRoutes.installments,
                l10n.installmentsTitle,
                Symbols.event_repeat_rounded,
              ),
              (
                AppRoutes.subscriptions,
                l10n.subscriptionsTitle,
                Symbols.autorenew_rounded,
              ),
              (AppRoutes.cards, l10n.cardsTitle, Symbols.credit_card_rounded),
            ])
              CdListRow(
                key: InsightsScreen.linkKey(route),
                title: title,
                icon: icon,
                chevron: true,
                padding: EdgeInsets.zero,
                onTap: () => context.push(route).ignore(),
              ),
          ],
        ),
      ),
    ];
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sm,
        AppSpacing.screenGutter,
        AppSpacing.xxl,
      ),
      itemCount: cards.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (_, index) => cards[index],
    );
  }
}

class _InsightLine extends ConsumerWidget {
  const new({required this.insight});

  final Insight insight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return CdInsightRow(
      icon: insightIcon(insight),
      tone: insightTone(context.money, insight),
      sentence: insightSentence(
        l10n,
        insight,
        hide: ref.watch(hideAmountsProvider),
      ),
    );
  }
}

class _FlowCard extends ConsumerStatefulWidget {
  const new({required this.insights, required this.count});

  final MonthlyInsights insights;
  final int count;

  @override
  ConsumerState<_FlowCard> createState() => _FlowCardState();
}

class _FlowCardState extends ConsumerState<_FlowCard> {
  int? _selected;

  @override
  void didUpdateWidget(_FlowCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.insights != widget.insights) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final money = context.money;
    final months = widget.insights.months;
    final selected = _selected ?? months.length - 1;
    final result = months.elementAtOrNull(selected);
    return CdInsightCard(
      title: l10n.insightsFlowTitle,
      trailing: SizedBox(
        width: 128,
        child: CdSegmented<int>(
          segments: [
            CdSegment(6, l10n.insightsMonthsSix, key: InsightsScreen.sixKey),
            CdSegment(
              12,
              l10n.insightsMonthsTwelve,
              key: InsightsScreen.twelveKey,
            ),
          ],
          selected: widget.count,
          onChanged: ref.read(monthWindowProvider.notifier).count,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CdColumnBars(
            semanticsLabel: l10n.insightsFlowSemantics(months.length),
            selected: selected,
            onSelect: (index) => setState(() => _selected = index),
            columns: [
              for (final month in months)
                CdBarColumn(
                  label: shortMonth(l10n, month.month),
                  bars: [
                    (month.income.cents / 100, money.income),
                    (month.expenses.cents / 100, money.expense),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          CdSegmentLegend(
            entries: [
              (money.income, l10n.insightsIncome),
              (money.expense, l10n.insightsExpenses),
            ],
          ),
          if (result != null) ...[
            const SizedBox(height: AppSpacing.md),
            CdKeyValueRow(
              label: l10n.insightsIncome,
              value: CdAmount(result.income, size: CdAmountSize.row),
            ),
            CdKeyValueRow(
              label: l10n.insightsExpenses,
              value: CdAmount(result.expenses, size: CdAmountSize.row),
            ),
            CdKeyValueRow(
              label: l10n.insightsResult,
              strong: true,
              value: CdAmount(result.result, size: CdAmountSize.row),
            ),
          ],
        ],
      ),
    );
  }
}

class _SavingsCard extends StatelessWidget {
  const new({required this.savings});

  final SavingsRate savings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final percent = savings.percent;
    final average = savings.averagePercent;
    final caption = average == null
        ? l10n.insightsSavingsNoAverage
        : l10n.insightsSavingsCaption(average);
    return CdInsightCard(
      title: l10n.insightsSavingsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                percent == null
                    ? l10n.insightsSavingsNoIncome
                    : l10n.insightsPercent(percent),
                style:
                    (percent == null
                            ? AppTextStyles.titleSm
                            : AppTextStyles.amountLg)
                        .copyWith(color: palette.onSurface),
              ),
              const Spacer(),
              if (percent != null && average != null)
                CdComparisonPill(
                  direction: percent - average,
                  value: l10n.insightsPercent((percent - average).abs()),
                  goodWhen: GoodWhen.up,
                ),
            ],
          ),
          if (percent != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              caption,
              style: AppTextStyles.bodyMd.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          CdColumnBars(
            height: 56,
            semanticsLabel: l10n.insightsSavingsTitle,
            selected: savings.trend.length - 1,
            columns: [
              for (final (month, rate) in savings.trend)
                CdBarColumn(
                  label: shortMonth(l10n, month),
                  bars: [
                    ((rate ?? 0).clamp(0, 100).toDouble(), palette.primary),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChangesCard extends ConsumerWidget {
  const new({required this.rose, required this.fell});

  final List<CategoryChange> rose;
  final List<CategoryChange> fell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hide = ref.watch(hideAmountsProvider);
    final changes = [...rose, ...fell];
    return CdInsightCard(
      title: l10n.insightsChangesTitle,
      child: changes.isEmpty
          ? Text(
              l10n.insightsChangesEmpty,
              style: AppTextStyles.bodyMd.copyWith(
                color: context.palette.onSurfaceVariant,
              ),
            )
          : Column(
              children: [
                for (final change in changes)
                  _changeRow(l10n, change, hide: hide),
              ],
            ),
    );
  }

  Widget _changeRow(
    AppLocalizations l10n,
    CategoryChange change, {
    required bool hide,
  }) {
    final category = Category(
      id: change.categoryId,
      key: change.key,
      name: change.name,
    );
    return CdListRow(
      title: categoryName(l10n, category),
      subtitle: l10n.insightsChangeAverage(
        MoneyFormat.whole(change.average, hide: hide),
      ),
      icon: categoryIcon(category),
      padding: EdgeInsets.zero,
      trailing: CdComparisonPill(
        direction: change.delta.cents.sign,
        value: MoneyFormat.whole(
          change.delta,
          hide: hide,
        ).replaceFirst(MoneyFormat.minus, ''),
      ),
    );
  }
}

class _FixedCostCard extends StatelessWidget {
  const new({required this.cost});

  final FixedCost cost;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final series = context.charts.series;
    final share = cost.sharePercent;
    double part(Money value) =>
        cost.income.cents > 0 ? value.cents / cost.income.cents : 0;
    final entries = [
      (cost.subscriptions, series[0].fill, l10n.insightsFixedSubscriptions),
      (cost.installments, series[1].fill, l10n.insightsFixedInstallments),
      (cost.bills, series[2].fill, l10n.insightsFixedBills),
    ];
    return CdInsightCard(
      title: l10n.insightsFixedTitle,
      child: Row(
        children: [
          CdProgressRing(
            size: 96,
            stroke: 10,
            semanticsLabel: l10n.insightsFixedSemantics(share ?? 0),
            parts: [
              for (final (value, color, _) in entries) (part(value), color),
            ],
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.insightsPercent(share ?? 0),
                  style: AppTextStyles.titleMd.copyWith(
                    color: palette.onSurface,
                  ),
                ),
                Text(
                  l10n.insightsFixedShare,
                  style: AppTextStyles.labelMd.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              children: [
                for (final (value, color, label) in entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            label,
                            style: AppTextStyles.bodyMd.copyWith(
                              color: palette.onSurfaceVariant,
                            ),
                          ),
                        ),
                        CdAmount(value, size: CdAmountSize.sm),
                      ],
                    ),
                  ),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.installmentsTotal,
                        style: AppTextStyles.labelLg.copyWith(
                          color: palette.onSurface,
                        ),
                      ),
                    ),
                    CdAmount(cost.total, size: CdAmountSize.sm),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LeftCard extends StatelessWidget {
  const new({required this.left});

  final LeftThisMonth left;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final money = context.money;
    final balance = math.max(1, left.balance.cents);
    double part(Money value) => value.cents.abs() / balance;
    return CdInsightCard(
      title: l10n.insightsLeftTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CdAmount(
            left.left,
            size: CdAmountSize.lg,
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: AppSpacing.md),
          CdSegmentBar(
            semanticsLabel: l10n.insightsLeftTitle,
            segments: [
              CdBarSegment(part(left.billsDue), money.overdue),
              CdBarSegment(part(left.cardBill), money.scheduled),
              CdBarSegment(
                left.left.cents > 0 ? part(left.left) : 0,
                money.paid,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          CdKeyValueRow(
            label: l10n.insightsLeftBalance,
            value: CdAmount(left.balance, size: CdAmountSize.row),
          ),
          CdKeyValueRow(
            label: l10n.insightsLeftBills,
            value: CdAmount(-left.billsDue, size: CdAmountSize.row),
          ),
          CdKeyValueRow(
            label: l10n.insightsLeftCard,
            value: CdAmount(-left.cardBill, size: CdAmountSize.row),
          ),
          CdKeyValueRow(
            label: l10n.insightsLeftResult,
            strong: true,
            value: CdAmount(left.left, size: CdAmountSize.row),
          ),
        ],
      ),
    );
  }
}

class _CompanyCard extends StatelessWidget {
  const new({required this.company});

  final CompanyToPersonal company;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CdInsightCard(
      title: l10n.insightsCompanyTitle,
      child: Column(
        children: [
          CdKeyValueRow(
            label: l10n.insightsCompanyTransfers,
            value: CdAmount(company.transfers, size: CdAmountSize.row),
          ),
          CdKeyValueRow(
            label: l10n.insightsCompanyTaxes,
            value: CdAmount(company.taxes, size: CdAmountSize.row),
          ),
        ],
      ),
    );
  }
}
