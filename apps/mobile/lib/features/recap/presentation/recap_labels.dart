import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/insights/presentation/insights_labels.dart';
import 'package:cashdeck/features/recap/domain/monthly_recap.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transaction_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';

final RegExp _amount = RegExp(r'R\$\s?\d[\d.,]*\d');

/// The closing words with every amount masked, for the privacy toggle.
String maskAmounts(String text) =>
    text.replaceAll(_amount, 'R\$ ${MoneyFormat.hidden}');

/// `pt` or `en`, the language the server writes the closing words in.
String recapLocaleOf(AppLocalizations l10n) =>
    l10n.localeName.startsWith('pt') ? 'pt' : 'en';

/// `Setembro`, as a sentence starts with it.
String capitalMonth(AppLocalizations l10n, YearMonth month) {
  final name = monthName(l10n, month);
  return '${name[0].toUpperCase()}${name.substring(1)}';
}

String recapTitleOf(AppLocalizations l10n, YearMonth month) =>
    l10n.recapTitle(monthName(l10n, month));

Category _asCategory(RecapCategory category) =>
    Category(id: category.categoryId, key: category.key, name: category.name);

String recapCategoryName(AppLocalizations l10n, RecapCategory category) =>
    categoryName(l10n, _asCategory(category));

IconData recapCategoryIcon(RecapCategory category) =>
    categoryIcon(_asCategory(category));

/// `+R$ 189,00` or `−R$ 642,00`.
String signedAmount(Money amount, {required bool hide}) =>
    MoneyFormat.format(amount, hide: hide, sign: MoneySign.plus);
