import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/insights/data/insight_dtos.dart';
import 'package:cashdeck/features/outlook/data/outlook_dtos.dart';
import 'package:cashdeck/features/outlook/domain/net_worth.dart';
import 'package:cashdeck/features/outlook/domain/outlook_repository.dart';
import 'package:cashdeck/features/outlook/domain/safe_to_spend.dart';
import 'package:dio/dio.dart';

final class ApiOutlookRepository implements OutlookRepository {
  const new(this._dio);

  final Dio _dio;

  @override
  Future<Result<SafeToSpend>> safeToSpend() => guardRequest(() async {
    final response = await _dio.get<Object?>(
      '/api/v1/home/personal/safe-to-spend',
    );
    return safeToSpendFromJson(asJsonMap(unwrapData(response.data)));
  });

  @override
  Future<Result<NetWorth>> netWorth(EntityScope scope, NetWorthPeriod period) =>
      guardRequest(() async {
        final response = await _dio.get<Object?>(
          '/api/v1/net-worth',
          queryParameters: {'months': period.months, ...scopeQuery(scope)},
        );
        return netWorthFromJson(asJsonMap(unwrapData(response.data)));
      });
}
