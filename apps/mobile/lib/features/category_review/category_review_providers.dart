import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/category_review/application/category_review_use_cases.dart';
import 'package:cashdeck/features/category_review/data/api_category_review_repository.dart';
import 'package:cashdeck/features/category_review/data/fake_category_review_repository.dart';
import 'package:cashdeck/features/category_review/domain/category_review.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final categoryReviewRepositoryProvider = Provider<CategoryReviewRepository>((
  ref,
) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeCategoryReviewRepository(ref.watch(clockProvider)),
    Backend.api => ApiCategoryReviewRepository(ref.watch(dioProvider)),
  };
});

final loadReviewQueueProvider = Provider<LoadReviewQueue>(
  (ref) => LoadReviewQueue(ref.watch(categoryReviewRepositoryProvider)),
);

final categorizeGroupProvider = Provider<CategorizeGroup>(
  (ref) => CategorizeGroup(ref.watch(categoryReviewRepositoryProvider)),
);

final acceptRuleSuggestionProvider = Provider<AcceptRuleSuggestion>(
  (ref) => AcceptRuleSuggestion(ref.watch(categoryReviewRepositoryProvider)),
);

final dismissRuleSuggestionProvider = Provider<DismissRuleSuggestion>(
  (ref) => DismissRuleSuggestion(ref.watch(categoryReviewRepositoryProvider)),
);

final listCategoryRulesProvider = Provider<ListCategoryRules>(
  (ref) => ListCategoryRules(ref.watch(categoryReviewRepositoryProvider)),
);

final updateCategoryRuleProvider = Provider<UpdateCategoryRule>(
  (ref) => UpdateCategoryRule(ref.watch(categoryReviewRepositoryProvider)),
);

final deleteCategoryRuleProvider = Provider<DeleteCategoryRule>(
  (ref) => DeleteCategoryRule(ref.watch(categoryReviewRepositoryProvider)),
);
