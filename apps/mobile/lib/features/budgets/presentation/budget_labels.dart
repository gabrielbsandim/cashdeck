import 'package:cashdeck/features/budgets/domain/budget.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transaction_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';

Category _asCategory(SpendCategory category) =>
    Category(id: category.id, key: category.key, name: category.name);

/// A built-in category in the app language; one the user made keeps its name.
String spendCategoryName(AppLocalizations l10n, SpendCategory category) =>
    categoryName(l10n, _asCategory(category));

IconData spendCategoryIcon(SpendCategory category) =>
    categoryIcon(_asCategory(category));
