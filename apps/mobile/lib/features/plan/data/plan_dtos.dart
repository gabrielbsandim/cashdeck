import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/plan/domain/life_plan.dart';

const Map<String, PlanGoalKind> planGoalKinds = {
  'PURCHASE': PlanGoalKind.purchase,
  'YEARLY': PlanGoalKind.yearly,
  'MILESTONE': PlanGoalKind.milestone,
};

const Map<String, PlanStatus> planStatuses = {
  'NOW': PlanStatus.now,
  'PLANNED': PlanStatus.planned,
  'LATE': PlanStatus.late,
  'OUT_OF_REACH': PlanStatus.outOfReach,
};

const Map<String, MilestoneMetric> milestoneMetrics = {
  'NET_WORTH': MilestoneMetric.netWorth,
  'INVESTED': MilestoneMetric.invested,
};

String _keyOf<T>(Map<String, T> table, T value) =>
    table.entries.firstWhere((entry) => entry.value == value).key;

Money? _optionalMoney(JsonMap json, String key) {
  final value = readOptionalMap(json, key);
  return value == null ? null : moneyFromJson(value);
}

YearMonth? _optionalMonth(JsonMap json, String key) {
  final value = readOptionalString(json, key);
  return value == null ? null : YearMonth.parse(value);
}

PlanGoal planGoalFromJson(JsonMap json) {
  final metric = readOptionalString(json, 'metric');
  return PlanGoal(
    id: readString(json, 'id'),
    kind: readEnum(json, 'kind', planGoalKinds),
    name: readString(json, 'name'),
    icon: readOptionalString(json, 'icon'),
    status: readEnum(json, 'status', planStatuses),
    month: _optionalMonth(json, 'month'),
    cash: readMoney(json, 'cash'),
    delays: [
      for (final delay in readMapList(json, 'delays'))
        MilestoneDelay(
          milestoneId: readString(delay, 'milestoneId'),
          name: readString(delay, 'name'),
          months: readOptionalInt(delay, 'months'),
        ),
    ],
    price: _optionalMoney(json, 'price'),
    tradeIn: _optionalMoney(json, 'tradeIn'),
    tradeInAssetId: readOptionalString(json, 'tradeInAssetId'),
    tradeInAssetName: readOptionalString(json, 'tradeInAssetName'),
    financed: _optionalMoney(json, 'financed'),
    monthlyCost: _optionalMoney(json, 'monthlyCost'),
    keepsValue: json['keepsValue'] == true,
    notBefore: _optionalMonth(json, 'notBefore'),
    by: _optionalMonth(json, 'by'),
    yearly: _optionalMoney(json, 'yearly'),
    metric: metric == null ? null : lookupValue(milestoneMetrics, metric),
    target: _optionalMoney(json, 'target'),
    current: _optionalMoney(json, 'current'),
  );
}

double _readNumber(JsonMap json, String key) {
  final value = json[key];
  if (value is num) return value.toDouble();
  throw FormatException('Expected a number at "$key"', json);
}

LifePlan lifePlanFromJson(JsonMap json) => LifePlan(
  asOf: YearMonth.parse(readString(json, 'asOf')),
  monthlySavings: readMoney(json, 'monthlySavings'),
  savingsFromBudget: readBool(json, 'savingsFromBudget'),
  monthlySpending: readMoney(json, 'monthlySpending'),
  reserveMonths: readInt(json, 'reserveMonths'),
  reserve: readMoney(json, 'reserve'),
  yearlyYield: _readNumber(json, 'yearlyYield'),
  keepInvested: readInt(json, 'keepInvested'),
  netWorth: readMoney(json, 'netWorth'),
  invested: readMoney(json, 'invested'),
  yearlyProvision: readMoney(json, 'yearlyProvision'),
  free: readMoney(json, 'free'),
  goals: readMapList(json, 'goals').map(planGoalFromJson).toList(),
  timeline: [
    for (final point in readMapList(json, 'timeline'))
      PlanPoint(
        month: YearMonth.parse(readString(point, 'month')),
        netWorth: readMoney(point, 'netWorth'),
        invested: readMoney(point, 'invested'),
      ),
  ],
);

JsonMap planGoalToJson(PlanGoalDraft draft) {
  final base = {
    'kind': _keyOf(planGoalKinds, draft.kind),
    'name': draft.name.trim(),
    'icon': draft.icon,
  };
  return switch (draft.kind) {
    PlanGoalKind.purchase => {
      ...base,
      'price': draft.price.cents,
      'tradeIn': draft.tradeIn.cents,
      'tradeInAssetId': draft.tradeInAssetId,
      'financed': draft.financed.cents,
      'monthlyCost': draft.monthlyCost.cents,
      'keepsValue': draft.keepsValue,
      'notBefore': draft.notBefore?.iso,
      'by': draft.by?.iso,
    },
    PlanGoalKind.yearly => {...base, 'yearly': draft.yearly.cents},
    PlanGoalKind.milestone => {
      ...base,
      'metric': _keyOf(milestoneMetrics, draft.metric),
      'target': draft.target.cents,
      'by': draft.by?.iso,
    },
  };
}

JsonMap planSettingsToJson(PlanSettings settings) => {
  'reserveMonths': settings.reserveMonths,
  'yearlyYield': settings.yearlyYield,
  'keepInvested': settings.keepInvested,
  'monthlySavings': settings.monthlySavings?.cents,
};
