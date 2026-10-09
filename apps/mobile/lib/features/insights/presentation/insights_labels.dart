import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

/// `out`, the short month the bars print under each column.
String shortMonth(AppLocalizations l10n, YearMonth month) => DateFormat(
  'MMM',
  l10n.localeName,
).format(DateTime.utc(month.year, month.month)).replaceAll('.', '');

/// `outubro`, as sentences use it.
String monthName(AppLocalizations l10n, YearMonth month) => DateFormat(
  'MMMM',
  l10n.localeName,
).format(DateTime.utc(month.year, month.month));

/// `Outubro 2026`, as the month header reads.
String monthTitle(AppLocalizations l10n, YearMonth month) {
  final name = monthName(l10n, month);
  return '${name[0].toUpperCase()}${name.substring(1)} ${month.year}';
}

/// `D S T Q Q S S`, from Sunday, as the month calendar heads its columns.
List<String> weekdayInitials(AppLocalizations l10n) => [
  for (var day = 0; day < 7; day++)
    DateFormat(
      'EEEEE',
      l10n.localeName,
    ).format(DateTime.utc(2026, 10, 4 + day)).toUpperCase(),
];

String periodLabel(AppLocalizations l10n, InsightPeriod period) =>
    switch (period) {
      InsightPeriod.week => l10n.periodWeek,
      InsightPeriod.month => l10n.periodMonth,
      InsightPeriod.sixMonths => l10n.periodSixMonths,
      InsightPeriod.year => l10n.periodYear,
    };

/// The sentence an insight reads as, amounts masked with privacy on.
String insightSentence(
  AppLocalizations l10n,
  Insight insight, {
  required bool hide,
}) {
  String amount(Money value) => MoneyFormat.format(value, hide: hide);
  return switch (insight) {
    CategoryAboveAverage(:final name, :final percent, amount: final value) =>
      l10n.insightCategoryAbove(name, percent, amount(value)),
    InstallmentsCommitted(:final month, amount: final value) =>
      l10n.insightInstallments(monthName(l10n, month), amount(value)),
    SavingsRateChanged(:final percent, :final averagePercent)
        when percent >= averagePercent =>
      l10n.insightSavingsUp(percent, averagePercent),
    SavingsRateChanged(:final percent, :final averagePercent) =>
      l10n.insightSavingsDown(percent, averagePercent),
    SubscriptionPriceUp(
      :final name,
      amount: final value,
      :final previousAmount,
    ) =>
      l10n.insightPriceUp(name, amount(value), amount(previousAmount)),
  };
}

IconData insightIcon(Insight insight) => switch (insight) {
  CategoryAboveAverage() => Symbols.trending_up_rounded,
  InstallmentsCommitted() => Symbols.event_repeat_rounded,
  SavingsRateChanged() => Symbols.savings_rounded,
  SubscriptionPriceUp() => Symbols.sell_rounded,
};

ToneColors insightTone(AppMoneyColors money, Insight insight) =>
    switch (insight.tone) {
      InsightTone.positive => ToneColors(
        foreground: money.paid,
        background: money.paidContainer,
      ),
      InsightTone.negative => ToneColors(
        foreground: money.overdue,
        background: money.overdueContainer,
      ),
      InsightTone.neutral => ToneColors(
        foreground: money.scheduled,
        background: money.scheduledContainer,
      ),
    };
