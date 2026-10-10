import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/insights/data/insight_dtos.dart';
import 'package:cashdeck/features/investments/data/investment_dtos.dart';
import 'package:cashdeck/features/investments/domain/investments.dart';
import 'package:cashdeck/features/investments/domain/investments_repository.dart';
import 'package:dio/dio.dart';

final class ApiInvestmentsRepository implements InvestmentsRepository {
  const new(this._dio);

  final Dio _dio;

  @override
  Future<Result<Investments>> investments(EntityScope scope) =>
      guardRequest(() async {
        final response = await _dio.get<Object?>(
          '/api/v1/investments',
          queryParameters: scopeQuery(scope),
        );
        return investmentsFromJson(asJsonMap(unwrapData(response.data)));
      });
}
