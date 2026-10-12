import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';
import 'package:cashdeck/features/outlook/domain/net_worth.dart';
import 'package:cashdeck/features/outlook/domain/safe_to_spend.dart';

const Map<String, SafeToSpendLineKind> safeToSpendLineKinds = {
  'BILL': SafeToSpendLineKind.bill,
  'FIXED': SafeToSpendLineKind.fixed,
  'SUBSCRIPTION': SafeToSpendLineKind.subscription,
  'CARD': SafeToSpendLineKind.card,
  'RESERVE': SafeToSpendLineKind.reserve,
};

double? _readOptionalNumber(JsonMap json, String key) {
  final value = json[key];
  if (value == null || value is num) return (value as num?)?.toDouble();
  throw FormatException('Expected a number or null at "$key"', json);
}

SafeToSpend safeToSpendFromJson(JsonMap json) {
  final income = readOptionalMap(json, 'income');
  return SafeToSpend(
    asOf: readDate(json, 'asOf'),
    cash: readMoney(json, 'cash'),
    total: readMoney(json, 'total'),
    daily: readMoney(json, 'daily'),
    days: readInt(json, 'days'),
    until: readDate(json, 'until'),
    shortBy: readMoney(json, 'shortBy'),
    income: income == null
        ? null
        : ExpectedIncome(
            on: readDate(income, 'on'),
            amount: readMoney(income, 'amount'),
          ),
    lines: [
      for (final line in readMapList(json, 'lines'))
        SafeToSpendLine(
          kind: readEnum(line, 'kind', safeToSpendLineKinds),
          label: readString(line, 'label'),
          amount: readMoney(line, 'amount'),
          on: readOptionalDate(line, 'on'),
        ),
    ],
  );
}

NetWorthComposition _composition(JsonMap json) => NetWorthComposition(
  cash: readMoney(json, 'cash'),
  investments: readMoney(json, 'investments'),
  cardDebt: readMoney(json, 'cardDebt'),
  assets: readMoney(json, 'assets'),
  liabilities: readMoney(json, 'liabilities'),
  total: readMoney(json, 'total'),
);

NetWorthChange _change(JsonMap json) => NetWorthChange(
  amount: readMoney(json, 'amount'),
  percent: _readOptionalNumber(json, 'percent'),
);

NetWorth netWorthFromJson(JsonMap json) => NetWorth(
  asOf: readDate(json, 'asOf'),
  current: _composition(readMap(json, 'current')),
  fromLastMonth: _change(readMap(json, 'fromLastMonth')),
  fromYearAgo: _change(readMap(json, 'fromYearAgo')),
  entities: [
    for (final entity in readMapList(json, 'entities'))
      EntityNetWorth(
        kind: readEntityKind(entity, 'kind'),
        current: _composition(readMap(entity, 'current')),
      ),
  ],
  series: [
    for (final point in readMapList(json, 'series'))
      NetWorthPoint(
        on: readDate(point, 'on'),
        assets: readMoney(point, 'assets'),
        liabilities: readMoney(point, 'liabilities'),
        total: readMoney(point, 'total'),
      ),
  ],
);
