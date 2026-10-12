import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/recap/data/recap_dtos.dart';
import 'package:cashdeck/features/recap/domain/monthly_recap.dart';
import 'package:dio/dio.dart';

final class ApiRecapRepository implements RecapRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/recaps';

  @override
  Future<Result<MonthlyRecap>> get(
    YearMonth month, {
    required String locale,
    required EntityKind entity,
  }) => guardRequest(() async {
    final response = await _dio.get<Object?>(
      '$path/${Uri.encodeComponent(month.iso)}',
      queryParameters: {'entity': entityKindToJson(entity), 'locale': locale},
    );
    return monthlyRecapFromJson(asJsonMap(unwrapData(response.data)));
  });
}
