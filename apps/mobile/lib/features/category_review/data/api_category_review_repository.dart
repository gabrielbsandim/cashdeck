import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/category_review/data/category_review_dtos.dart';
import 'package:cashdeck/features/category_review/domain/category_review.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:dio/dio.dart';

final class ApiCategoryReviewRepository implements CategoryReviewRepository {
  const new(this._dio);

  final Dio _dio;

  static const reviewPath = '/api/v1/categories/review';
  static const rulesPath = '/api/v1/categories/rules';

  String _rule(String id) => '$rulesPath/${Uri.encodeComponent(id)}';

  @override
  Future<Result<ReviewQueue>> queue({EntityKind? entity}) =>
      guardRequest(() async {
        final response = await _dio.get<Object?>(
          reviewPath,
          queryParameters: {
            if (entity != null) 'entity': entityKindToJson(entity),
          },
        );
        return reviewQueueFromJson(asJsonMap(unwrapData(response.data)));
      });

  @override
  Future<Result<CategorizeOutcome>> categorize(
    List<String> transactionIds,
    String categoryId, {
    required bool createRule,
  }) => guardRequest(() async {
    final response = await _dio.post<Object?>(
      '$reviewPath/groups',
      data: {
        'transactionIds': transactionIds,
        'categoryId': categoryId,
        'createRule': createRule,
      },
    );
    return categorizeOutcomeFromJson(asJsonMap(unwrapData(response.data)));
  });

  @override
  Future<Result<CategorizeOutcome>> acceptSuggestion(String id) =>
      guardRequest(() async {
        final response = await _dio.post<Object?>(
          '$reviewPath/suggestions/accept',
          data: {'id': id},
        );
        return categorizeOutcomeFromJson(asJsonMap(unwrapData(response.data)));
      });

  @override
  Future<Result<void>> dismissSuggestion(String id) => guardRequest(
    () =>
        _dio.post<Object?>('$reviewPath/suggestions/dismiss', data: {'id': id}),
  );

  @override
  Future<Result<List<CategoryRule>>> rules() => guardRequest(() async {
    final response = await _dio.get<Object?>(rulesPath);
    return asJsonMapList(unwrapData(response.data))
        .map(categoryRuleFromJson)
        .toList();
  });

  @override
  Future<Result<CategoryRule>> updateRule(
    String id,
    CategoryRuleChange change,
  ) => guardRequest(() async {
    final response = await _dio.patch<Object?>(
      _rule(id),
      data: categoryRuleChangeToJson(change),
    );
    final data = asJsonMap(unwrapData(response.data));
    return categoryRuleFromJson(readMap(data, 'rule'));
  });

  @override
  Future<Result<void>> deleteRule(String id) =>
      guardRequest(() => _dio.delete<Object?>(_rule(id)));
}
