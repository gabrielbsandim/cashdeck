import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/theme/app_chart_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/insights/cd_insight_card.dart';
import 'package:cashdeck/core/widgets/insights/cd_institution_logo.dart';
import 'package:cashdeck/core/widgets/insights/cd_segment_bar.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
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
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Everything invested: the total and its yield, how the chosen window went,
/// the split by institution and by kind, then each position.
class InvestmentsScreen extends ConsumerWidget {
  const new({super.key});

  static const totalKey = Key('investments-total');
  static Key institutionKey(String id) => Key('investments-institution-$id');
  static Key kindKey(InvestmentKind kind) =>
      Key('investments-kind-${kind.name}');
  static Key positionKey(String id) => Key('investments-position-$id');
  static Key positionYieldKey(String id) =>
      Key('investments-position-yield-$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.investmentsTitle)),
      body: switch (ref.watch(investmentsProvider)) {
        AsyncData(:final value) when value.isEmpty => CdEmptyState(
          icon: Symbols.savings_rounded,
          title: l10n.investmentsEmpty,
          message: l10n.investmentsEmptyMessage,
        ),
        AsyncData(:final value) => CdRefresh(
          providers: [investmentsProvider, investmentPerformanceProvider],
          child: _Holdings(investments: value),
        ),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(investmentsProvider),
        ),
        _ => const CdSkeleton(),
      },
    );
  }
}

class _Holdings extends ConsumerWidget {
  const new({required this.investments});

  final Investments investments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final performance = ref.watch(investmentPerformanceProvider);
    final palette = context.palette;
    final charts = context.charts;
    final syncedAt = investments.syncedAt;
    final institutionIds = [
      for (final group in investments.institutions) group.institutionId,
    ];
    SeriesColors colorsOf(String institutionId) =>
        charts.at(institutionIds.indexOf(institutionId));
    final muted = AppTextStyles.bodyMd.copyWith(
      color: palette.onSurfaceVariant,
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
              Text(l10n.investmentsTotal, style: muted),
              const SizedBox(height: AppSpacing.xs),
              CdAmount(
                investments.total,
                key: InvestmentsScreen.totalKey,
                size: CdAmountSize.xl,
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(l10n.investmentsProfit, style: muted),
                  InvestmentYield(
                    amount: investments.profit,
                    percent: investments.profitPercent,
                  ),
                ],
              ),
              if (syncedAt != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.investmentsSyncedAt(
                    CalendarDate.brazilToday(syncedAt).display,
                    brazilTime(syncedAt),
                  ),
                  style: AppTextStyles.labelMd.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.lg,
            AppSpacing.screenGutter,
            0,
          ),
          child: InvestmentPerformanceCard(
            performance: performance,
            onRetry: () => ref.invalidate(investmentPerformanceProvider),
          ),
        ),
        if (investments.institutions.isNotEmpty)
          _Split(
            title: l10n.investmentsByInstitution,
            parts: [
              for (final group in investments.institutions)
                (
                  key: InvestmentsScreen.institutionKey(group.institutionId),
                  label: group.institution,
                  total: group.total,
                  count: group.count,
                  color: colorsOf(group.institutionId).fill,
                  leading: CdInstitutionLogo(
                    name: group.institution,
                    imageUrl: group.logo?.imageUrl,
                    colors: colorsOf(group.institutionId),
                    size: 32,
                  ),
                ),
            ],
            total: investments.total,
          ),
        if (investments.kinds.isNotEmpty)
          _Split(
            title: l10n.investmentsByKind,
            parts: [
              for (final (index, group) in investments.kinds.indexed)
                (
                  key: InvestmentsScreen.kindKey(group.kind),
                  label: investmentKindLabel(l10n, group.kind),
                  total: group.total,
                  count: group.count,
                  color: charts.at(index).fill,
                  leading: null,
                ),
            ],
            total: investments.total,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.lg,
            AppSpacing.screenGutter,
            AppSpacing.xs,
          ),
          child: CdSectionHeader(title: l10n.investmentsPositions, small: true),
        ),
        for (final position in investments.positions)
          _PositionRow(
            position: position,
            colors: colorsOf(position.institutionId),
            performance: performance.value?.positionOf(position.id),
          ),
      ],
    );
  }
}

typedef _Part = ({
  Key key,
  String label,
  Money total,
  int count,
  Color color,
  Widget? leading,
});

class _Split extends StatelessWidget {
  const new({required this.title, required this.parts, required this.total});

  final String title;
  final List<_Part> parts;
  final Money total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.lg,
        AppSpacing.screenGutter,
        0,
      ),
      child: CdInsightCard(
        title: title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CdSegmentBar(
              semanticsLabel: l10n.investmentsSplitSemantics(title),
              segments: [
                for (final part in parts)
                  CdBarSegment(part.total.cents.toDouble(), part.color),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final part in parts)
              Padding(
                key: part.key,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    part.leading ??
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: part.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            part.label,
                            style: AppTextStyles.bodyLg.copyWith(
                              color: palette.onSurface,
                            ),
                          ),
                          Text(
                            [
                              l10n.investmentsPositionCount(part.count),
                              if (total.cents > 0)
                                l10n.balancesShare(
                                  (part.total.cents * 100 / total.cents)
                                      .round(),
                                ),
                            ].join(' · '),
                            style: AppTextStyles.labelMd.copyWith(
                              color: palette.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    CdAmount(part.total, size: CdAmountSize.row),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PositionRow extends StatelessWidget {
  const new({
    required this.position,
    required this.colors,
    required this.performance,
  });

  final InvestmentPosition position;
  final SeriesColors colors;

  /// What the position earned in the chosen window, null until it loads.
  final PositionPerformance? performance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final due = position.dueOn;
    final twelveMonths = position.lastTwelveMonthsRate;
    final performance = this.performance;
    return CdListRow(
      key: InvestmentsScreen.positionKey(position.id),
      onTap: () => context.push(AppRoutes.investment(position.id)).ignore(),
      leading: CdInstitutionLogo(
        name: position.institution,
        imageUrl: position.logo?.imageUrl,
        colors: colors,
      ),
      title: position.name,
      subtitle: [
        investmentSubtypeLabel(l10n, position.subtype) ??
            investmentKindLabel(l10n, position.kind),
        ?investmentRateLabel(l10n, position.rate),
        if (twelveMonths != null)
          l10n.investmentTwelveMonths(signedPercent(l10n, twelveMonths)),
        if (due != null) l10n.investmentsDueOn(due.display),
        if (position.pending) l10n.investmentsPending,
      ].join(' · '),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CdAmount(position.balance, size: CdAmountSize.row),
          if (performance != null)
            InvestmentYield(
              key: InvestmentsScreen.positionYieldKey(position.id),
              amount: performance.yieldAmount,
              percent: performance.yieldPercent,
              size: CdAmountSize.sm,
            ),
        ],
      ),
    );
  }
}
