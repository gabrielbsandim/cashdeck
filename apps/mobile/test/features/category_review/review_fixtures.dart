import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/category_review/domain/category_review.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';

import '../../support/builders.dart';

ReviewGroup reviewGroup(
  String id, {
  int count = 2,
  bool canCreateRule = true,
  String? suggestedCategoryId,
}) => ReviewGroup(
  id: id,
  owner: EntityKind.personal,
  merchant: 'Padaria Exemplo',
  pattern: 'padaria exemplo',
  direction: FlowDirection.outgoing,
  count: count,
  total: const Money(1000),
  reasons: const [ReviewReason.uncategorized],
  suggestedCategoryId: suggestedCategoryId,
  canCreateRule: canCreateRule,
  lastBookedOn: const CalendarDate(2026, 10, 8),
  transactionIds: [for (var i = 0; i < count; i++) '$id-$i'],
);

const suggestion = RuleSuggestion(
  id: 'suggestion-1',
  owner: EntityKind.personal,
  merchant: 'Mercado Exemplo',
  pattern: 'mercado exemplo',
  direction: FlowDirection.outgoing,
  categoryId: 'cat-groceries',
  count: 3,
);

CategoryRule categoryRule({String pattern = 'academia', String? document}) =>
    CategoryRule(
      id: 'rule-1',
      pattern: pattern,
      counterparty: document,
      categoryId: 'cat-leisure',
      createdAt: testNow,
    );
