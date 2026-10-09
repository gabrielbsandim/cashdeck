import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/chat/domain/chat.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';

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
  bool autoDebit = false,
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
  autoDebit: autoDebit,
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

Transaction testTransaction({
  String id = 'tx-1',
  String accountId = 'acc-1',
  EntityKind owner = EntityKind.personal,
  Money amount = const Money(-4_590),
  CalendarDate bookedOn = testToday,
  String description = 'Padaria Exemplo',
  TransactionKind kind = TransactionKind.expense,
  String? categoryId,
  String? transferId,
  String? note,
  CategorySource? categorizedBy,
  double? categoryConfidence,
}) => Transaction(
  id: id,
  accountId: accountId,
  owner: owner,
  amount: amount,
  bookedOn: bookedOn,
  description: description,
  kind: kind,
  categoryId: categoryId,
  transferId: transferId,
  note: note,
  categorizedBy: categorizedBy,
  categoryConfidence: categoryConfidence,
);

Map<String, dynamic> transactionJson({
  String id = 'tx-1',
  String kind = 'EXPENSE',
  String? categoryId = 'cat-groceries',
  String? categorizedBy = 'AI',
  Object? confidence = 0.8,
}) => {
  'id': id,
  'accountId': 'acc-1',
  'entityKind': 'PF',
  'amount': {'cents': -4590, 'currency': 'BRL'},
  'bookedOn': '2026-10-08',
  'description': 'Padaria Exemplo',
  'categoryId': categoryId,
  'kind': kind,
  'transferId': null,
  'invoiceId': null,
  'note': null,
  'categorizedBy': categorizedBy,
  'categoryConfidence': confidence,
};

ChatAction testAction({
  String id = 'action-1',
  String threadId = 'thread-1',
  ChatTool tool = ChatTool.payBill,
  ChatActionStatus status = ChatActionStatus.pending,
  bool needsEntity = false,
  ChatActionDetails details = const ChatActionDetails(
    payee: 'Energia Exemplo',
    amount: Money(28_740),
    dueDate: testToday,
  ),
  String? error,
}) => ChatAction(
  id: id,
  threadId: threadId,
  tool: tool,
  status: status,
  needsEntity: needsEntity,
  entity: needsEntity ? null : EntityKind.personal,
  details: details,
  error: error,
  createdAt: testNow,
);

ChatMessage testMessage({
  String id = 'msg-1',
  String threadId = 'thread-1',
  ChatRole role = ChatRole.assistant,
  String text = 'Resposta de exemplo',
  ChatNotice? notice,
  List<ChatAttachment> attachments = const [],
  List<ChatAction> actions = const [],
}) => ChatMessage(
  id: id,
  threadId: threadId,
  role: role,
  text: text,
  notice: notice,
  attachments: attachments,
  actions: actions,
  createdAt: testNow,
);

ChatThread testThread({
  String id = 'thread-1',
  EntityScope scope = EntityScope.personal,
  String? title = 'Conversa de exemplo',
}) => ChatThread(
  id: id,
  scope: scope,
  title: title,
  createdAt: testNow,
  updatedAt: testNow,
);

/// An EMV field: two digit id, two digit length, then the value.
String tlv(String id, String value) =>
    '$id${value.length.toString().padLeft(2, '0')}$value';

/// A fictional static Pix BR Code with its CRC; [amount] null leaves the
/// amount to the payer.
String testPixCode({
  String? amount = '119.90',
  String name = 'LOJA EXEMPLO',
  String city = 'CURITIBA',
  String key = 'loja@exemplo.com',
}) {
  final account = tlv('00', 'br.gov.bcb.pix') + tlv('01', key);
  final body = [
    tlv('00', '01'),
    tlv('26', account),
    tlv('52', '0000'),
    tlv('53', '986'),
    if (amount != null) tlv('54', amount),
    tlv('58', 'BR'),
    tlv('59', name),
    tlv('60', city),
    tlv('62', tlv('05', '***')),
  ].join();
  final checked = '${body}6304';
  return '$checked${_crc(checked)}';
}

/// An independent CRC16/CCITT-FALSE, so the fixtures do not trust the code
/// under test.
String _crc(String text) {
  var crc = 0xFFFF;
  for (final unit in text.codeUnits) {
    crc ^= unit << 8;
    for (var bit = 0; bit < 8; bit++) {
      crc = crc & 0x8000 != 0
          ? ((crc << 1) ^ 0x1021) & 0xFFFF
          : (crc << 1) & 0xFFFF;
    }
  }
  return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
}

/// A fictional boleto digitable line (47 digits) and a tax guide line (48).
const testBoletoLine = '23793.38128 60000.000003 00000.000400 1 98760000011990';
const testGuideLine = '85890000014 7 76000328262 2 01000000000 5 00000000000 0';
