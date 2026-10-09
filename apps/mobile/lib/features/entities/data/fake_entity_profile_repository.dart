import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_profile.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/domain/tax_id.dart';

/// The seed's two entities, on public test tax ids.
final class FakeEntityProfileRepository implements EntityProfileRepository {
  new({this.latency = const Duration(milliseconds: 300)});

  final Duration latency;

  /// What the server answers for a tax id that fails its check digits.
  static const invalidTaxIdMessage = 'Tax id is not a valid CPF or CNPJ.';

  final Map<String, EntityProfile> _profiles = {
    'personal': const EntityProfile(
      id: 'personal',
      kind: EntityKind.personal,
      name: 'Conta pessoal',
      taxId: '52998224725',
    ),
    'company': const EntityProfile(
      id: 'company',
      kind: EntityKind.company,
      name: 'Empresa Exemplo Ltda',
      taxId: '11222333000181',
      taxRegime: TaxRegime.simplesNacional,
    ),
  };

  @override
  Future<Result<List<EntityProfile>>> list() async {
    await Future<void>.delayed(latency);
    return Ok(_profiles.values.toList());
  }

  @override
  Future<Result<EntityProfile>> update(EntityProfile profile) async {
    await Future<void>.delayed(latency);
    final current = _profiles[profile.id];
    if (current == null) return const Err(NotFoundFailure());
    if (!TaxIds.isValid(current.kind, profile.taxId)) {
      return const Err(ValidationFailure(invalidTaxIdMessage));
    }
    final saved = current.copyWith(
      name: profile.name.trim(),
      taxId: TaxIds.clean(current.kind, profile.taxId),
      taxRegime: profile.taxRegime,
    );
    _profiles[profile.id] = saved;
    return Ok(saved);
  }
}
