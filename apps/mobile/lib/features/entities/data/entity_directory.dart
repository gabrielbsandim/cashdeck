import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:dio/dio.dart';

/// Resolves the server id of the personal or company entity, which some
/// bodies take instead of the kind. Read once per repository.
final class EntityDirectory {
  new(this._dio);

  final Dio _dio;
  Map<EntityKind, String>? _ids;

  static const path = '/api/v1/entities';

  Future<String> idOf(EntityKind kind) async {
    final ids = _ids ??= await _load();
    final id = ids[kind];
    if (id != null) return id;
    throw FormatException('No entity of kind', kind.name);
  }

  Future<Map<EntityKind, String>> _load() async {
    final response = await _dio.get<Object?>(path);
    return {
      for (final entity in asJsonMapList(unwrapData(response.data)))
        readEntityKind(entity, 'kind'): readString(entity, 'id'),
    };
  }
}
