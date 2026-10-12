import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/features/category_review/domain/category_review.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';

const Map<String, FlowDirection> _directions = {
  'IN': FlowDirection.incoming,
  'OUT': FlowDirection.outgoing,
};

const Map<String, ReviewReason> _reasons = {
  'UNCATEGORIZED': ReviewReason.uncategorized,
  'LOW_CONFIDENCE': ReviewReason.lowConfidence,
  'INCONSISTENT': ReviewReason.inconsistent,
};

FlowDirection? _optionalDirection(JsonMap json) {
  final raw = json['direction'];
  return raw is String ? _directions[raw] : null;
}

EntityKind? _optionalKind(JsonMap json) {
  final raw = json['entityKind'];
  return raw is String ? entityKindFromJson(raw) : null;
}

double? _optionalDouble(JsonMap json, String key) {
  final raw = json[key];
  return raw is num ? raw.toDouble() : null;
}

/// A reason a newer server added is left out, so the group still shows.
List<ReviewReason> _readReasons(JsonMap json) => [
  for (final raw in readStringList(json, 'reasons'))
    if (_reasons[raw] case final ReviewReason reason) reason,
];

ReviewGroup reviewGroupFromJson(JsonMap json) => ReviewGroup(
  id: readString(json, 'id'),
  owner: readEntityKind(json, 'entityKind'),
  merchant: readString(json, 'merchant'),
  pattern: readString(json, 'pattern'),
  counterparty: readOptionalString(json, 'counterparty'),
  direction: readEnum(json, 'direction', _directions),
  count: readInt(json, 'count'),
  total: readMoney(json, 'total'),
  reasons: _readReasons(json),
  suggestedCategoryId: readOptionalString(json, 'suggestedCategoryId'),
  confidence: _optionalDouble(json, 'confidence'),
  canCreateRule: readBool(json, 'canCreateRule'),
  lastBookedOn: readDate(json, 'lastBookedOn'),
  transactionIds: readStringList(json, 'transactionIds'),
);

RuleSuggestion ruleSuggestionFromJson(JsonMap json) => RuleSuggestion(
  id: readString(json, 'id'),
  owner: readEntityKind(json, 'entityKind'),
  merchant: readString(json, 'merchant'),
  pattern: readString(json, 'pattern'),
  counterparty: readOptionalString(json, 'counterparty'),
  direction: readEnum(json, 'direction', _directions),
  categoryId: readString(json, 'categoryId'),
  count: readInt(json, 'count'),
);

ReviewQueue reviewQueueFromJson(JsonMap json) => ReviewQueue(
  pending: readInt(json, 'pending'),
  groups: readMapList(json, 'groups').map(reviewGroupFromJson).toList(),
  suggestions: readMapList(
    json,
    'suggestions',
  ).map(ruleSuggestionFromJson).toList(),
);

CategoryRule categoryRuleFromJson(JsonMap json) => CategoryRule(
  id: readString(json, 'id'),
  owner: _optionalKind(json),
  pattern: readString(json, 'pattern'),
  counterparty: readOptionalString(json, 'counterparty'),
  direction: _optionalDirection(json),
  categoryId: readString(json, 'categoryId'),
  priority: readOptionalInt(json, 'priority') ?? 0,
  createdAt: readDateTime(json, 'createdAt'),
);

CategorizeOutcome categorizeOutcomeFromJson(JsonMap json) => CategorizeOutcome(
  updated: readInt(json, 'updated'),
  similarUpdated: readOptionalInt(json, 'similarUpdated') ?? 0,
  rule: switch (readOptionalMap(json, 'rule')) {
    final JsonMap rule => categoryRuleFromJson(rule),
    null => null,
  },
);

JsonMap categoryRuleChangeToJson(CategoryRuleChange change) => {
  if (change.pattern case final String pattern) 'pattern': pattern.trim(),
  if (change.categoryId case final String categoryId) 'categoryId': categoryId,
};
