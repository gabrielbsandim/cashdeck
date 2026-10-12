import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/budgets/domain/budget.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';

const Map<String, BudgetLevel> _levels = {
  'OK': BudgetLevel.ok,
  'NEAR': BudgetLevel.near,
  'REACHED': BudgetLevel.reached,
};

SpendCategory _category(JsonMap json) => SpendCategory(
  id: readString(json, 'categoryId'),
  key: readOptionalString(json, 'key'),
  name: readString(json, 'name'),
);

BudgetUsage budgetUsageFromJson(JsonMap json) => BudgetUsage(
  available: readMoney(json, 'available'),
  spent: readMoney(json, 'spent'),
  remaining: readMoney(json, 'remaining'),
  percent: readInt(json, 'percent'),
  level: readEnum(json, 'level', _levels),
);

BudgetItem budgetItemFromJson(JsonMap json) => BudgetItem(
  id: readString(json, 'id'),
  category: _category(json),
  limit: readMoney(json, 'limit'),
  carried: readMoney(json, 'carried'),
  rollover: readBool(json, 'rollover'),
  usage: budgetUsageFromJson(json),
);

BudgetMonth budgetMonthFromJson(JsonMap json) => BudgetMonth(
  month: YearMonth.parse(readString(json, 'month')),
  total: budgetUsageFromJson(readMap(json, 'total')),
  items: readMapList(json, 'items').map(budgetItemFromJson).toList(),
  unbudgeted: [
    for (final item in readMapList(json, 'unbudgeted'))
      UnbudgetedSpend(
        category: _category(item),
        spent: readMoney(item, 'spent'),
      ),
  ],
);

BudgetSuggestions budgetSuggestionsFromJson(JsonMap json) => BudgetSuggestions(
  month: YearMonth.parse(readString(json, 'month')),
  basedOn: readStringList(json, 'basedOn').map(YearMonth.parse).toList(),
  items: [
    for (final item in readMapList(json, 'items'))
      BudgetSuggestion(
        category: _category(item),
        months: readMapList(item, 'months').map(moneyFromJson).toList(),
        suggested: readMoney(item, 'suggested'),
        current: switch (readOptionalMap(item, 'current')) {
          final JsonMap current => moneyFromJson(current),
          null => null,
        },
      ),
  ],
);

/// The entity as the API names it.
String budgetEntityCode(EntityKind entity) => switch (entity) {
  EntityKind.personal => 'PF',
  EntityKind.company => 'PJ',
};

JsonMap acceptToJson(
  EntityKind entity,
  YearMonth month,
  List<BudgetLimit> limits,
) => {
  'entity': budgetEntityCode(entity),
  'month': month.iso,
  'items': [
    for (final entry in limits)
      {'categoryId': entry.categoryId, 'limitCents': entry.limit.cents},
  ],
};
