import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/data/entity_directory.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';
import 'package:cashdeck/features/entities/domain/entity_profile.dart';
import 'package:dio/dio.dart';

final class ApiEntityProfileRepository implements EntityProfileRepository {
  const new(this._dio);

  final Dio _dio;

  @override
  Future<Result<List<EntityProfile>>> list() => guardRequest(() async {
    final response = await _dio.get<Object?>(EntityDirectory.path);
    return asJsonMapList(unwrapData(response.data))
        .map(entityProfileFromJson)
        .toList();
  });

  @override
  Future<Result<EntityProfile>> update(EntityProfile profile) =>
      guardRequest(() async {
        final regime = profile.taxRegime;
        final response = await _dio.patch<Object?>(
          '${EntityDirectory.path}/${Uri.encodeComponent(profile.id)}',
          data: {
            'name': profile.name,
            'taxId': profile.taxId,
            if (regime != null) 'taxRegime': taxRegimeToJson(regime),
          },
        );
        return entityProfileFromJson(asJsonMap(unwrapData(response.data)));
      });
}
