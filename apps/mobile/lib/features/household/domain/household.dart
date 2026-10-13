import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/domain/tax_id.dart';
import 'package:equatable/equatable.dart';

/// A person of the family whose Pix to or from the personal accounts moves
/// the household's own money, neither income nor spending.
final class HouseholdMember extends Equatable {
  const new({required this.name, required this.taxId});

  final String name;

  /// The CPF digits only.
  final String taxId;

  String get maskedTaxId => TaxIds.maskCpf(taxId);

  @override
  List<Object?> get props => [name, taxId];
}

enum MemberProblem { nameMissing, nameTooLong, cpfInvalid, cpfTaken, full }

/// The members besides the personal entity, saved whole on every change.
final class Household extends Equatable {
  const new(this.members);

  static const maxMembers = 10;
  static const maxNameLength = 80;

  final List<HouseholdMember> members;

  bool get isFull => members.length >= maxMembers;

  bool includes(String taxId) => members.any((member) => member.taxId == taxId);

  /// The first rule a new member with [name] and the typed [cpf] breaks, or
  /// null when it can join.
  MemberProblem? problemOf(String name, String cpf) {
    final trimmed = name.trim();
    final digits = TaxIds.clean(EntityKind.personal, cpf);
    if (isFull) return MemberProblem.full;
    if (trimmed.isEmpty) return MemberProblem.nameMissing;
    if (trimmed.length > maxNameLength) return MemberProblem.nameTooLong;
    if (!TaxIds.isValidCpf(digits)) return MemberProblem.cpfInvalid;
    return includes(digits) ? MemberProblem.cpfTaken : null;
  }

  /// Every member follows the server's rules: a name, a valid CPF, no
  /// repeated CPF and at most [maxMembers].
  bool get isValid {
    final ids = members.map((member) => member.taxId).toSet();
    return members.length <= maxMembers &&
        ids.length == members.length &&
        members.every(_isValidMember);
  }

  static bool _isValidMember(HouseholdMember member) {
    final name = member.name.trim();
    return name.isNotEmpty &&
        name.length <= maxNameLength &&
        TaxIds.isValidCpf(member.taxId);
  }

  /// With a member named [name] and the CPF typed as [cpf], cleaned.
  Household adding(String name, String cpf) => Household([
    ...members,
    HouseholdMember(
      name: name.trim(),
      taxId: TaxIds.clean(EntityKind.personal, cpf),
    ),
  ]);

  Household removing(HouseholdMember member) => Household([
    for (final kept in members)
      if (kept.taxId != member.taxId) kept,
  ]);

  @override
  List<Object?> get props => [members];
}

abstract interface class HouseholdRepository {
  Future<Result<Household>> get();

  /// Replaces the whole list and returns what the server stored.
  Future<Result<Household>> save(Household household);
}
