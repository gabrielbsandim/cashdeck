import 'package:cashdeck/core/network/file_transfer.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/features/chat/domain/chat.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/pix_contacts/data/pix_contact_dtos.dart';

const Map<String, EntityScope> _scopes = {
  'PF': EntityScope.personal,
  'PJ': EntityScope.company,
  'ALL': EntityScope.consolidated,
};

const Map<String, ChatRole> _roles = {
  'user': ChatRole.user,
  'assistant': ChatRole.assistant,
};

const Map<String, ChatNotice> _notices = {
  'ROUND_LIMIT': ChatNotice.roundLimit,
  'TIME_BUDGET': ChatNotice.timeBudget,
  'EMPTY': ChatNotice.empty,
  'ERROR': ChatNotice.error,
};

const Map<String, ChatTool> _tools = {
  'CREATE_BILL_FROM_ATTACHMENT': ChatTool.createBillFromAttachment,
  'PAY_BILL': ChatTool.payBill,
  'CREATE_CATEGORY_RULE': ChatTool.createCategoryRule,
  'DRAFT_INVOICE': ChatTool.draftInvoice,
  'SEND_PIX': ChatTool.sendPix,
};

const Map<String, ChatActionStatus> _statuses = {
  'PENDING': ChatActionStatus.pending,
  'CONFIRMED': ChatActionStatus.confirmed,
  'CANCELLED': ChatActionStatus.cancelled,
  'FAILED': ChatActionStatus.failed,
  'EXPIRED': ChatActionStatus.expired,
};

String scopeToJson(EntityScope scope) => switch (scope) {
  EntityScope.personal => 'PF',
  EntityScope.company => 'PJ',
  EntityScope.consolidated => 'ALL',
};

ChatThread threadFromJson(JsonMap json) => ChatThread(
  id: readString(json, 'id'),
  scope: readEnum(json, 'scope', _scopes),
  title: readOptionalString(json, 'title'),
  createdAt: readDateTime(json, 'createdAt'),
  updatedAt: readDateTime(json, 'updatedAt'),
);

ChatAttachment attachmentFromJson(JsonMap json) => ChatAttachment(
  id: readString(json, 'id'),
  fileName: readString(json, 'fileName'),
  mimeType: readString(json, 'mimeType'),
  size: readInt(json, 'size'),
);

ChatActionDetails _details(JsonMap json) {
  final amount = readOptionalMap(json, 'amount');
  return ChatActionDetails(
    payee: readOptionalString(json, 'payee'),
    amount: amount == null ? null : moneyFromJson(amount),
    dueDate: readOptionalDate(json, 'dueDate'),
    fileName: readOptionalString(json, 'fileName'),
    pattern: readOptionalString(json, 'pattern'),
    category: readOptionalString(json, 'category'),
    payer: readOptionalString(json, 'payer'),
    pixKey: readOptionalString(json, 'pixKey'),
    pixKeyType: readOptionalKeyType(json, 'pixKeyType'),
    contactHandle: readOptionalString(json, 'contactHandle'),
    newContact: switch (json['newContact']) {
      final bool value => value,
      _ => null,
    },
    recipient: _recipient(readOptionalMap(json, 'recipient')),
  );
}

ChatRecipient? _recipient(JsonMap? json) {
  if (json == null) return null;
  return ChatRecipient(
    name: readString(json, 'name'),
    taxId: readOptionalString(json, 'taxId'),
    bank: readOptionalString(json, 'bank'),
    verified: json['verified'] == true,
  );
}

ChatActionResult? _result(JsonMap? json) {
  if (json == null) return null;
  return ChatActionResult(
    billId: readOptionalString(json, 'billId'),
    invoiceId: readOptionalString(json, 'invoiceId'),
    ruleId: readOptionalString(json, 'ruleId'),
    updated: readOptionalInt(json, 'updated'),
    contactId: readOptionalString(json, 'contactId'),
  );
}

EntityKind? _entity(JsonMap json) {
  final raw = readOptionalString(json, 'entity');
  return raw == null ? null : entityKindFromJson(raw);
}

ChatAction actionFromJson(JsonMap json) => ChatAction(
  id: readString(json, 'id'),
  threadId: readString(json, 'threadId'),
  tool: readEnum(json, 'tool', _tools),
  status: readEnum(json, 'status', _statuses),
  entity: _entity(json),
  needsEntity: readBool(json, 'needsEntity'),
  details: _details(readMap(json, 'details')),
  result: _result(readOptionalMap(json, 'result')),
  error: readOptionalString(json, 'error'),
  createdAt: readDateTime(json, 'createdAt'),
);

ChatNotice? _notice(JsonMap json) {
  final raw = readOptionalString(json, 'notice');
  return raw == null ? null : lookupValue(_notices, raw);
}

ChatMessage messageFromJson(JsonMap json) => ChatMessage(
  id: readString(json, 'id'),
  threadId: readString(json, 'threadId'),
  role: readEnum(json, 'role', _roles),
  text: readString(json, 'text'),
  notice: _notice(json),
  attachments: readMapList(
    json,
    'attachments',
  ).map(attachmentFromJson).toList(),
  actions: readMapList(json, 'actions').map(actionFromJson).toList(),
  createdAt: readDateTime(json, 'createdAt'),
);

JsonMap draftToJson(ChatDraft draft, {String? clientId}) => {
  'text': draft.text.trim(),
  if (draft.files.isNotEmpty)
    'attachments': [for (final file in draft.files) uploadBody(file)],
  'clientId': ?clientId,
};

/// No text asks for a new answer to the message as it is.
JsonMap regenerateToJson(String? text) => {'text': ?text?.trim()};
