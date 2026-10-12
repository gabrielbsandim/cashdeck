import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/features/goals/domain/goal.dart';

const Map<String, GoalStatus> _statuses = {
  'DONE': GoalStatus.done,
  'ON_TRACK': GoalStatus.onTrack,
  'BEHIND': GoalStatus.behind,
};

const Map<String, GoalSource> _sources = {
  'MANUAL': GoalSource.manual,
  'ACCOUNT': GoalSource.account,
  'INVESTMENT': GoalSource.investment,
};

Money? _optionalMoney(JsonMap json, String key) =>
    switch (readOptionalMap(json, key)) {
      final JsonMap value => moneyFromJson(value),
      null => null,
    };

GoalContribution contributionFromJson(JsonMap json) => GoalContribution(
  id: readString(json, 'id'),
  amount: readMoney(json, 'amount'),
  on: readDate(json, 'on'),
  note: readOptionalString(json, 'note'),
);

Goal goalFromJson(JsonMap json) => Goal(
  id: readString(json, 'id'),
  name: readString(json, 'name'),
  target: readMoney(json, 'target'),
  saved: readMoney(json, 'saved'),
  remaining: readMoney(json, 'remaining'),
  percent: readInt(json, 'percent'),
  status: readEnum(json, 'status', _statuses),
  source: readEnum(json, 'source', _sources),
  deadline: readOptionalDate(json, 'deadline'),
  requiredMonthly: _optionalMoney(json, 'requiredMonthly'),
  monthlyPace: _optionalMoney(json, 'monthlyPace'),
  projectedOn: readOptionalDate(json, 'projectedOn'),
  accountId: readOptionalString(json, 'accountId'),
  investmentId: readOptionalString(json, 'investmentId'),
  linkedName: readOptionalString(json, 'linkedName'),
  icon: readOptionalString(json, 'icon'),
  color: readOptionalString(json, 'color'),
  archived: json['archivedAt'] != null,
  contributions: readMapList(
    json,
    'contributions',
  ).map(contributionFromJson).toList(),
);

/// A new goal for the person; what is already saved goes only with a goal
/// that adds up contributions.
JsonMap goalCreateToJson(GoalDraft draft) => {
  'entity': 'PF',
  'name': draft.name.trim(),
  'targetCents': draft.target.cents,
  'deadline': ?draft.deadline?.iso,
  'accountId': ?draft.accountId,
  'investmentId': ?draft.investmentId,
  'icon': ?draft.icon,
  'color': ?draft.color,
  if (draft.isManual && draft.initial.cents > 0)
    'initialCents': draft.initial.cents,
};

/// Every field, so a cleared deadline or link reaches the server as null.
JsonMap goalUpdateToJson(GoalDraft draft) => {
  'name': draft.name.trim(),
  'targetCents': draft.target.cents,
  'deadline': draft.deadline?.iso,
  'accountId': draft.accountId,
  'investmentId': draft.investmentId,
  'icon': draft.icon,
  'color': draft.color,
};
