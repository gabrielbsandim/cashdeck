import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:equatable/equatable.dart';

enum TaxRegime { simplesNacional, mei, lucroPresumido, lucroReal }

/// The name and tax id that issuers, payment rails and DDA act under.
final class EntityProfile extends Equatable {
  const new({
    required this.id,
    required this.kind,
    required this.name,
    required this.taxId,
    this.taxRegime,
  });

  final String id;
  final EntityKind kind;
  final String name;

  /// Unmasked: the CPF or CNPJ characters only.
  final String taxId;

  /// Null for a person; a company always has one.
  final TaxRegime? taxRegime;

  EntityProfile copyWith({String? name, String? taxId, TaxRegime? taxRegime}) =>
      EntityProfile(
        id: id,
        kind: kind,
        name: name ?? this.name,
        taxId: taxId ?? this.taxId,
        taxRegime: taxRegime ?? this.taxRegime,
      );

  @override
  List<Object?> get props => [id, kind, name, taxId, taxRegime];
}

abstract interface class EntityProfileRepository {
  /// The person first, then the company.
  Future<Result<List<EntityProfile>>> list();

  Future<Result<EntityProfile>> update(EntityProfile profile);
}
