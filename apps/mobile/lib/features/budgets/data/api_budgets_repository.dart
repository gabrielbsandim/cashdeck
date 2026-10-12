import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/budgets/data/budget_dtos.dart';
import 'package:cashdeck/features/budgets/domain/budget.dart';
import 'package:dio/dio.dart';

final class ApiBudgetsRepository implements BudgetsRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/budgets';

  String _budget(String id) => '$path/${Uri.encodeComponent(id)}';

  BudgetMonth _read(Response<Object?> response) =>
      budgetMonthFromJson(asJsonMap(unwrapData(response.data)));

  @override
  Future<Result<BudgetMonth>> month(YearMonth month) => guardRequest(
    () async => _read(
      await _dio.get<Object?>(
        path,
        queryParameters: {'entity': 'PF', 'month': month.iso},
      ),
    ),
  );

  @override
  Future<Result<BudgetMonth>> create(
    YearMonth month,
    String categoryId,
    Money limit, {
    bool rollover = false,
  }) => guardRequest(
    () async => _read(
      await _dio.post<Object?>(
        path,
        data: {
          'entity': 'PF',
          'month': month.iso,
          'categoryId': categoryId,
          'limitCents': limit.cents,
          'rollover': rollover,
        },
      ),
    ),
  );

  @override
  Future<Result<BudgetMonth>> update(
    String id, {
    required Money limit,
    required bool rollover,
  }) => guardRequest(
    () async => _read(
      await _dio.patch<Object?>(
        _budget(id),
        data: {'limitCents': limit.cents, 'rollover': rollover},
      ),
    ),
  );

  @override
  Future<Result<BudgetMonth>> delete(String id) =>
      guardRequest(() async => _read(await _dio.delete<Object?>(_budget(id))));

  @override
  Future<Result<BudgetMonth>> copyToNext(YearMonth from) => guardRequest(
    () async => _read(
      await _dio.post<Object?>(
        '$path/copy',
        data: {'entity': 'PF', 'month': from.iso},
      ),
    ),
  );

  @override
  Future<Result<BudgetSuggestions>> suggestions(YearMonth month) =>
      guardRequest(() async {
        final response = await _dio.get<Object?>(
          '$path/suggestions',
          queryParameters: {'entity': 'PF', 'month': month.iso},
        );
        return budgetSuggestionsFromJson(asJsonMap(unwrapData(response.data)));
      });

  @override
  Future<Result<BudgetMonth>> accept(
    YearMonth month,
    List<BudgetLimit> limits,
  ) => guardRequest(
    () async => _read(
      await _dio.post<Object?>(
        '$path/suggestions',
        data: acceptToJson(month, limits),
      ),
    ),
  );
}
