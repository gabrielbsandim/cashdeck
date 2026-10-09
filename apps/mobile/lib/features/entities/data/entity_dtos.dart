import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/features/entities/domain/entity_profile.dart';
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

const Map<String, TaxRegime> _regimes = {
  'SIMPLES_NACIONAL': TaxRegime.simplesNacional,
  'MEI': TaxRegime.mei,
  'LUCRO_PRESUMIDO': TaxRegime.lucroPresumido,
  'LUCRO_REAL': TaxRegime.lucroReal,
};

String taxRegimeToJson(TaxRegime regime) =>
    _regimes.entries.firstWhere((entry) => entry.value == regime).key;

EntityProfile entityProfileFromJson(JsonMap json) {
  final regime = readOptionalString(json, 'taxRegime');
  return EntityProfile(
    id: readString(json, 'id'),
    kind: readEntityKind(json, 'kind'),
    name: readString(json, 'name'),
    taxId: readString(json, 'taxId'),
    taxRegime: regime == null ? null : lookupValue(_regimes, regime),
  );
}
