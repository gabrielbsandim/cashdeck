import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/pix_contacts/domain/pix_contact.dart';

const Map<String, PixKeyType> _keyTypes = {
  'CPF': PixKeyType.cpf,
  'CNPJ': PixKeyType.cnpj,
  'EMAIL': PixKeyType.email,
  'PHONE': PixKeyType.phone,
  'EVP': PixKeyType.evp,
};

String pixKeyTypeToJson(PixKeyType type) => switch (type) {
  PixKeyType.cpf => 'CPF',
  PixKeyType.cnpj => 'CNPJ',
  PixKeyType.email => 'EMAIL',
  PixKeyType.phone => 'PHONE',
  PixKeyType.evp => 'EVP',
};

/// Null when absent or unknown, so a newer server never breaks the app.
PixKeyType? readOptionalKeyType(JsonMap json, String key) {
  final raw = json[key];
  return raw is String ? _keyTypes[raw] : null;
}

PixContact pixContactFromJson(JsonMap json) => PixContact(
  id: readString(json, 'id'),
  name: readString(json, 'name'),
  handle: readString(json, 'handle'),
  pixKey: readString(json, 'pixKey'),
  pixKeyType: readEnum(json, 'pixKeyType', _keyTypes),
  timesPaid: readOptionalInt(json, 'timesPaid') ?? 0,
  lastPaidAt: readOptionalDateTime(json, 'lastPaidAt'),
  createdAt: readDateTime(json, 'createdAt'),
);

/// A key the app cannot read goes as typed, for the server to judge.
JsonMap pixContactDraftToJson(PixContactDraft draft) {
  final (key, type) = draft.normalizedKey ?? (draft.pixKey.trim(), null);
  return {
    'name': draft.name.trim(),
    'handle': draft.handle.trim(),
    'pixKey': key,
    if (type != null) 'pixKeyType': pixKeyTypeToJson(type),
  };
}

JsonMap pixPayeeToJson(PixPayee payee, EntityKind entity) {
  final entityJson = {'entity': entityKindToJson(entity)};
  final draft = payee.draft;
  if (draft == null) return {'contactId': payee.contactId, ...entityJson};
  final contact = pixContactDraftToJson(draft)..remove('handle');
  return {...contact, ...entityJson};
}

JsonMap pixTransferToJson(PixPayee payee, EntityKind entity, Money amount) => {
  ...pixPayeeToJson(payee, entity),
  'amountCents': amount.cents,
};

PixPreview pixPreviewFromJson(JsonMap json) {
  final contact = asJsonMap(json['contact']);
  final recipient = asJsonMap(json['recipient']);
  return PixPreview(
    name: readString(contact, 'name'),
    pixKey: readString(contact, 'pixKey'),
    pixKeyType: readEnum(contact, 'pixKeyType', _keyTypes),
    isNew: readBool(contact, 'isNew'),
    recipient: PixRecipientCheck(
      name: readString(recipient, 'name'),
      taxId: readOptionalString(recipient, 'taxId'),
      bank: readOptionalString(recipient, 'bank'),
      verified: readBool(recipient, 'verified'),
    ),
  );
}
