import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:equatable/equatable.dart';

enum RailKind {
  pixApi,
  boletoApi,
  taxApi,
  reserveFunding,
  bankApproval,
  assisted,
}

enum RailStatus { active, needsAuthorization, unavailable, always }

/// A way the ladder can pay, on step [step] of the entity's ladder.
final class PaymentRail extends Equatable {
  const new({
    required this.id,
    required this.kind,
    required this.owner,
    required this.step,
    required this.institution,
    required this.status,
  });

  final String id;
  final RailKind kind;
  final EntityKind owner;
  final int step;

  /// Empty for the assisted step, which needs no bank.
  final String institution;
  final RailStatus status;

  /// Only API rails carry credentials and a test.
  bool get configurable => switch (kind) {
    RailKind.pixApi || RailKind.boletoApi || RailKind.taxApi => true,
    RailKind.reserveFunding ||
    RailKind.bankApproval ||
    RailKind.assisted => false,
  };

  PaymentRail withStatus(RailStatus next) => PaymentRail(
    id: id,
    kind: kind,
    owner: owner,
    step: step,
    institution: institution,
    status: next,
  );

  @override
  List<Object?> get props => [id, kind, owner, step, institution, status];
}

/// The mTLS certificate and key of an API rail. Secrets never come back:
/// only what identifies them.
final class RailCredentials extends Equatable {
  const new({
    required this.certificateName,
    required this.certificateValidUntil,
    required this.apiKeyHint,
    required this.lastTestAt,
  });

  final String certificateName;
  final CalendarDate certificateValidUntil;

  /// The last four characters, the rest masked by the server.
  final String apiKeyHint;
  final DateTime? lastTestAt;

  @override
  List<Object?> get props => [
    certificateName,
    certificateValidUntil,
    apiKeyHint,
    lastTestAt,
  ];
}

enum RailCheckKind { certificate, apiKey, scope, payerAccount }

final class RailCheck extends Equatable {
  const new({required this.kind, required this.passed, this.millis});

  final RailCheckKind kind;
  final bool passed;
  final int? millis;

  @override
  List<Object?> get props => [kind, passed, millis];
}

abstract interface class RailsRepository {
  Future<Result<List<PaymentRail>>> rails(EntityKind owner);

  Future<Result<PaymentRail>> authorize(String id);

  Future<Result<RailCredentials>> credentials(String id);

  Future<Result<List<RailCheck>>> test(String id);

  Future<Result<void>> remove(String id);
}
