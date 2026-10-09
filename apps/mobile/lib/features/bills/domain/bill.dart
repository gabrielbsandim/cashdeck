import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:equatable/equatable.dart';

enum BillKind { boleto, pixKey, pixQr, taxBarcode, darfNoBarcode }

enum BillStatus {
  pending,

  /// Above a cap, to a new payee or an unusual amount: step 1 waits for an
  /// in-app confirmation and, without it, the bill goes to step 3.
  needsConfirmation,
  scheduled,
  awaitingApproval,
  paid,
  failed,
  cancelled,
}

enum BillSource { email, share, camera, chat, dda, manual }

/// The three ways a bill gets paid, tried in this order.
enum LadderStep { automatic, bankApproval, assisted }

enum AttemptOutcome { succeeded, failed, waiting }

/// How an attempt tried to pay: most boletos now carry a Pix BR Code, and the
/// ladder tries it before the barcode.
enum PaymentMethod { pix, boleto }

/// Who settled a paid bill: a rail on its own, or the user by hand.
enum PaidBy { rail, user }

/// Why step 1 waits for the user before it pays (plan 5.3).
enum ConfirmationReason {
  newPayee,
  aboveThreshold,
  amountDeviation,
  capExceeded,
}

final class PaymentAttempt extends Equatable {
  const new({
    required this.step,
    required this.rail,
    required this.at,
    required this.outcome,
    this.reason,
    this.method,
  });

  final LadderStep step;
  final String rail;
  final DateTime at;
  final AttemptOutcome outcome;
  final String? reason;
  final PaymentMethod? method;

  @override
  List<Object?> get props => [step, rail, at, outcome, reason, method];
}

final class Bill extends Equatable {
  const new({
    required this.id,
    required this.payee,
    required this.amount,
    required this.dueDate,
    required this.kind,
    required this.owner,
    required this.status,
    required this.source,
    required this.plan,
    this.paymentCode,
    this.pixCode,
    this.attempts = const [],
    this.paidAt,
    this.paidBy,
    this.confirmationReason,
  });

  final String id;
  final String payee;
  final Money amount;
  final CalendarDate dueDate;
  final BillKind kind;
  final EntityKind owner;
  final BillStatus status;
  final BillSource source;

  /// The steps able to pay this bill for its owner, in ladder order.
  final List<LadderStep> plan;

  /// The boleto line or the Pix payload, absent for a Pix key payment.
  final String? paymentCode;

  /// The Pix BR Code printed on a boleto that has one (a bolepix).
  final String? pixCode;

  /// Oldest first.
  final List<PaymentAttempt> attempts;
  final DateTime? paidAt;
  final PaidBy? paidBy;

  /// Set while [status] is [BillStatus.needsConfirmation], when the server
  /// says why; null reads as a generic safety rule.
  final ConfirmationReason? confirmationReason;

  bool get isBolepix => kind == BillKind.boleto && pixCode != null;

  bool get isTax =>
      kind == BillKind.taxBarcode || kind == BillKind.darfNoBarcode;

  /// Paid by hand, the only payment that can be undone.
  Bill markedPaid(DateTime at) => Bill(
    id: id,
    payee: payee,
    amount: amount,
    dueDate: dueDate,
    kind: kind,
    owner: owner,
    status: BillStatus.paid,
    source: source,
    plan: plan,
    paymentCode: paymentCode,
    pixCode: pixCode,
    attempts: attempts,
    paidAt: at,
    paidBy: PaidBy.user,
    confirmationReason: confirmationReason,
  );

  bool get isSettled =>
      status == BillStatus.paid || status == BillStatus.cancelled;

  bool isOverdue(CalendarDate today) => !isSettled && dueDate.isBefore(today);

  @override
  List<Object?> get props => [
    id,
    payee,
    amount,
    dueDate,
    kind,
    owner,
    status,
    source,
    plan,
    paymentCode,
    pixCode,
    attempts,
    paidAt,
    paidBy,
    confirmationReason,
  ];
}

/// Open bills before settled ones, each group by due date.
int byUrgency(Bill a, Bill b) {
  if (a.isSettled != b.isSettled) return a.isSettled ? 1 : -1;
  return a.dueDate.compareTo(b.dueDate);
}
