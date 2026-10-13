import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/household/data/household_dtos.dart';
import 'package:cashdeck/features/household/domain/household.dart';
import 'package:dio/dio.dart';

final class ApiHouseholdRepository implements HouseholdRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/household';

  @override
  Future<Result<Household>> get() => guardRequest(() async {
    final response = await _dio.get<Object?>(path);
    return householdFromJson(asJsonMap(unwrapData(response.data)));
  });

  @override
  Future<Result<Household>> save(Household household) => guardRequest(() async {
    final response = await _dio.put<Object?>(
      path,
      data: householdToJson(household),
    );
    return householdFromJson(asJsonMap(unwrapData(response.data)));
  });
}
