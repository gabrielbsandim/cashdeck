import 'dart:math' as math;

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/theme/app_chart_colors.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/charts/cd_bar_chart.dart';
import 'package:cashdeck/core/widgets/charts/cd_donut.dart';
import 'package:cashdeck/core/widgets/charts/cd_line_chart.dart';
import 'package:cashdeck/core/widgets/feedback/cd_haptics.dart';
import 'package:cashdeck/core/widgets/inputs/cd_segmented.dart';
import 'package:cashdeck/core/widgets/insights/cd_insight_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_key_value_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_refresh.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/home/presentation/home_labels.dart';
import 'package:cashdeck/features/outlook/domain/net_worth.dart';
import 'package:cashdeck/features/outlook/presentation/net_worth_card.dart';
import 'package:cashdeck/features/outlook/presentation/outlook_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Net worth over time: the total and how it moved, the curve over the
/// chosen window, assets against liabilities per month, and what each
/// entity holds by kind.
class NetWorthScreen extends ConsumerWidget {
  const new({super.key});

  static const totalKey = Key('net-worth-total');
  static const periodKey = Key('net-worth-period');
  static const assetsKey = Key('net-worth-assets');
  static Key entityKey(EntityKind kind) => Key('net-worth-entity-${kind.name}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.netWorthTitle)),
      // The last value stays up while the other window loads.
      body: switch (ref.watch(netWorthProvider)) {
        AsyncValue(:final value?) when value.isEmpty => CdEmptyState(
          icon: Symbols.account_balance_rounded,
          title: l10n.netWorthEmpty,
          message: l10n.netWorthEmptyMessage,
        ),
        AsyncValue(:final value?) => CdRefresh(
          providers: [netWorthProvider],
          child: _History(worth: value),
        ),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(netWorthProvider),
        ),
        _ => const CdSkeleton(),
      },
    );
  }
}

class _History extends ConsumerWidget {
  const new({required this.worth});

  final NetWorth worth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final period = ref.watch(netWorthPeriodProvider);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.md,
        AppSpacing.screenGutter,
        AppSpacing.xxl,
      ),
      children: [
        CdAmount(
          worth.current.total,
          key: NetWorthScreen.totalKey,
          size: CdAmountSize.xl,
          textAlign: TextAlign.start,
          countUp: true,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            NetWorthChangePill(
              change: worth.fromLastMonth,
              label: l10n.netWorthFromLastMonth,
            ),
            NetWorthChangePill(
              change: worth.fromYearAgo,
              label: l10n.netWorthFromYearAgo,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        CdSegmented<NetWorthPeriod>(
          key: NetWorthScreen.periodKey,
          segments: [
            CdSegment(NetWorthPeriod.sixMonths, l10n.netWorthPeriodSix),
            CdSegment(NetWorthPeriod.twelveMonths, l10n.netWorthPeriodTwelve),
          ],
          selected: period,
          onChanged: (chosen) {
            CdHaptics.selection();
            ref.read(netWorthPeriodProvider.notifier).period = chosen;
          },
        ),
        if (worth.series.length > 1) ...[
          const SizedBox(height: AppSpacing.md),
          CdInsightCard(child: _Curve(worth: worth)),
          const SizedBox(height: AppSpacing.md),
          CdInsightCard(
            title: l10n.netWorthHistoryTitle,
            child: _Bars(series: worth.series),
          ),
        ],
        for (final entity in worth.entities) ...[
          const SizedBox(height: AppSpacing.md),
          CdInsightCard(
            key: NetWorthScreen.entityKey(entity.kind),
            title: switch (entity.kind) {
              EntityKind.personal => l10n.entityPersonal,
              EntityKind.company => l10n.entityCompany,
            },
            child: _Composition(composition: entity.current),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        CdInsightCard(
          child: CdListRow(
            key: NetWorthScreen.assetsKey,
            title: l10n.assetsTitle,
            subtitle: l10n.netWorthAssetsLink,
            icon: Symbols.real_estate_agent_rounded,
            chevron: true,
            padding: EdgeInsets.zero,
            onTap: () => context.push(AppRoutes.assets).ignore(),
          ),
        ),
      ],
    );
  }
}

class _Curve extends ConsumerWidget {
  const new({required this.worth});

  final NetWorth worth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hide = ref.watch(hideAmountsProvider);
    final first = worth.series.first;
    final last = worth.series.last;
    return CdLineChart(
      height: 160,
      values: [for (final point in worth.series) point.total.cents / 100],
      xLabels: [monthShort(context, first.on), l10n.relativeTodayTitle],
      pointLabel: (index) {
        final point = worth.series[index];
        return '${point.on.dayMonth} · '
            '${MoneyFormat.format(point.total, hide: hide)}';
      },
      semanticsLabel: l10n.netWorthChartSemantics(
        MoneyFormat.format(first.total, hide: hide),
        monthShort(context, first.on),
        MoneyFormat.format(last.total, hide: hide),
      ),
    );
  }
}

class _Bars extends ConsumerWidget {
  const new({required this.series});

  final List<NetWorthPoint> series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hide = ref.watch(hideAmountsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CdBarChart(
          groups: [
            for (final point in series)
              // An overdrawn account can push assets below zero; a bar cannot.
              CdBarGroup(
                monthShort(context, point.on),
                math.max(0, point.assets.cents) / 100,
                math.max(0, point.liabilities.cents) / 100,
              ),
          ],
          incomeLabel: l10n.netWorthAssets,
          expenseLabel: l10n.netWorthLiabilities,
          semanticsLabel: l10n.netWorthBarsSemantics,
          groupLabel: (index) {
            final point = series[index];
            final assets = MoneyFormat.format(point.assets, hide: hide);
            final debts = MoneyFormat.format(point.liabilities, hide: hide);
            return [
              monthShort(context, point.on),
              '${l10n.netWorthAssets} $assets',
              '${l10n.netWorthLiabilities} $debts',
            ].join('\n');
          },
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.netWorthHistoryHint,
          style: AppTextStyles.bodyMd.copyWith(
            color: context.palette.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Composition extends ConsumerWidget {
  const new({required this.composition});

  final NetWorthComposition composition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hide = ref.watch(hideAmountsProvider);
    final charts = context.charts;
    final parts = [
      (l10n.netWorthCash, composition.cash, charts.at(0).fill),
      (l10n.netWorthInvestments, composition.investments, charts.at(1).fill),
      (l10n.netWorthRealEstate, composition.realEstate, charts.at(2).fill),
      (l10n.netWorthVehicles, composition.vehicles, charts.at(3).fill),
      (l10n.netWorthOtherAssets, composition.otherAssets, charts.at(4).fill),
    ];
    final debts = [
      (l10n.netWorthCardDebt, composition.cardDebt, context.money.expense),
      (l10n.netWorthLoanDebt, composition.loanDebt, context.money.overdue),
    ];
    final whole = composition.assets.cents + composition.liabilities.cents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (whole > 0) ...[
          Center(
            child: CdDonut(
              slices: [
                for (final (label, amount, color) in [...parts, ...debts])
                  if (amount.cents > 0)
                    CdDonutSlice(label, amount.cents / whole, color),
              ],
              centerValue: MoneyFormat.format(composition.total, hide: hide),
              centerCaption: l10n.netWorthNet,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        // Cash and investments always show; a kind of good only once owned.
        for (final (index, (label, amount, _)) in parts.indexed)
          if (index < 2 || amount.cents != 0)
            CdKeyValueRow(label: label, value: CdAmount(amount)),
        for (final (index, (label, amount, _)) in debts.indexed)
          if (index == 0 || amount.cents != 0)
            CdKeyValueRow(
              label: label,
              value: CdAmount(amount, kind: CdAmountKind.expense),
            ),
        CdKeyValueRow(
          label: l10n.netWorthTitle,
          strong: true,
          value: CdAmount(
            composition.total,
            color: composition.total.isNegative ? context.money.expense : null,
          ),
        ),
      ],
    );
  }
}
