import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/home/domain/home_summary.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

String budgetCategoryLabel(AppLocalizations l10n, BudgetSummary budget) =>
    switch (budget.category) {
      BudgetCategory.transport => l10n.categoryTransport,
      BudgetCategory.groceries => l10n.categoryGroceries,
      BudgetCategory.restaurants => l10n.categoryRestaurants,
      BudgetCategory.other => _capitalized(budget.name),
    };

String _capitalized(String name) =>
    name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);

IconData budgetCategoryIcon(BudgetCategory category) => switch (category) {
  BudgetCategory.transport => Symbols.directions_car_rounded,
  BudgetCategory.groceries => Symbols.shopping_cart_rounded,
  BudgetCategory.restaurants => Symbols.restaurant_rounded,
  BudgetCategory.other => Symbols.category_rounded,
};

/// hoje, ontem or dd/MM.
String relativeDay(
  AppLocalizations l10n,
  CalendarDate day,
  CalendarDate today,
) => switch (day.daysUntil(today)) {
  0 => l10n.relativeToday,
  1 => l10n.relativeYesterday,
  _ => day.dayMonth,
};

/// outubro, in the app's language.
String monthName(BuildContext context, CalendarDate day) =>
    DateFormat.MMMM(Localizations.localeOf(context).toLanguageTag())
        .format(DateTime(day.year, day.month));

/// out., in the app's language.
String monthShort(BuildContext context, CalendarDate day) =>
    DateFormat.MMM(Localizations.localeOf(context).toLanguageTag())
        .format(DateTime(day.year, day.month));

String capitalized(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
