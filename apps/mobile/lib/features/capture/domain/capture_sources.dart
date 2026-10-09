import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/capture/domain/bill_draft.dart';
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

  /// Null until the first read.
  final DateTime? lastReadAt;
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

  /// Null until the bank sends the first batch.
  final DateTime? lastBatchAt;
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

  /// The provider's consent page for a read-only mailbox grant; the server
  /// finishes the OAuth flow and the mailbox shows up in [sources].
  Future<Result<Uri>> mailboxAuthorizationUrl(EntityKind owner);

  /// A bill PDF or photo the user shared into the app, for the server to read.
  /// Photos are shrunk to fit the upload cap first.
  Future<Result<CaptureOutcome>> submitFile(LocalFile file, EntityKind owner);

  /// A code scanned, shared or typed; the server builds the bill from it.
  Future<Result<CaptureOutcome>> capture(BillDraft draft);
}
