import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/category_review/category_review_providers.dart';
import 'package:cashdeck/features/category_review/domain/category_review.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The review queue of the entity in view. A settled group leaves at once;
/// a rule that relabeled other transactions reloads the queue behind it.
class CategoryReviewController extends AsyncNotifier<ReviewQueue> {
  @override
  Future<ReviewQueue> build() async {
    final scope = ref.watch(entityScopeProvider);
    return (await ref.watch(loadReviewQueueProvider).call(scope)).orThrow;
  }

  Future<Result<CategorizeOutcome>> categorize(
    ReviewGroup group,
    String categoryId, {
    required bool createRule,
  }) async {
    final result = await ref
        .read(categorizeGroupProvider)
        .call(group, categoryId, createRule: createRule);
    if (result case Ok(:final value)) {
      _update((queue) => queue.withoutGroup(group.id));
      ref.invalidate(transactionsControllerProvider);
      if (value.similarUpdated > 0) await _reload();
    }
    return result;
  }

  /// Leaves [group] for later; it comes back on the next load.
  void skip(ReviewGroup group) =>
      _update((queue) => queue.withoutGroup(group.id));

  Future<Result<CategorizeOutcome>> accept(RuleSuggestion suggestion) async {
    final result = await ref
        .read(acceptRuleSuggestionProvider)
        .call(suggestion);
    if (result case Ok()) {
      _update((queue) => queue.withoutSuggestion(suggestion.id));
      ref.invalidate(categoryRulesControllerProvider);
    }
    return result;
  }

  Future<AppFailure?> dismiss(RuleSuggestion suggestion) async {
    final result = await ref
        .read(dismissRuleSuggestionProvider)
        .call(suggestion);
    switch (result) {
      case Ok():
        _update((queue) => queue.withoutSuggestion(suggestion.id));
        return null;
      case Err(:final failure):
        return failure;
    }
  }

  void _update(ReviewQueue Function(ReviewQueue queue) change) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(change(current));
  }

  Future<void> _reload() async {
    final scope = ref.read(entityScopeProvider);
    final result = await ref.read(loadReviewQueueProvider).call(scope);
    if (result case Ok(:final value)) state = AsyncData(value);
  }
}

final AsyncNotifierProvider<CategoryReviewController, ReviewQueue>
categoryReviewControllerProvider =
    AsyncNotifierProvider.autoDispose<CategoryReviewController, ReviewQueue>(
      CategoryReviewController.new,
      retry: noRetry,
    );

class CategoryRulesController extends AsyncNotifier<List<CategoryRule>> {
  @override
  Future<List<CategoryRule>> build() async =>
      (await ref.watch(listCategoryRulesProvider).call()).orThrow;

  Future<AppFailure?> save(CategoryRule rule, CategoryRuleChange change) async {
    final result = await ref
        .read(updateCategoryRuleProvider)
        .call(rule, change);
    switch (result) {
      case Ok(:final value):
        state = AsyncData([
          for (final kept in state.value ?? const <CategoryRule>[])
            if (kept.id == value.id) value else kept,
        ]);
        ref.invalidate(transactionsControllerProvider);
        return null;
      case Err(:final failure):
        return failure;
    }
  }

  Future<AppFailure?> delete(CategoryRule rule) async {
    final result = await ref.read(deleteCategoryRuleProvider).call(rule);
    switch (result) {
      case Ok():
        state = AsyncData([
          for (final kept in state.value ?? const <CategoryRule>[])
            if (kept.id != rule.id) kept,
        ]);
        return null;
      case Err(:final failure):
        return failure;
    }
  }
}

final AsyncNotifierProvider<CategoryRulesController, List<CategoryRule>>
categoryRulesControllerProvider =
    AsyncNotifierProvider.autoDispose<
      CategoryRulesController,
      List<CategoryRule>
    >(CategoryRulesController.new, retry: noRetry);
