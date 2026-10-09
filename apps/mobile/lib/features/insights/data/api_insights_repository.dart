import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/insights/data/insight_dtos.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:cashdeck/features/insights/domain/insights_repository.dart';
import 'package:dio/dio.dart';

final class ApiInsightsRepository implements InsightsRepository {
  const new(this._dio);

  final Dio _dio;

  Future<JsonMap> _get(String path, Map<String, Object> query) async {
    final response = await _dio.get<Object?>(
      '/api/v1/$path',
      queryParameters: query,
    );
    return asJsonMap(unwrapData(response.data));
  }

  @override
  Future<Result<InsightsOverview>> overview(
    EntityScope scope,
    InsightPeriod period,
  ) => guardRequest(
    () async => overviewFromJson(
      await _get('insights/overview', {
        ...scopeQuery(scope),
        'period': periodToJson(period),
      }),
    ),
  );

  @override
  Future<Result<MonthlyInsights>> months(
    EntityScope scope, {
    required int count,
    YearMonth? month,
  }) => guardRequest(
    () async => monthlyFromJson(
      await _get('insights/months', {
        ...scopeQuery(scope),
        'months': count,
        if (month != null) 'month': month.iso,
      }),
    ),
  );

  @override
  Future<Result<Installments>> installments(EntityScope scope) => guardRequest(
    () async =>
        installmentsFromJson(await _get('installments', scopeQuery(scope))),
  );

  @override
  Future<Result<Subscriptions>> subscriptions(EntityScope scope) =>
      guardRequest(
        () async => subscriptionsFromJson(
          await _get('subscriptions', scopeQuery(scope)),
        ),
      );

  @override
  Future<Result<String>> confirmSubscription(String transactionId) =>
      guardRequest(() async {
        final response = await _dio.post<Object?>(
          '/api/v1/subscriptions',
          data: {'transactionId': transactionId},
        );
        return readString(asJsonMap(unwrapData(response.data)), 'id');
      });

  @override
  Future<Result<void>> dismissSubscription(String transactionId) =>
      guardRequest(() async {
        await _dio.post<Object?>(
          '/api/v1/subscriptions/dismiss',
          data: {'transactionId': transactionId},
        );
      });

  @override
  Future<Result<void>> removeSubscription(String id) => guardRequest(() async {
    await _dio.delete<Object?>(
      '/api/v1/subscriptions/${Uri.encodeComponent(id)}',
    );
  });
}
