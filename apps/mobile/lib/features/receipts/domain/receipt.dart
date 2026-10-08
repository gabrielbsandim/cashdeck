import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:equatable/equatable.dart';

/// The proof the paying rail returned, kept on the user's server.
final class BankProof extends Equatable {
  const new({
    required this.rail,
    required this.amount,
    required this.paidAt,
    required this.payer,
    required this.receiver,
    required this.transactionId,
    required this.authentication,
  });

  final String rail;
  final Money amount;
  final DateTime paidAt;
  final String payer;
  final String receiver;

  /// Null when the rail does not return one.
  final String? transactionId;
  final String? authentication;

  @override
  List<Object?> get props => [
    rail,
    amount,
    paidAt,
    payer,
    receiver,
    transactionId,
    authentication,
  ];
}

final class Attachment extends Equatable {
  const new({required this.id, required this.fileName});

  final String id;
  final String fileName;

  @override
  List<Object?> get props => [id, fileName];
}

/// What proves a bill was paid: the bank's proof when a rail paid it, and
/// any file the user attached.
final class Receipt extends Equatable {
  const new({required this.billId, this.proof, this.attachments = const []});

  final String billId;
  final BankProof? proof;
  final List<Attachment> attachments;

  @override
  List<Object?> get props => [billId, proof, attachments];
}

abstract interface class ReceiptsRepository {
  Future<Result<Receipt>> receipt(String billId);

  /// The bank's proof as a PDF, ready for the share sheet.
  Future<Result<LocalFile>> document(String billId);

  Future<Result<Receipt>> attach(String billId, LocalFile file);
}
