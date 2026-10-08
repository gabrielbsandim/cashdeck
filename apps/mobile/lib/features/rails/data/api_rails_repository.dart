import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/network/file_transfer.dart';
import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/rails/data/rail_dtos.dart';
import 'package:cashdeck/features/rails/domain/payment_rail.dart';
import 'package:dio/dio.dart';

final class ApiRailsRepository implements RailsRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/rails';

  String _rail(String id) => '$path/${Uri.encodeComponent(id)}';

  @override
  Future<Result<List<PaymentRail>>> rails(EntityKind owner) =>
      guardRequest(() async {
        final response = await _dio.get<Object?>(
          path,
          queryParameters: {'entity': entityKindToJson(owner)},
        );
        return asJsonMapList(unwrapData(response.data))
            .map(railFromJson)
            .toList();
      });

  @override
  Future<Result<PaymentRail>> authorize(String id) => guardRequest(() async {
    final response = await _dio.post<Object?>(
      '${_rail(id)}/authorize',
      data: const <String, Object?>{},
    );
    return railFromJson(asJsonMap(unwrapData(response.data)));
  });

  /// A 404 here means nothing is stored yet, which the screen shows as such.
  @override
  Future<Result<RailCredentials>> credentials(String id) async {
    final result = await guardRequest(() async {
      final response = await _dio.get<Object?>('${_rail(id)}/credentials');
      return credentialsFromJson(asJsonMap(unwrapData(response.data)));
    });
    if (result case Err(failure: NotFoundFailure())) {
      return const Ok(RailCredentials.none);
    }
    return result;
  }

  @override
  Future<Result<List<RailCheck>>> test(String id) => guardRequest(() async {
    final response = await _dio.post<Object?>(
      '${_rail(id)}/test',
      data: const <String, Object?>{},
    );
    return readMapList(
      asJsonMap(unwrapData(response.data)),
      'checks',
    ).map(checkFromJson).toList();
  });

  @override
  Future<Result<void>> remove(String id) =>
      guardRequest(() => _dio.delete<Object?>(_rail(id)));

  @override
  Future<Result<RailCredentials>> uploadCredential(
    String id,
    LocalFile file, {
    String? password,
    CalendarDate? validUntil,
  }) => guardRequest(() async {
    final field = file.extension == 'key' ? 'privateKey' : 'certificate';
    final response = await _dio.put<Object?>(
      '${_rail(id)}/credentials',
      data: {
        field: uploadBody(file),
        if (password != null && password.isNotEmpty)
          'certificatePassword': password,
        'certificateValidUntil': ?validUntil?.iso,
      },
    );
    return credentialsFromJson(asJsonMap(unwrapData(response.data)));
  });
}
