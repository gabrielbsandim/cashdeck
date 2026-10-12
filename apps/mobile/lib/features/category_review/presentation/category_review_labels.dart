import 'package:cashdeck/features/category_review/domain/category_review.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_switcher.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transaction_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';

/// Why the group waits; the model's confidence when it guessed low.
String reviewReasonLabel(
  AppLocalizations l10n,
  ReviewReason reason,
  double? confidence,
) => switch ((reason, confidence)) {
  (ReviewReason.uncategorized, _) => l10n.categoryReviewReasonUncategorized,
  (ReviewReason.lowConfidence, null) => l10n.categoryReviewReasonUnsure,
  (ReviewReason.lowConfidence, final double value) =>
    l10n.categoryReviewReasonLowConfidence('${(value * 100).round()}'),
  (ReviewReason.inconsistent, _) => l10n.categoryReviewReasonInconsistent,
};

String reviewReasonsLine(AppLocalizations l10n, ReviewGroup group) => group
    .reasons
    .map((reason) => reviewReasonLabel(l10n, reason, group.confidence))
    .join(' · ');

String flowDirectionLabel(AppLocalizations l10n, FlowDirection? direction) =>
    switch (direction) {
      FlowDirection.incoming => l10n.categoryRuleIncoming,
      FlowDirection.outgoing => l10n.categoryRuleOutgoing,
      null => l10n.categoryRuleAnyDirection,
    };

/// What the rule matches: its words, or the payee document.
String ruleMatchLabel(AppLocalizations l10n, CategoryRule rule) {
  final document = rule.counterparty;
  if (rule.pattern.isNotEmpty || document == null) return rule.pattern;
  return l10n.categoryRuleDocument(document);
}

/// The category, the entity and the direction the rule applies to.
String ruleScopeLine(
  AppLocalizations l10n,
  CategoryRule rule,
  List<Category> categories,
) {
  final owner = rule.owner;
  return [
    categoryLabel(l10n, rule.categoryId, categories),
    if (owner == null)
      l10n.categoryRuleAnyEntity
    else
      entityScopeLabel(l10n, scopeOfKind(owner)),
    flowDirectionLabel(l10n, rule.direction),
  ].join(' · ');
}

EntityScope scopeOfKind(EntityKind kind) => switch (kind) {
  EntityKind.personal => EntityScope.personal,
  EntityKind.company => EntityScope.company,
};

Category? categoryById(String? id, List<Category> categories) =>
    categories.where((category) => category.id == id).firstOrNull;

/// A category the list no longer has reads as unknown.
String categoryLabel(
  AppLocalizations l10n,
  String id,
  List<Category> categories,
) => switch (categoryById(id, categories)) {
  final Category category => categoryName(l10n, category),
  null => l10n.transactionCategoryUnknown,
};
