import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/category_review/domain/category_review.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';

/// The queue of the entity the switcher shows, or of both.
final class LoadReviewQueue {
  const new(this._repository);

  final CategoryReviewRepository _repository;

  Future<Result<ReviewQueue>> call(EntityScope scope) => _repository.queue(
    entity: switch (scope) {
      EntityScope.personal => EntityKind.personal,
      EntityScope.company => EntityKind.company,
      EntityScope.consolidated => null,
    },
  );
}

/// Labels every transaction of a group; a rule only goes along when the
/// group has a pattern to build it from.
final class CategorizeGroup {
  const new(this._repository);

  final CategoryReviewRepository _repository;

  Future<Result<CategorizeOutcome>> call(
    ReviewGroup group,
    String categoryId, {
    required bool createRule,
  }) => _repository.categorize(
    group.transactionIds,
    categoryId,
    createRule: createRule && group.canCreateRule,
  );
}

final class AcceptRuleSuggestion {
  const new(this._repository);

  final CategoryReviewRepository _repository;

  Future<Result<CategorizeOutcome>> call(RuleSuggestion suggestion) =>
      _repository.acceptSuggestion(suggestion.id);
}

final class DismissRuleSuggestion {
  const new(this._repository);

  final CategoryReviewRepository _repository;

  Future<Result<void>> call(RuleSuggestion suggestion) =>
      _repository.dismissSuggestion(suggestion.id);
}

final class ListCategoryRules {
  const new(this._repository);

  final CategoryReviewRepository _repository;

  Future<Result<List<CategoryRule>>> call() => _repository.rules();
}

/// An empty change keeps the rule without a request; a blank pattern never
/// reaches the server.
final class UpdateCategoryRule {
  const new(this._repository);

  final CategoryReviewRepository _repository;

  Future<Result<CategoryRule>> call(
    CategoryRule rule,
    CategoryRuleChange change,
  ) {
    if (!change.isValid) {
      return Future.value(const Err(UnexpectedFailure()));
    }
    if (change.isEmpty) return Future.value(Ok(rule));
    return _repository.updateRule(rule.id, change);
  }
}

final class DeleteCategoryRule {
  const new(this._repository);

  final CategoryReviewRepository _repository;

  Future<Result<void>> call(CategoryRule rule) =>
      _repository.deleteRule(rule.id);
}
