import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:cashdeck/features/auth/domain/server_access.dart';
import 'package:dio/dio.dart';

/// Calls the server being signed in to, not the one the session points at.
final class ApiServerAccessRepository implements ServerAccessRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/auth/check';

  @override
  Future<Result<void>> check(ServerCredentials credentials) =>
      guardRequest(() async {
        await _dio.get<Object?>(
          '${credentials.baseUrl}$path',
          options: Options(
            headers: {'Authorization': 'Bearer ${credentials.token}'},
          ),
        );
      });
}
