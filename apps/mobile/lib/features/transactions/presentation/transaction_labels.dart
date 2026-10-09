import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

typedef _Label = String Function(AppLocalizations l10n);

const Map<String, (_Label, IconData)> _builtIn = {
  'groceries': (_groceries, Symbols.shopping_cart_rounded),
  'restaurants': (_restaurants, Symbols.restaurant_rounded),
  'transport': (_transport, Symbols.directions_car_rounded),
  'fuel': (_fuel, Symbols.local_gas_station_rounded),
  'housing': (_housing, Symbols.home_rounded),
  'utilities': (_utilities, Symbols.bolt_rounded),
  'health': (_health, Symbols.medical_services_rounded),
  'education': (_education, Symbols.school_rounded),
  'leisure': (_leisure, Symbols.theater_comedy_rounded),
  'shopping': (_shopping, Symbols.shopping_bag_rounded),
  'subscriptions': (_subscriptions, Symbols.autorenew_rounded),
  'travel': (_travel, Symbols.flight_rounded),
  'taxes': (_taxes, Symbols.account_balance_rounded),
  'fees': (_fees, Symbols.receipt_rounded),
  'salary': (_salary, Symbols.badge_rounded),
  'income': (_income, Symbols.trending_up_rounded),
  'investments': (_investments, Symbols.savings_rounded),
  'transfers': (_transfers, Symbols.sync_alt_rounded),
  'services': (_services, Symbols.handyman_rounded),
  'other': (_other, Symbols.category_rounded),
};

String _groceries(AppLocalizations l10n) => l10n.categoryGroceries;
String _restaurants(AppLocalizations l10n) => l10n.categoryRestaurants;
String _transport(AppLocalizations l10n) => l10n.categoryTransport;
String _fuel(AppLocalizations l10n) => l10n.categoryFuel;
String _housing(AppLocalizations l10n) => l10n.categoryHousing;
String _utilities(AppLocalizations l10n) => l10n.categoryUtilities;
String _health(AppLocalizations l10n) => l10n.categoryHealth;
String _education(AppLocalizations l10n) => l10n.categoryEducation;
String _leisure(AppLocalizations l10n) => l10n.categoryLeisure;
String _shopping(AppLocalizations l10n) => l10n.categoryShopping;
String _subscriptions(AppLocalizations l10n) => l10n.categorySubscriptions;
String _travel(AppLocalizations l10n) => l10n.categoryTravel;
String _taxes(AppLocalizations l10n) => l10n.categoryTaxes;
String _fees(AppLocalizations l10n) => l10n.categoryFees;
String _salary(AppLocalizations l10n) => l10n.categorySalary;
String _income(AppLocalizations l10n) => l10n.categoryIncome;
String _investments(AppLocalizations l10n) => l10n.categoryInvestments;
String _transfers(AppLocalizations l10n) => l10n.categoryTransfers;
String _services(AppLocalizations l10n) => l10n.categoryServices;
String _other(AppLocalizations l10n) => l10n.categoryOther;

/// A built-in category in the app language; one the user made keeps its name.
String categoryName(AppLocalizations l10n, Category category) =>
    _builtIn[category.key]?.$1(l10n) ?? category.name;

IconData categoryIcon(Category? category) =>
    _builtIn[category?.key]?.$2 ?? Symbols.category_rounded;

/// The category of [transaction] among [categories], or null.
Category? categoryOf(Transaction transaction, List<Category> categories) {
  final id = transaction.categoryId;
  if (id == null) return null;
  return categories.where((category) => category.id == id).firstOrNull;
}

String transactionCategoryLabel(
  AppLocalizations l10n,
  Transaction transaction,
  List<Category> categories,
) {
  final category = categoryOf(transaction, categories);
  if (category != null) return categoryName(l10n, category);
  return transaction.isUncategorized
      ? l10n.transactionUncategorized
      : l10n.transactionCategoryUnknown;
}

/// Who chose the category, with the model's confidence when it did.
String? categorySourceLabel(AppLocalizations l10n, Transaction transaction) {
  final confidence = ((transaction.categoryConfidence ?? 0) * 100).round();
  return switch (transaction.categorizedBy) {
    null => null,
    CategorySource.user => l10n.categorySourceUser,
    CategorySource.rule => l10n.categorySourceRule,
    CategorySource.ai when transaction.categoryConfidence == null =>
      l10n.categorySourceAi,
    CategorySource.ai => l10n.categorySourceAiConfidence(confidence),
  };
}

CdAmountKind amountKindOf(Transaction transaction) =>
    switch (transaction.kind) {
      TransactionKind.income => CdAmountKind.income,
      TransactionKind.expense => CdAmountKind.expense,
      TransactionKind.transfer => CdAmountKind.transfer,
    };

/// Hoje, Ontem, or the weekday and date of [day].
String dayLabel(
  AppLocalizations l10n,
  CalendarDate day,
  CalendarDate today,
  String locale,
) {
  return switch (day.daysUntil(today)) {
    0 => l10n.relativeTodayTitle,
    1 => l10n.relativeYesterdayTitle,
    _ => DateFormat.MMMEd(
      locale,
    ).format(DateTime(day.year, day.month, day.day)),
  };
}
