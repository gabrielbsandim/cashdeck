import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';

const Map<String, EntityKind> _kinds = {
  'PF': EntityKind.personal,
  'PJ': EntityKind.company,
};

EntityKind entityKindFromJson(String raw) => lookupValue(_kinds, raw);

String entityKindToJson(EntityKind kind) => switch (kind) {
  EntityKind.personal => 'PF',
  EntityKind.company => 'PJ',
};

EntityKind readEntityKind(JsonMap json, String key) =>
    entityKindFromJson(readString(json, key));
