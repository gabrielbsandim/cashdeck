import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/capture/domain/pasted_code.dart';
import 'package:cashdeck/features/capture/domain/scanned_code.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:equatable/equatable.dart';

/// Where a captured code came from, as the bill's source says.
enum CaptureChannel { camera, share, manual }

/// The JSON body (base64 included) must stay under the host's 4.5 MB request
/// cap, which leaves about 3.3 MB for the file itself.
const maxUploadBytes = 3300000;

/// A bill to capture from a code: one of [paymentCode], [pixCode] or
/// [pixKey], or a barcode plus its Pix (a "boleto com Pix").
final class BillDraft extends Equatable {
  const new({
    required this.owner,
    required this.channel,
    this.paymentCode,
    this.pixCode,
    this.pixKey,
    this.amount,
    this.dueDate,
    this.payee,
  });

  factory fromScanned(
    ScannedCode code,
    EntityKind owner, {
    CaptureChannel channel = CaptureChannel.camera,
  }) => switch (code.kind) {
    ScannedKind.pix => BillDraft(
      owner: owner,
      channel: channel,
      pixCode: code.value,
    ),
    ScannedKind.boleto || ScannedKind.taxGuide => BillDraft(
      owner: owner,
      channel: channel,
      paymentCode: code.value,
    ),
  };

  factory fromPasted(
    PastedCode code,
    EntityKind owner, {
    CaptureChannel channel = CaptureChannel.manual,
  }) => switch (code) {
    PastedPixCode(:final code) => BillDraft(
      owner: owner,
      channel: channel,
      pixCode: code.payload,
    ),
    PastedBarcode(:final digits) => BillDraft(
      owner: owner,
      channel: channel,
      paymentCode: digits,
    ),
    PastedPixKey(:final value) => BillDraft(
      owner: owner,
      channel: channel,
      pixKey: value,
    ),
  };

  final EntityKind owner;
  final CaptureChannel channel;
  final String? paymentCode;
  final String? pixCode;
  final String? pixKey;
  final Money? amount;
  final CalendarDate? dueDate;
  final String? payee;

  /// The same draft with what the user typed; null leaves a field as it was.
  BillDraft copyWith({
    Money? amount,
    CalendarDate? dueDate,
    String? payee,
    String? pixCode,
  }) => BillDraft(
    owner: owner,
    channel: channel,
    paymentCode: paymentCode,
    pixCode: pixCode ?? this.pixCode,
    pixKey: pixKey,
    amount: amount ?? this.amount,
    dueDate: dueDate ?? this.dueDate,
    payee: payee ?? this.payee,
  );

  @override
  List<Object?> get props => [
    owner,
    channel,
    paymentCode,
    pixCode,
    pixKey,
    amount,
    dueDate,
    payee,
  ];
}

/// How a capture ended when it did not fail: the bill exists, or the user
/// has something to add before it can.
sealed class CaptureOutcome extends Equatable {
  const new();
}

final class BillCaptured extends CaptureOutcome {
  const new({required this.billId, this.duplicate = false});

  final String billId;

  /// The same code was captured before; the server returned that bill.
  final bool duplicate;

  @override
  List<Object?> get props => [billId, duplicate];
}

/// A Pix QR without an amount, or a key: the server asks for the due date
/// and, when [amount] is true, the amount before it captures the bill.
final class CaptureDetailsNeeded extends CaptureOutcome {
  const new({required this.amount});

  final bool amount;

  @override
  List<Object?> get props => [amount];
}

/// The file stays above [maxUploadBytes] even after shrinking.
final class CaptureFileTooLarge extends CaptureOutcome {
  const new(this.bytes);

  final int bytes;

  @override
  List<Object?> get props => [bytes];
}

/// The server read the file and found no payment code in it.
final class CaptureNothingFound extends CaptureOutcome {
  const new();

  @override
  List<Object?> get props => [];
}
