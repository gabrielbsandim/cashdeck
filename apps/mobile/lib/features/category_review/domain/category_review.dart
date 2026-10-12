import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:equatable/equatable.dart';

/// Why a transaction waits for a human look.
enum ReviewReason { uncategorized, lowConfidence, inconsistent }

/// Money coming in or going out; a rule without one matches both.
enum FlowDirection { incoming, outgoing }

/// The transactions one choice of category settles together: same entity,
/// direction and merchant words.
final class ReviewGroup extends Equatable {
  const new({
    required this.id,
    required this.owner,
    required this.merchant,
    required this.pattern,
    required this.direction,
    required this.count,
    required this.total,
    required this.reasons,
    required this.lastBookedOn,
    required this.transactionIds,
    this.counterparty,
    this.suggestedCategoryId,
    this.confidence,
    this.canCreateRule = false,
  });

  final String id;
  final EntityKind owner;
  final String merchant;

  /// The words a rule made from the group matches; empty when it matches
  /// the payee document instead.
  final String pattern;
  final String? counterparty;
  final FlowDirection direction;
  final int count;

  /// Without a sign; [direction] tells income from expense.
  final Money total;
  final List<ReviewReason> reasons;

  /// The model's guess or the group's usual category, preselected.
  final String? suggestedCategoryId;
  final double? confidence;
  final bool canCreateRule;
  final CalendarDate lastBookedOn;
  final List<String> transactionIds;

  @override
  List<Object?> get props => [
    id,
    owner,
    merchant,
    pattern,
    counterparty,
    direction,
    count,
    total,
    reasons,
    suggestedCategoryId,
    confidence,
    canCreateRule,
    lastBookedOn,
    transactionIds,
  ];
}

/// A rule the server offers after the user picked the same category for one
/// merchant more than once.
final class RuleSuggestion extends Equatable {
  const new({
    required this.id,
    required this.owner,
    required this.merchant,
    required this.pattern,
    required this.direction,
    required this.categoryId,
    required this.count,
    this.counterparty,
  });

  final String id;
  final EntityKind owner;
  final String merchant;
  final String pattern;
  final String? counterparty;
  final FlowDirection direction;
  final String categoryId;

  /// How many times the user chose it.
  final int count;

  @override
  List<Object?> get props => [
    id,
    owner,
    merchant,
    pattern,
    counterparty,
    direction,
    categoryId,
    count,
  ];
}

final class ReviewQueue extends Equatable {
  const new({
    required this.pending,
    this.groups = const [],
    this.suggestions = const [],
  });

  /// Transactions waiting, across every group.
  final int pending;
  final List<ReviewGroup> groups;
  final List<RuleSuggestion> suggestions;

  bool get isEmpty => groups.isEmpty && suggestions.isEmpty;

  ReviewQueue withoutGroup(String id) {
    final removed = groups.where((group) => group.id == id);
    final count = removed.fold(0, (sum, group) => sum + group.count);
    return ReviewQueue(
      pending: (pending - count).clamp(0, pending),
      groups: [
        for (final group in groups)
          if (group.id != id) group,
      ],
      suggestions: suggestions,
    );
  }

  ReviewQueue withoutSuggestion(String id) => ReviewQueue(
    pending: pending,
    groups: groups,
    suggestions: [
      for (final suggestion in suggestions)
        if (suggestion.id != id) suggestion,
    ],
  );

  @override
  List<Object?> get props => [pending, groups, suggestions];
}

/// A learned rule: description words, or a payee document when [pattern] is
/// empty, mapped to a category.
final class CategoryRule extends Equatable {
  const new({
    required this.id,
    required this.pattern,
    required this.categoryId,
    required this.createdAt,
    this.owner,
    this.counterparty,
    this.direction,
    this.priority = 0,
  });

  final String id;

  /// Null applies to both entities.
  final EntityKind? owner;
  final String pattern;
  final String? counterparty;
  final FlowDirection? direction;
  final String categoryId;
  final int priority;
  final DateTime createdAt;

  /// What the rule matches, as the list shows it.
  String get matches => pattern.isNotEmpty ? pattern : counterparty ?? '';

  @override
  List<Object?> get props => [
    id,
    owner,
    pattern,
    counterparty,
    direction,
    categoryId,
    priority,
    createdAt,
  ];
}

/// A change to a rule; a null field stays as it is.
final class CategoryRuleChange extends Equatable {
  const new({this.pattern, this.categoryId});

  final String? pattern;
  final String? categoryId;

  bool get isEmpty => pattern == null && categoryId == null;

  /// A pattern of blanks would match nothing.
  bool get isValid => pattern?.trim() != '';

  @override
  List<Object?> get props => [pattern, categoryId];
}

/// What a category choice changed on the server.
final class CategorizeOutcome extends Equatable {
  const new({required this.updated, this.similarUpdated = 0, this.rule});

  final int updated;

  /// Other transactions the new rule relabeled.
  final int similarUpdated;
  final CategoryRule? rule;

  @override
  List<Object?> get props => [updated, similarUpdated, rule];
}

abstract interface class CategoryReviewRepository {
  /// [entity] null reads both entities.
  Future<Result<ReviewQueue>> queue({EntityKind? entity});

  Future<Result<CategorizeOutcome>> categorize(
    List<String> transactionIds,
    String categoryId, {
    required bool createRule,
  });

  Future<Result<CategorizeOutcome>> acceptSuggestion(String id);

  Future<Result<void>> dismissSuggestion(String id);

  Future<Result<List<CategoryRule>>> rules();

  Future<Result<CategoryRule>> updateRule(String id, CategoryRuleChange change);

  Future<Result<void>> deleteRule(String id);
}
