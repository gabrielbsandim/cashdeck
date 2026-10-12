import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/category_review/domain/category_review.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';

/// A fictional queue and rules in memory, settled the way the server does.
final class FakeCategoryReviewRepository implements CategoryReviewRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 300)});

  final Clock _clock;
  final Duration latency;
  var _counter = 0;
  late final List<ReviewGroup> _groups = _seedGroups();
  late final List<RuleSuggestion> _suggestions = _seedSuggestions();
  late final List<CategoryRule> _rules = _seedRules();

  CalendarDate get _today => CalendarDate.fromDateTime(_clock.now());

  List<ReviewGroup> _seedGroups() => [
    ReviewGroup(
      id: 'group-bakery',
      owner: EntityKind.personal,
      merchant: 'Padaria Exemplo',
      pattern: 'padaria exemplo',
      direction: FlowDirection.outgoing,
      count: 4,
      total: const Money(8640),
      reasons: const [ReviewReason.uncategorized],
      canCreateRule: true,
      lastBookedOn: _today,
      transactionIds: const ['review-1', 'review-2', 'review-3', 'review-4'],
    ),
    ReviewGroup(
      id: 'group-fuel',
      owner: EntityKind.personal,
      merchant: 'Posto Modelo',
      pattern: 'posto modelo',
      direction: FlowDirection.outgoing,
      count: 2,
      total: const Money(30000),
      reasons: const [ReviewReason.lowConfidence],
      suggestedCategoryId: 'cat-fuel',
      confidence: 0.62,
      canCreateRule: true,
      lastBookedOn: _today,
      transactionIds: const ['review-5', 'review-6'],
    ),
    ReviewGroup(
      id: 'group-client',
      owner: EntityKind.company,
      merchant: 'Cliente Fictício',
      pattern: '',
      counterparty: '11222333000181',
      direction: FlowDirection.incoming,
      count: 1,
      total: const Money(450000),
      reasons: const [ReviewReason.inconsistent],
      suggestedCategoryId: 'cat-income',
      canCreateRule: true,
      lastBookedOn: _today,
      transactionIds: const ['review-7'],
    ),
  ];

  List<RuleSuggestion> _seedSuggestions() => [
    const RuleSuggestion(
      id: 'suggestion-market',
      owner: EntityKind.personal,
      merchant: 'Mercado Exemplo',
      pattern: 'mercado exemplo',
      direction: FlowDirection.outgoing,
      categoryId: 'cat-groceries',
      count: 3,
    ),
  ];

  List<CategoryRule> _seedRules() {
    final created = _clock.now().subtract(const Duration(days: 30));
    return [
      CategoryRule(
        id: 'rule-gym',
        owner: EntityKind.personal,
        pattern: 'academia exemplo',
        direction: FlowDirection.outgoing,
        categoryId: 'cat-leisure',
        createdAt: created,
      ),
      CategoryRule(
        id: 'rule-pharmacy',
        pattern: 'farmacia modelo',
        categoryId: 'cat-health',
        createdAt: created,
      ),
    ];
  }

  @override
  Future<Result<ReviewQueue>> queue({EntityKind? entity}) async {
    await Future<void>.delayed(latency);
    bool shown(EntityKind owner) => entity == null || owner == entity;
    final groups = _groups.where((group) => shown(group.owner)).toList();
    return Ok(
      ReviewQueue(
        pending: groups.fold(0, (sum, group) => sum + group.count),
        groups: groups,
        suggestions: _suggestions
            .where((suggestion) => shown(suggestion.owner))
            .toList(),
      ),
    );
  }

  @override
  Future<Result<CategorizeOutcome>> categorize(
    List<String> transactionIds,
    String categoryId, {
    required bool createRule,
  }) async {
    await Future<void>.delayed(latency);
    final ids = transactionIds.toSet();
    final settled = _groups
        .where((group) => group.transactionIds.any(ids.contains))
        .toList();
    if (settled.isEmpty) return const Err(NotFoundFailure());
    _groups.removeWhere(settled.contains);
    final first = settled.first;
    final rule = createRule
        ? _addRule(
            owner: first.owner,
            pattern: first.pattern,
            counterparty: first.counterparty,
            direction: first.direction,
            categoryId: categoryId,
          )
        : null;
    return Ok(CategorizeOutcome(updated: ids.length, rule: rule));
  }

  CategoryRule _addRule({
    required EntityKind owner,
    required String pattern,
    required String? counterparty,
    required FlowDirection direction,
    required String categoryId,
  }) {
    final rule = CategoryRule(
      id: 'rule-new-${++_counter}',
      owner: owner,
      pattern: pattern,
      counterparty: counterparty,
      direction: direction,
      categoryId: categoryId,
      createdAt: _clock.now(),
    );
    _rules.add(rule);
    return rule;
  }

  @override
  Future<Result<CategorizeOutcome>> acceptSuggestion(String id) async {
    await Future<void>.delayed(latency);
    final suggestion = _suggestions.where((s) => s.id == id).firstOrNull;
    if (suggestion == null) return const Err(NotFoundFailure());
    _suggestions.remove(suggestion);
    final rule = _addRule(
      owner: suggestion.owner,
      pattern: suggestion.pattern,
      counterparty: suggestion.counterparty,
      direction: suggestion.direction,
      categoryId: suggestion.categoryId,
    );
    return Ok(CategorizeOutcome(updated: 0, rule: rule));
  }

  @override
  Future<Result<void>> dismissSuggestion(String id) async {
    await Future<void>.delayed(latency);
    final before = _suggestions.length;
    _suggestions.removeWhere((suggestion) => suggestion.id == id);
    if (_suggestions.length == before) return const Err(NotFoundFailure());
    return const Ok(null);
  }

  @override
  Future<Result<List<CategoryRule>>> rules() async {
    await Future<void>.delayed(latency);
    return Ok([..._rules]..sort((a, b) => a.matches.compareTo(b.matches)));
  }

  @override
  Future<Result<CategoryRule>> updateRule(
    String id,
    CategoryRuleChange change,
  ) async {
    await Future<void>.delayed(latency);
    final index = _rules.indexWhere((rule) => rule.id == id);
    if (index < 0) return const Err(NotFoundFailure());
    final rule = _rules[index];
    final pattern = change.pattern?.trim();
    final updated = CategoryRule(
      id: rule.id,
      owner: rule.owner,
      pattern: pattern ?? rule.pattern,
      counterparty: pattern == null ? rule.counterparty : null,
      direction: rule.direction,
      categoryId: change.categoryId ?? rule.categoryId,
      priority: rule.priority,
      createdAt: rule.createdAt,
    );
    _rules[index] = updated;
    return Ok(updated);
  }

  @override
  Future<Result<void>> deleteRule(String id) async {
    await Future<void>.delayed(latency);
    final before = _rules.length;
    _rules.removeWhere((rule) => rule.id == id);
    if (_rules.length == before) return const Err(NotFoundFailure());
    return const Ok(null);
  }
}
