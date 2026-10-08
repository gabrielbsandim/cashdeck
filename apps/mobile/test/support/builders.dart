import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';

/// 2026-10-08 12:00 in Brazil.
final testNow = DateTime.utc(2026, 10, 8, 15);
const testToday = CalendarDate(2026, 10, 8);

Bill testBill({
  String id = 'bill-1',
  String payee = 'Payee Example',
  Money amount = const Money(12_345),
  CalendarDate dueDate = testToday,
  BillKind kind = BillKind.boleto,
  EntityKind owner = EntityKind.personal,
  BillStatus status = BillStatus.pending,
  BillSource source = BillSource.email,
  List<LadderStep> plan = LadderStep.values,
  String? paymentCode = '12345.67890',
  String? pixCode,
  List<PaymentAttempt> attempts = const [],
}) => Bill(
  id: id,
  payee: payee,
  amount: amount,
  dueDate: dueDate,
  kind: kind,
  owner: owner,
  status: status,
  source: source,
  plan: plan,
  paymentCode: paymentCode,
  pixCode: pixCode,
  attempts: attempts,
);

PaymentAttempt testAttempt(
  LadderStep step,
  AttemptOutcome outcome, {
  String rail = 'FakeRail',
  String? reason,
}) => PaymentAttempt(
  step: step,
  rail: rail,
  at: testNow,
  outcome: outcome,
  reason: reason,
);

Map<String, dynamic> billJson({
  String id = 'bill-1',
  String status = 'OPEN',
  Object? plan = const {
    'steps': [
      {'mode': 'AUTOMATIC', 'rail': 'MERCADO_PAGO_PAYOUTS'},
      {'mode': 'AUTOMATIC', 'rail': 'ASAAS'},
      {'mode': 'ASSISTED', 'rail': 'ASSISTED'},
    ],
    'currentStep': 0,
  },
  List<Object?>? attempts,
}) => {
  'id': id,
  'entityId': 'personal',
  'entityKind': 'PF',
  'kind': 'BOLETO',
  'status': status,
  'source': 'GMAIL',
  'payee': 'Payee Example',
  'amount': {'cents': 12345, 'currency': 'BRL'},
  'dueDate': '2026-10-08',
  'code': '12345.67890',
  'createdAt': '2026-10-08T12:00:00.000Z',
  'paidAt': null,
  'paidBy': null,
  'plan': plan,
  'attempts': ?attempts,
};
