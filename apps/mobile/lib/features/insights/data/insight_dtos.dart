import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';

const Map<String, InsightPeriod> _periods = {
  '1w': InsightPeriod.week,
  '1m': InsightPeriod.month,
  '6m': InsightPeriod.sixMonths,
  '1y': InsightPeriod.year,
};

String periodToJson(InsightPeriod period) =>
    _periods.entries.firstWhere((entry) => entry.value == period).key;

/// The `entity` query of a scope; consolidated sends none.
Map<String, Object> scopeQuery(EntityScope scope) => switch (scope) {
  EntityScope.personal => {'entity': entityKindToJson(EntityKind.personal)},
  EntityScope.company => {'entity': entityKindToJson(EntityKind.company)},
  EntityScope.consolidated => const {},
};

YearMonth readMonth(JsonMap json, String key) =>
    YearMonth.parse(readString(json, key));

DateSpan _span(JsonMap json) =>
    DateSpan(readDate(json, 'from'), readDate(json, 'to'));

List<SpendPoint> _points(JsonMap json, String key) => [
  for (final point in readMapList(json, key))
    SpendPoint(readDate(point, 'day'), readMoney(point, 'cumulative')),
];

CardsSummary? _cards(JsonMap? json) {
  if (json == null) return null;
  final limit = readOptionalMap(json, 'limit');
  final used = readOptionalMap(json, 'used');
  return CardsSummary(
    bill: readMoney(json, 'bill'),
    dueOn: readOptionalDate(json, 'dueOn'),
    count: readInt(json, 'count'),
    limit: limit == null ? null : moneyFromJson(limit),
    used: used == null ? null : moneyFromJson(used),
    usedPercent: readOptionalInt(json, 'usedPercent'),
  );
}

InsightsOverview overviewFromJson(JsonMap json) {
  final spend = readMap(json, 'spend');
  final categories = readMap(json, 'categories');
  final flow = readMap(json, 'flow');
  final bills = readMap(json, 'billsDue');
  return InsightsOverview(
    period: readEnum(json, 'period', _periods),
    range: _span(readMap(json, 'range')),
    previousRange: _span(readMap(json, 'previousRange')),
    spend: SpendSummary(
      total: readMoney(spend, 'total'),
      previous: readMoney(spend, 'previous'),
      changePercent: readOptionalInt(spend, 'changePercent'),
      series: _points(spend, 'series'),
      previousSeries: _points(spend, 'previousSeries'),
      topMerchants: [
        for (final merchant in readMapList(spend, 'topMerchants'))
          MerchantSpend(
            name: readString(merchant, 'name'),
            total: readMoney(merchant, 'total'),
            count: readInt(merchant, 'count'),
          ),
      ],
    ),
    categoryTotal: readMoney(categories, 'total'),
    categories: [
      for (final item in readMapList(categories, 'items'))
        CategoryShare(
          categoryId: readOptionalString(item, 'categoryId'),
          key: readOptionalString(item, 'key'),
          name: readOptionalString(item, 'name'),
          icon: readOptionalString(item, 'icon'),
          total: readMoney(item, 'total'),
          sharePercent: readInt(item, 'sharePercent'),
          changePercent: readOptionalInt(item, 'changePercent'),
        ),
    ],
    flow: CashFlow(
      income: readMoney(flow, 'income'),
      expenses: readMoney(flow, 'expenses'),
      result: readMoney(flow, 'result'),
    ),
    cards: _cards(readOptionalMap(json, 'cards')),
    billsDue: BillsDue(
      days: readInt(bills, 'days'),
      total: readMoney(bills, 'total'),
      count: readInt(bills, 'count'),
    ),
  );
}

CategoryChange _change(JsonMap json) => CategoryChange(
  categoryId: readString(json, 'categoryId'),
  key: readOptionalString(json, 'key'),
  name: readString(json, 'name'),
  icon: readOptionalString(json, 'icon'),
  total: readMoney(json, 'total'),
  average: readMoney(json, 'average'),
  delta: readMoney(json, 'delta'),
);

const Map<String, InsightTone> _tones = {
  'POSITIVE': InsightTone.positive,
  'NEGATIVE': InsightTone.negative,
  'NEUTRAL': InsightTone.neutral,
};

/// An insight type the app does not know yet is skipped, so a newer server
/// never blanks Análises.
Insight? insightFromJson(JsonMap json) {
  final tone = readEnum(json, 'tone', _tones);
  return switch (json['type']) {
    'CATEGORY_ABOVE_AVERAGE' => CategoryAboveAverage(
      tone: tone,
      categoryId: readString(json, 'categoryId'),
      name: readString(json, 'name'),
      percent: readInt(json, 'percent'),
      amount: readMoney(json, 'amount'),
    ),
    'INSTALLMENTS_COMMITTED' => InstallmentsCommitted(
      tone: tone,
      month: readMonth(json, 'month'),
      amount: readMoney(json, 'amount'),
    ),
    'SAVINGS_RATE' => SavingsRateChanged(
      tone: tone,
      percent: readInt(json, 'percent'),
      averagePercent: readInt(json, 'averagePercent'),
    ),
    'SUBSCRIPTION_PRICE_UP' => SubscriptionPriceUp(
      tone: tone,
      name: readString(json, 'name'),
      amount: readMoney(json, 'amount'),
      previousAmount: readMoney(json, 'previousAmount'),
    ),
    _ => null,
  };
}

LeftThisMonth? _left(JsonMap? json) {
  if (json == null) return null;
  return LeftThisMonth(
    balance: readMoney(json, 'balance'),
    billsDue: readMoney(json, 'billsDue'),
    cardBill: readMoney(json, 'cardBill'),
    left: readMoney(json, 'left'),
  );
}

CompanyToPersonal? _company(JsonMap? json) {
  if (json == null) return null;
  return CompanyToPersonal(
    transfers: readMoney(json, 'transfers'),
    taxes: readMoney(json, 'taxes'),
  );
}

MonthlyInsights monthlyFromJson(JsonMap json) {
  final savings = readMap(json, 'savings');
  final changes = readMap(json, 'changes');
  final fixed = readMap(json, 'fixedCost');
  return MonthlyInsights(
    month: readMonth(json, 'month'),
    months: [
      for (final item in readMapList(json, 'months'))
        MonthResult(
          month: readMonth(item, 'month'),
          income: readMoney(item, 'income'),
          expenses: readMoney(item, 'expenses'),
          result: readMoney(item, 'result'),
        ),
    ],
    savings: SavingsRate(
      percent: readOptionalInt(savings, 'percent'),
      averagePercent: readOptionalInt(savings, 'averagePercent'),
      trend: [
        for (final point in readMapList(savings, 'trend'))
          (readMonth(point, 'month'), readOptionalInt(point, 'percent')),
      ],
    ),
    rose: readMapList(changes, 'rose').map(_change).toList(),
    fell: readMapList(changes, 'fell').map(_change).toList(),
    fixedCost: FixedCost(
      subscriptions: readMoney(fixed, 'subscriptions'),
      installments: readMoney(fixed, 'installments'),
      bills: readMoney(fixed, 'bills'),
      total: readMoney(fixed, 'total'),
      income: readMoney(fixed, 'income'),
      sharePercent: readOptionalInt(fixed, 'sharePercent'),
    ),
    leftThisMonth: _left(readOptionalMap(json, 'leftThisMonth')),
    companyToPersonal: _company(readOptionalMap(json, 'companyToPersonal')),
    insights: readMapList(
      json,
      'insights',
    ).map(insightFromJson).nonNulls.toList(),
  );
}

InstallmentPlan _plan(JsonMap json) => InstallmentPlan(
  key: readString(json, 'key'),
  accountId: readString(json, 'accountId'),
  card: readString(json, 'card'),
  cardSuffix: readOptionalString(json, 'cardSuffix'),
  owner: readEntityKind(json, 'entityKind'),
  name: readString(json, 'name'),
  categoryId: readOptionalString(json, 'categoryId'),
  number: readInt(json, 'number'),
  count: readInt(json, 'count'),
  amount: readMoney(json, 'amount'),
  paid: readMoney(json, 'paid'),
  remaining: readMoney(json, 'remaining'),
  total: readMoney(json, 'total'),
  purchaseOn: readOptionalDate(json, 'purchaseOn'),
  lastBilledOn: readDate(json, 'lastBilledOn'),
  finalMonth: readMonth(json, 'finalMonth'),
);

Installments installmentsFromJson(JsonMap json) => Installments(
  months: [
    for (final item in readMapList(json, 'months'))
      (readMonth(item, 'month'), readMoney(item, 'total')),
  ],
  plans: readMapList(json, 'plans').map(_plan).toList(),
);

const Map<String, SubscriptionMonthStatus> _monthStatuses = {
  'PAID': SubscriptionMonthStatus.paid,
  'UPCOMING': SubscriptionMonthStatus.upcoming,
  'LATE': SubscriptionMonthStatus.late,
};

Subscription subscriptionFromJson(JsonMap json) {
  final previous = readOptionalMap(json, 'previousAmount');
  return Subscription(
    id: readOptionalString(json, 'id'),
    key: readString(json, 'key'),
    owner: readEntityKind(json, 'entityKind'),
    name: readString(json, 'name'),
    amount: readMoney(json, 'amount'),
    previousAmount: previous == null ? null : moneyFromJson(previous),
    priceChanged: readBool(json, 'priceChanged'),
    dayOfMonth: readInt(json, 'dayOfMonth'),
    lastChargeOn: readOptionalDate(json, 'lastChargeOn'),
    thisMonth: readEnum(json, 'thisMonth', _monthStatuses),
    accountId: readOptionalString(json, 'accountId'),
    categoryId: readOptionalString(json, 'categoryId'),
    transactionIds: readStringList(json, 'transactionIds'),
  );
}

Subscriptions subscriptionsFromJson(JsonMap json) => Subscriptions(
  monthly: readMoney(json, 'monthly'),
  yearly: readMoney(json, 'yearly'),
  previousMonth: readMoney(json, 'previousMonth'),
  changePercent: readOptionalInt(json, 'changePercent'),
  items: readMapList(json, 'items').map(subscriptionFromJson).toList(),
  suggestions: readMapList(
    json,
    'suggestions',
  ).map(subscriptionFromJson).toList(),
);
