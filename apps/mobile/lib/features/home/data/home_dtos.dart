import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/features/home/domain/home_summary.dart';

const Map<String, BudgetCategory> _categories = {
  'transport': BudgetCategory.transport,
  'groceries': BudgetCategory.groceries,
  'restaurants': BudgetCategory.restaurants,
};

const Map<String, InternalTransferKind> _transferKinds = {
  'PROFIT_DISTRIBUTION': InternalTransferKind.profitDistribution,
  'PRO_LABORE': InternalTransferKind.proLabore,
};

SyncInfo syncFromJson(JsonMap json) => SyncInfo(
  accountCount: readInt(json, 'accountCount'),
  syncedAt: readOptionalDateTime(json, 'syncedAt'),
);

ReserveSummary? reserveFromJson(JsonMap? json) {
  if (json == null) return null;
  return ReserveSummary(
    institution: readString(json, 'institution'),
    product: readString(json, 'product'),
    balance: readMoney(json, 'balance'),
    monthYield: readMoney(json, 'monthYield'),
    coverDays: readInt(json, 'coverDays'),
    cdiPercent: readOptionalInt(json, 'cdiPercent'),
  );
}

BudgetSummary budgetFromJson(JsonMap json) {
  final name = readString(json, 'category');
  return BudgetSummary(
    category: _categories[name] ?? BudgetCategory.other,
    name: name,
    spent: readMoney(json, 'spent'),
    limit: readMoney(json, 'limit'),
  );
}

/// An alert type the app does not know yet is skipped, not an error, so a
/// newer server never blanks Início.
HomeAlert? alertFromJson(JsonMap json) => switch (json['type']) {
  'ASSISTED_PAYMENT' => AssistedPaymentAlert(
    billId: readString(json, 'billId'),
    payee: readString(json, 'payee'),
    reason: readString(json, 'reason'),
    at: readDateTime(json, 'at'),
  ),
  'BUDGET_EXCEEDED' => BudgetExceededAlert(
    budget: budgetFromJson(readMap(json, 'budget')),
    at: readDateTime(json, 'at'),
  ),
  _ => null,
};

CashForecast forecastFromJson(JsonMap json) => CashForecast(
  from: readDate(json, 'from'),
  balances: readMapList(json, 'balances').map(moneyFromJson).toList(),
  floor: readMoney(json, 'floor'),
);

PersonalSummary personalFromJson(JsonMap json) => PersonalSummary(
  balance: readMoney(json, 'balance'),
  sync: syncFromJson(readMap(json, 'sync')),
  reserve: reserveFromJson(readOptionalMap(json, 'reserve')),
  forecast: forecastFromJson(readMap(json, 'forecast')),
  budgets: readMapList(json, 'budgets').map(budgetFromJson).toList(),
  alerts: readMapList(json, 'alerts').map(alertFromJson).nonNulls.toList(),
);

CompanySummary companyFromJson(JsonMap json) => CompanySummary(
  cash: readMoney(json, 'cash'),
  sync: syncFromJson(readMap(json, 'sync')),
  billed: readMoney(json, 'billed'),
  invoiceCount: readInt(json, 'invoiceCount'),
  dasEstimate: readMoney(json, 'dasEstimate'),
  dasDue: readDate(json, 'dasDue'),
  inss: taxEstimateFromJson(readOptionalMap(json, 'inss')),
  drafts: [
    for (final draft in readMapList(json, 'drafts'))
      InvoiceDraft(
        id: readString(draft, 'id'),
        customer: readString(draft, 'customer'),
        amount: readMoney(draft, 'amount'),
        recurring: readBool(draft, 'recurring'),
        issueOn: readDate(draft, 'issueOn'),
      ),
  ],
  unbilled: [
    for (final receipt in readMapList(json, 'unbilled'))
      UnbilledReceipt(
        id: readString(receipt, 'id'),
        payer: readString(receipt, 'payer'),
        amount: readMoney(receipt, 'amount'),
        receivedOn: readDate(receipt, 'receivedOn'),
      ),
  ],
);

ConsolidatedSummary consolidatedFromJson(JsonMap json) => ConsolidatedSummary(
  personal: readMoney(json, 'personal'),
  company: readMoney(json, 'company'),
  externalIn: readMoney(json, 'externalIn'),
  externalOut: readMoney(json, 'externalOut'),
  transfers: [
    for (final transfer in readMapList(json, 'transfers'))
      InternalTransfer(
        id: readString(transfer, 'id'),
        kind: readEnum(transfer, 'kind', _transferKinds),
        amount: readMoney(transfer, 'amount'),
        on: readDate(transfer, 'on'),
      ),
  ],
);

TaxEstimate? taxEstimateFromJson(JsonMap? json) {
  if (json == null) return null;
  return TaxEstimate(
    amount: readMoney(json, 'estimate'),
    due: readDate(json, 'due'),
  );
}

FundingPlan fundingFromJson(JsonMap json) {
  final balance = readOptionalMap(json, 'balance');
  return FundingPlan(
    balance: balance == null ? null : moneyFromJson(balance),
    monthlyAverage: readMoney(json, 'monthlyAverage'),
    months: readMapList(json, 'months').length,
    upcoming: readMoney(json, 'upcoming'),
    topUp: readMoney(json, 'topUp'),
  );
}
