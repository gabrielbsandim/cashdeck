import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/charts/cd_line_chart.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_icon_tile.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/money/cd_budget_bar.dart';
import 'package:cashdeck/features/bills/application/bills_use_cases.dart';
import 'package:cashdeck/features/bills/presentation/bills_controller.dart';
import 'package:cashdeck/features/home/domain/home_summary.dart';
import 'package:cashdeck/features/home/presentation/home_labels.dart';
import 'package:cashdeck/features/home/presentation/home_screen.dart';
import 'package:cashdeck/features/home/presentation/home_sections.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Início for the person: balance, reserve, what is due, the 30 day
/// forecast, budgets and alerts.
class PersonalHome extends ConsumerWidget {
  const new({required this.summary, super.key});

  static const alertsSeeAllKey = Key('home-alerts-see-all');
  static const budgetsChatKey = Key('home-budgets-chat');

  final PersonalSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final today = homeToday(ref);
    final bills = ref.watch(billsControllerProvider).value?.bills ?? const [];
    final month = monthName(context, today);
    return HomeScroll(
      children: [
        const PausedBanner(),
        BalanceHeader(
          label: l10n.totalBalance,
          balance: summary.balance,
          syncLine: syncLineOf(l10n, ref, summary.sync),
        ),
        if (summary.reserve case final reserve?)
          _ReserveCard(reserve: reserve, today: today),
        DueSoonSection(bills: billsDueWithin(bills, today, 7), today: today),
        _ForecastSection(forecast: summary.forecast),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CdSectionHeader(title: l10n.budgetsOfMonth(month)),
            const SizedBox(height: AppSpacing.md),
            CdCard(
              child: summary.budgets.isEmpty
                  ? const _NoBudgets()
                  : Column(
                      children: [
                        for (final (index, budget)
                            in summary.budgets.indexed) ...[
                          if (index > 0) const SizedBox(height: AppSpacing.lg),
                          CdBudgetBar(
                            icon: budgetCategoryIcon(budget.category),
                            name: budgetCategoryLabel(l10n, budget),
                            spent: budget.spent,
                            limit: budget.limit,
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
        if (summary.alerts.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CdSectionHeader(
                title: l10n.alertsTitle,
                actionLabel: l10n.seeAllButton,
                actionKey: alertsSeeAllKey,
                onAction: () => showAlertsSheet(context, summary.alerts),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final (index, alert) in summary.alerts.indexed)
                HomeAlertRow(key: Key('home-alert-$index'), alert: alert),
            ],
          ),
      ],
    );
  }
}

class _NoBudgets extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return Row(
      children: [
        Icon(Symbols.donut_small_rounded, color: palette.onSurfaceVariant),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            l10n.budgetsEmpty,
            style: AppTextStyles.bodyMd.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
        ),
        CdButton.text(
          key: PersonalHome.budgetsChatKey,
          label: l10n.budgetsAskChat,
          onPressed: () => context.go(AppRoutes.chat),
        ),
      ],
    );
  }
}

class _ReserveCard extends StatelessWidget {
  const new({required this.reserve, required this.today});

  final ReserveSummary reserve;
  final CalendarDate today;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final income = context.money.income;
    final secondary = AppTextStyles.bodyMd.copyWith(
      color: palette.onSurfaceVariant,
    );
    return CdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CdIconTile(
                Symbols.savings_rounded,
                circle: false,
                tone: context.entities.of(EntityTone.personal),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.reserveTitle,
                      style: AppTextStyles.titleSm.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                    Text(
                      l10n.reserveSource(reserve.institution, reserve.product),
                      style: secondary,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          CdAmount(reserve.balance, textAlign: TextAlign.start),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Icon(Symbols.trending_up_rounded, size: 16, color: income),
              const SizedBox(width: AppSpacing.xs),
              CdPrivateText(
                (hide) => l10n.reserveYield(
                  MoneyFormat.format(
                    reserve.monthYield,
                    hide: hide,
                    sign: MoneySign.plus,
                  ),
                  monthShort(context, today),
                ),
                style: AppTextStyles.labelLg.copyWith(color: income),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              value: (reserve.coverDays / 30).clamp(0, 1),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(switch (reserve.cdiPercent) {
            null => l10n.reserveCoversDays(reserve.coverDays),
            final cdi => l10n.reserveCovers(reserve.coverDays, cdi),
          }, style: secondary),
        ],
      ),
    );
  }
}

class _ForecastSection extends StatelessWidget {
  const new({required this.forecast});

  final CashForecast forecast;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final secondary = AppTextStyles.bodyMd.copyWith(
      color: palette.onSurfaceVariant,
    );
    final strong = AppTextStyles.amountSm.copyWith(
      color: palette.onSurface,
      fontWeight: FontWeight.w600,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CdSectionHeader(
          title: l10n.forecastTitle,
          subtitle: Text(l10n.forecastSubtitle, style: secondary),
        ),
        const SizedBox(height: AppSpacing.md),
        CdCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.forecastLowest, style: secondary),
                        CdPrivateText(
                          (hide) =>
                              MoneyFormat.format(forecast.lowest, hide: hide),
                          style: strong,
                        ),
                        Text(
                          l10n.forecastOn(forecast.lowestDate.dayMonth),
                          style: secondary,
                        ),
                      ],
                    ),
                  ),
                  if (forecast.lastDate != forecast.lowestDate)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          l10n.forecastAt(forecast.lastDate.dayMonth),
                          style: secondary,
                        ),
                        CdPrivateText(
                          (hide) =>
                              MoneyFormat.format(forecast.last, hide: hide),
                          style: strong,
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _ForecastChart(forecast: forecast),
            ],
          ),
        ),
      ],
    );
  }
}

class _ForecastChart extends ConsumerWidget {
  const new({required this.forecast});

  final CashForecast forecast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final middle = forecast.from.addDays((forecast.balances.length - 1) ~/ 2);
    final hide = ref.watch(hideAmountsProvider);
    return CdLineChart(
      values: [for (final balance in forecast.balances) balance.cents / 100],
      floor: forecast.floor.cents / 100,
      xLabels: [
        l10n.relativeTodayTitle,
        middle.dayMonth,
        forecast.lastDate.dayMonth,
      ],
      semanticsLabel: l10n.forecastSemantics(
        MoneyFormat.format(forecast.lowest, hide: hide),
        forecast.lowestDate.dayMonth,
      ),
    );
  }
}
