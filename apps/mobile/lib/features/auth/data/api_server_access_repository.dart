import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:cashdeck/features/auth/data/device_session_dtos.dart';
import 'package:cashdeck/features/auth/domain/server_access.dart';
import 'package:dio/dio.dart';

/// Calls the server being signed in to, not the one the session points at.
final class ApiServerAccessRepository implements ServerAccessRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/sessions';

  @override
  Future<Result<ServerCredentials>> exchange(
    ServerCredentials staticToken,
    DeviceIdentity device,
  ) => guardRequest(() async {
    final response = await _dio.post<Object?>(
      '${staticToken.baseUrl}$path',
      data: deviceIdentityToJson(device),
      options: Options(
        headers: {'Authorization': 'Bearer ${staticToken.token}'},
      ),
    );
    final created = asJsonMap(unwrapData(response.data));
    return ServerCredentials(
      baseUrl: staticToken.baseUrl,
      token: readString(created, 'token'),
    );
  });
}
