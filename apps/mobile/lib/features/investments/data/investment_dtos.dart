import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';
import 'package:cashdeck/features/investments/domain/investments.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';

const Map<String, InvestmentKind> investmentKinds = {
  'FIXED_INCOME': InvestmentKind.fixedIncome,
  'FUND': InvestmentKind.fund,
  'EQUITY': InvestmentKind.equity,
  'ETF': InvestmentKind.etf,
  'PENSION': InvestmentKind.pension,
  'STRUCTURED': InvestmentKind.structured,
  'OTHER': InvestmentKind.other,
};

double? _readOptionalNumber(JsonMap json, String key) {
  final value = json[key];
  if (value == null || value is num) return (value as num?)?.toDouble();
  throw FormatException('Expected a number or null at "$key"', json);
}

AccountLogo? _logo(JsonMap? json) {
  if (json == null) return null;
  return AccountLogo(
    imageUrl: readString(json, 'imageUrl'),
    color: readOptionalString(json, 'color'),
  );
}

InvestmentRate? _rate(JsonMap? json) {
  if (json == null) return null;
  return InvestmentRate(
    percent: _readOptionalNumber(json, 'percent'),
    index: readOptionalString(json, 'index'),
    fixedAnnual: _readOptionalNumber(json, 'fixedAnnual'),
  );
}

InvestmentPosition _position(JsonMap json) {
  final invested = readOptionalMap(json, 'invested');
  final profit = readOptionalMap(json, 'profit');
  return InvestmentPosition(
    id: readString(json, 'id'),
    owner: readEntityKind(json, 'entityKind'),
    institutionId: readString(json, 'institutionId'),
    institution: readString(json, 'institution'),
    logo: _logo(readOptionalMap(json, 'logo')),
    name: readString(json, 'name'),
    kind: readEnum(json, 'kind', investmentKinds),
    subtype: readOptionalString(json, 'subtype'),
    issuer: readOptionalString(json, 'issuer'),
    pending: readString(json, 'status') == 'PENDING',
    balance: readMoney(json, 'balance'),
    invested: invested == null ? null : moneyFromJson(invested),
    profit: profit == null ? null : moneyFromJson(profit),
    profitPercent: _readOptionalNumber(json, 'profitPercent'),
    quantity: _readOptionalNumber(json, 'quantity'),
    rate: _rate(readOptionalMap(json, 'rate')),
    lastMonthRate: _readOptionalNumber(json, 'lastMonthRate'),
    lastTwelveMonthsRate: _readOptionalNumber(json, 'lastTwelveMonthsRate'),
    dueOn: readOptionalDate(json, 'dueOn'),
    valuedOn: readOptionalDate(json, 'valuedOn'),
  );
}

Investments investmentsFromJson(JsonMap json) => Investments(
  total: readMoney(json, 'total'),
  invested: readMoney(json, 'invested'),
  profit: readMoney(json, 'profit'),
  syncedAt: readOptionalDateTime(json, 'syncedAt'),
  institutions: [
    for (final item in readMapList(json, 'institutions'))
      InstitutionHoldings(
        institutionId: readString(item, 'institutionId'),
        institution: readString(item, 'institution'),
        logo: _logo(readOptionalMap(item, 'logo')),
        total: readMoney(item, 'total'),
        count: readInt(item, 'count'),
      ),
  ],
  kinds: [
    for (final item in readMapList(json, 'kinds'))
      KindHoldings(
        kind: readEnum(item, 'kind', investmentKinds),
        total: readMoney(item, 'total'),
        count: readInt(item, 'count'),
      ),
  ],
  positions: readMapList(json, 'positions').map(_position).toList(),
);
