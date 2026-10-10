import 'package:cashdeck/features/investments/domain/investments.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:intl/intl.dart';

String investmentKindLabel(AppLocalizations l10n, InvestmentKind kind) =>
    switch (kind) {
      InvestmentKind.fixedIncome => l10n.investmentKindFixedIncome,
      InvestmentKind.fund => l10n.investmentKindFund,
      InvestmentKind.equity => l10n.investmentKindEquity,
      InvestmentKind.etf => l10n.investmentKindEtf,
      InvestmentKind.pension => l10n.investmentKindPension,
      InvestmentKind.structured => l10n.investmentKindStructured,
      InvestmentKind.other => l10n.investmentKindOther,
    };

final Map<String, String Function(AppLocalizations)> _subtypes = {
  'TREASURY': (l10n) => l10n.investmentSubtypeTreasury,
  'DEBENTURES': (l10n) => l10n.investmentSubtypeDebentures,
  'STOCK': (l10n) => l10n.investmentSubtypeStock,
  'REAL_ESTATE_FUND': (l10n) => l10n.investmentSubtypeRealEstateFund,
  'MULTIMARKET_FUND': (l10n) => l10n.investmentSubtypeMultimarketFund,
  'FIXED_INCOME_FUND': (l10n) => l10n.investmentSubtypeFixedIncomeFund,
  'STOCK_FUND': (l10n) => l10n.investmentSubtypeStockFund,
  'INVESTMENT_FUND': (l10n) => l10n.investmentSubtypeInvestmentFund,
  'RETIREMENT': (l10n) => l10n.investmentSubtypeRetirement,
};

/// Acronyms such as CDB, LCI or VGBL read as they come.
String? investmentSubtypeLabel(AppLocalizations l10n, String? subtype) {
  if (subtype == null) return null;
  return _subtypes[subtype]?.call(l10n) ?? subtype.replaceAll('_', ' ');
}

String _number(AppLocalizations l10n, double value) =>
    NumberFormat('#,##0.##', l10n.localeName).format(value);

String signedPercent(AppLocalizations l10n, double value) =>
    '${value > 0 ? '+' : ''}${_number(l10n, value)}%';

String plainNumber(AppLocalizations l10n, double value) => _number(l10n, value);

/// 102% do CDI, IPCA + 6,2% a.a., or a fixed 12% a.a.
String? investmentRateLabel(AppLocalizations l10n, InvestmentRate? rate) {
  if (rate == null) return null;
  final index = rate.index;
  final percent = rate.percent;
  final fixed = rate.fixedAnnual ?? 0;
  if (index != null && fixed > 0) {
    return l10n.investmentRateIndexPlus(index, _number(l10n, fixed));
  }
  if (index != null && percent != null) {
    return l10n.investmentRatePercentOf(_number(l10n, percent), index);
  }
  if (fixed > 0) return l10n.investmentRateFixed(_number(l10n, fixed));
  return null;
}
