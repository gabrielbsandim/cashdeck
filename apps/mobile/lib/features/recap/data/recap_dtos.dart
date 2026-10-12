import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/recap/domain/monthly_recap.dart';

const Map<String, RecapStorySource> _sources = {
  'AI': RecapStorySource.ai,
  'TEMPLATE': RecapStorySource.template,
};

RecapChange _change(JsonMap json) => RecapChange(
  amount: readMoney(json, 'amount'),
  percent: readOptionalInt(json, 'percent'),
);

RecapFlow _flow(JsonMap json) => RecapFlow(
  income: readMoney(json, 'income'),
  expenses: readMoney(json, 'expenses'),
  net: readMoney(json, 'net'),
);

RecapCategory _category(JsonMap json) => RecapCategory(
  categoryId: readString(json, 'categoryId'),
  key: readOptionalString(json, 'key'),
  name: readString(json, 'name'),
  total: readMoney(json, 'total'),
  sharePercent: readOptionalInt(json, 'sharePercent'),
  change: switch (readOptionalMap(json, 'change')) {
    final JsonMap change => _change(change),
    null => null,
  },
);

RecapSubscription _subscription(JsonMap json) => RecapSubscription(
  name: readString(json, 'name'),
  amount: readMoney(json, 'amount'),
);

RecapNetWorth _netWorth(JsonMap json) => RecapNetWorth(
  total: readMoney(json, 'total'),
  change: _change(readMap(json, 'change')),
);

MonthlyRecap monthlyRecapFromJson(JsonMap json) {
  final savings = readMap(json, 'savings');
  final changes = readMap(json, 'changes');
  final subscriptions = readMap(json, 'subscriptions');
  final story = readMap(json, 'story');
  return MonthlyRecap(
    month: YearMonth.parse(readString(json, 'month')),
    flow: _flow(readMap(json, 'flow')),
    previousFlow: _flow(readMap(json, 'previousFlow')),
    expensesChange: _change(readMap(json, 'expensesChange')),
    savingsPercent: readOptionalInt(savings, 'percent'),
    previousSavingsPercent: readOptionalInt(savings, 'previousPercent'),
    topCategory: switch (readOptionalMap(json, 'topCategory')) {
      final JsonMap top => _category(top),
      null => null,
    },
    rose: readMapList(changes, 'rose').map(_category).toList(),
    fell: readMapList(changes, 'fell').map(_category).toList(),
    started: readMapList(subscriptions, 'started').map(_subscription).toList(),
    stopped: readMapList(subscriptions, 'stopped').map(_subscription).toList(),
    netWorth: switch (readOptionalMap(json, 'netWorth')) {
      final JsonMap netWorth => _netWorth(netWorth),
      null => null,
    },
    story: readString(story, 'text'),
    storySource: readEnum(story, 'source', _sources),
  );
}
