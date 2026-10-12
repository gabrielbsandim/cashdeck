import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/auth/data/device_session_dtos.dart';
import 'package:cashdeck/features/auth/domain/device_session.dart';
import 'package:dio/dio.dart';

final class ApiDeviceSessionsRepository implements DeviceSessionsRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/sessions';

  @override
  Future<Result<List<DeviceSession>>> list() => guardRequest(() async {
    final response = await _dio.get<Object?>(path);
    return asJsonMapList(unwrapData(response.data))
        .map(deviceSessionFromJson)
        .toList();
  });

  @override
  Future<Result<void>> revoke(String id) => guardRequest(
    () => _dio.delete<Object?>('$path/${Uri.encodeComponent(id)}'),
  );

  @override
  Future<Result<void>> endCurrent() =>
      guardRequest(() => _dio.delete<Object?>('$path/current'));
}
