import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:equatable/equatable.dart';

/// A mailbox read with a read-only grant, looking for bills.
final class Mailbox extends Equatable {
  const new({
    required this.id,
    required this.address,
    required this.owner,
    required this.lastReadAt,
    required this.billsFound,
    required this.emailsScanned,
  });

  final String id;
  final String address;
  final EntityKind owner;
  final DateTime lastReadAt;
  final int billsFound;
  final int emailsScanned;

  @override
  List<Object?> get props => [
    id,
    address,
    owner,
    lastReadAt,
    billsFound,
    emailsScanned,
  ];
}

/// The bank's registry of boletos issued against the entity's tax id.
final class DdaEnrollment extends Equatable {
  const new({
    required this.owner,
    required this.bank,
    required this.lastBatchAt,
    required this.boletos,
    required this.enabled,
  });

  final EntityKind owner;
  final String bank;
  final DateTime lastBatchAt;
  final int boletos;
  final bool enabled;

  @override
  List<Object?> get props => [owner, bank, lastBatchAt, boletos, enabled];
}

final class CaptureSources extends Equatable {
  const new({required this.mailboxes, required this.dda});

  final List<Mailbox> mailboxes;
  final List<DdaEnrollment> dda;

  @override
  List<Object?> get props => [mailboxes, dda];
}

abstract interface class CaptureRepository {
  Future<Result<CaptureSources>> sources();

  Future<Result<CaptureSources>> readNow(String mailboxId);

  Future<Result<CaptureSources>> disconnect(String mailboxId);

  Future<Result<CaptureSources>> setDda(EntityKind owner, {required bool on});
}
