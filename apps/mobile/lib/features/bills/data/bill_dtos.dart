import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';

const Map<String, BillKind> _kinds = {
  'BOLETO': BillKind.boleto,
  'PIX_KEY': BillKind.pixKey,
  'PIX_QR': BillKind.pixQr,
  'TAX_BARCODE': BillKind.taxBarcode,
  'DARF_NO_BARCODE': BillKind.darfNoBarcode,
};

/// The server statuses folded into what the app shows: a bill waiting for the
/// user to pay it by hand is still pending, its ladder says it is on step 3.
const Map<String, BillStatus> _statuses = {
  'OPEN': BillStatus.pending,
  'NEEDS_CONFIRMATION': BillStatus.needsConfirmation,
  'PROCESSING': BillStatus.scheduled,
  'AWAITING_BANK_APPROVAL': BillStatus.awaitingApproval,
  'ASSISTED': BillStatus.pending,
  'PAID': BillStatus.paid,
  'CANCELLED': BillStatus.cancelled,
};

const Map<String, BillSource> _sources = {
  'GMAIL': BillSource.email,
  'SHARE': BillSource.share,
  'CAMERA': BillSource.camera,
  'CHAT': BillSource.chat,
  'DDA': BillSource.dda,
  'MANUAL': BillSource.manual,
};

const Map<String, LadderStep> _steps = {
  'AUTOMATIC': LadderStep.automatic,
  'BANK_APPROVAL': LadderStep.bankApproval,
  'ASSISTED': LadderStep.assisted,
};

const Map<String, AttemptOutcome> _outcomes = {
  'PAID': AttemptOutcome.succeeded,
  'SUBMITTED': AttemptOutcome.waiting,
  'PENDING_APPROVAL': AttemptOutcome.waiting,
  'ASSISTED': AttemptOutcome.waiting,
  'IN_FLIGHT': AttemptOutcome.waiting,
  'FAILED': AttemptOutcome.failed,
};

const Map<String, PaymentMethod> _methods = {
  'PIX': PaymentMethod.pix,
  'BOLETO': PaymentMethod.boleto,
};

const Map<String, PaidBy> _paidBy = {
  'RAIL': PaidBy.rail,
  'USER': PaidBy.user,
  'STATEMENT': PaidBy.statement,
};

/// Not in the v1 contract yet; an unknown or missing value reads as null, so
/// the sheet falls back to a generic reason instead of failing the bill.
const Map<String, ConfirmationReason> _confirmationReasons = {
  'NEW_PAYEE': ConfirmationReason.newPayee,
  'ABOVE_THRESHOLD': ConfirmationReason.aboveThreshold,
  'AMOUNT_DEVIATION': ConfirmationReason.amountDeviation,
  'CAP_EXCEEDED': ConfirmationReason.capExceeded,
};

PaymentAttempt attemptFromJson(JsonMap json) => PaymentAttempt(
  step: lookupValue(_steps, readString(json, 'mode')),
  rail: readString(json, 'rail'),
  at: readDateTime(json, 'at'),
  outcome: lookupValue(_outcomes, readString(json, 'outcome')),
  reason: readOptionalString(json, 'reason'),
  method: switch (readOptionalString(json, 'method')) {
    null => null,
    final raw => lookupValue(_methods, raw),
  },
);

/// The server plan lists one step per rail; the app shows one per mode, so
/// repeated modes collapse in ladder order. No plan yet reads as empty.
List<LadderStep> planFromJson(Object? plan) {
  if (plan == null) return const [];
  if (plan is! JsonMap) {
    throw FormatException('Expected an object at "plan"', plan);
  }
  final modes = {
    for (final step in readMapList(plan, 'steps'))
      lookupValue(_steps, readString(step, 'mode')),
  };
  return modes.toList();
}

Bill billFromJson(JsonMap json) => Bill(
  id: readString(json, 'id'),
  payee: readOptionalString(json, 'payee') ?? '',
  amount: readMoney(json, 'amount'),
  dueDate: readDate(json, 'dueDate'),
  kind: lookupValue(_kinds, readString(json, 'kind')),
  owner: readEntityKind(json, 'entityKind'),
  status: lookupValue(_statuses, readString(json, 'status')),
  source: lookupValue(_sources, readString(json, 'source')),
  plan: planFromJson(json['plan']),
  paymentCode: readOptionalString(json, 'code'),
  pixCode: readOptionalString(json, 'pixCode'),
  attempts: readMapList(json, 'attempts').map(attemptFromJson).toList(),
  paidAt: readOptionalDateTime(json, 'paidAt'),
  paidBy: switch (readOptionalString(json, 'paidBy')) {
    null => null,
    final raw => lookupValue(_paidBy, raw),
  },
  confirmationReason: _confirmationReasons[json['confirmationReason']],
  autoDebit: json['autoDebit'] == true,
);
