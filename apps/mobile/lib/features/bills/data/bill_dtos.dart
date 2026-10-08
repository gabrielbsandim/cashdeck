import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';

const Map<String, BillKind> _kinds = {
  'BOLETO': BillKind.boleto,
  'PIX_KEY': BillKind.pixKey,
  'PIX_QR': BillKind.pixQr,
  'TAX_BARCODE': BillKind.taxBarcode,
  'DARF_NO_BARCODE': BillKind.darfNoBarcode,
};

const Map<String, EntityKind> _owners = {
  'PF': EntityKind.personal,
  'PJ': EntityKind.company,
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
  'FAILED': AttemptOutcome.failed,
};

const Map<String, PaidBy> _paidBy = {'RAIL': PaidBy.rail, 'USER': PaidBy.user};

T _lookup<T>(Map<String, T> table, String raw) {
  final match = table[raw];
  if (match != null) return match;
  throw FormatException('Unknown value', raw);
}

Money moneyFromJson(JsonMap json) =>
    Money(readInt(json, 'cents'), currency: readString(json, 'currency'));

PaymentAttempt attemptFromJson(JsonMap json) => PaymentAttempt(
  step: _lookup(_steps, readString(json, 'mode')),
  rail: readString(json, 'rail'),
  at: readDateTime(json, 'at'),
  outcome: _lookup(_outcomes, readString(json, 'outcome')),
  reason: readOptionalString(json, 'reason'),
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
      _lookup(_steps, readString(step, 'mode')),
  };
  return modes.toList();
}

Bill billFromJson(JsonMap json) => Bill(
  id: readString(json, 'id'),
  payee: readOptionalString(json, 'payee') ?? '',
  amount: moneyFromJson(readMap(json, 'amount')),
  dueDate: readDate(json, 'dueDate'),
  kind: _lookup(_kinds, readString(json, 'kind')),
  owner: _lookup(_owners, readString(json, 'entityKind')),
  status: _lookup(_statuses, readString(json, 'status')),
  source: _lookup(_sources, readString(json, 'source')),
  plan: planFromJson(json['plan']),
  paymentCode: readOptionalString(json, 'code'),
  attempts: readMapList(json, 'attempts').map(attemptFromJson).toList(),
  paidAt: _optionalMoment(json, 'paidAt'),
  paidBy: switch (readOptionalString(json, 'paidBy')) {
    null => null,
    final raw => _lookup(_paidBy, raw),
  },
);

DateTime? _optionalMoment(JsonMap json, String key) {
  if (json[key] == null) return null;
  return readDateTime(json, key);
}
