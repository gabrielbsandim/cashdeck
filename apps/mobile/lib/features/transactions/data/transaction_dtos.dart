import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';

const Map<String, TransactionKind> _kinds = {
  'INCOME': TransactionKind.income,
  'EXPENSE': TransactionKind.expense,
  'TRANSFER': TransactionKind.transfer,
};

const Map<String, CategorySource> _sources = {
  'RULE': CategorySource.rule,
  'AI': CategorySource.ai,
  'USER': CategorySource.user,
};

double? _confidence(JsonMap json) {
  final value = json['categoryConfidence'];
  if (value == null) return null;
  if (value is num) return value.toDouble();
  throw FormatException('Expected a number at "categoryConfidence"', json);
}

CategorySource? _source(JsonMap json) {
  final raw = readOptionalString(json, 'categorizedBy');
  return raw == null ? null : lookupValue(_sources, raw);
}

Transaction transactionFromJson(JsonMap json) => Transaction(
  id: readString(json, 'id'),
  accountId: readString(json, 'accountId'),
  owner: readEntityKind(json, 'entityKind'),
  amount: readMoney(json, 'amount'),
  bookedOn: readDate(json, 'bookedOn'),
  description: readString(json, 'description'),
  kind: readEnum(json, 'kind', _kinds),
  categoryId: readOptionalString(json, 'categoryId'),
  transferId: readOptionalString(json, 'transferId'),
  invoiceId: readOptionalString(json, 'invoiceId'),
  note: readOptionalString(json, 'note'),
  categorizedBy: _source(json),
  categoryConfidence: _confidence(json),
  merchant: readOptionalString(json, 'merchant'),
  installment: _installment(readOptionalMap(json, 'installment')),
);

TransactionInstallment? _installment(JsonMap? json) {
  if (json == null) return null;
  return TransactionInstallment(
    number: readInt(json, 'number'),
    count: readInt(json, 'count'),
    purchaseOn: readOptionalDate(json, 'purchaseOn'),
  );
}

Category categoryFromJson(JsonMap json) => Category(
  id: readString(json, 'id'),
  key: readOptionalString(json, 'key'),
  name: readString(json, 'name'),
  icon: readOptionalString(json, 'icon'),
  parentId: readOptionalString(json, 'parentId'),
);

const Map<String, AccountType> _accountTypes = {
  'CHECKING': AccountType.checking,
  'SAVINGS': AccountType.savings,
  'CREDIT_CARD': AccountType.creditCard,
  'INVESTMENT': AccountType.investment,
  'WALLET': AccountType.wallet,
};

TransactionAccount accountFromJson(JsonMap json) => TransactionAccount(
  id: readString(json, 'id'),
  name: readString(json, 'name'),
  owner: readEntityKind(json, 'entityKind'),
  institution: readString(json, 'institution'),
  type: _accountTypes[readOptionalString(json, 'type')],
  balance: readMoney(json, 'balance'),
  isReserve: readBool(json, 'isReserve'),
  numberSuffix: readOptionalString(json, 'numberSuffix'),
  logo: _logo(readOptionalMap(json, 'logo')),
  credit: _credit(readOptionalMap(json, 'credit')),
  openBill: switch (readOptionalMap(json, 'openBill')) {
    final JsonMap bill => moneyFromJson(bill),
    null => null,
  },
  sync: _sync(readOptionalMap(json, 'sync')),
  connectionId: readOptionalString(json, 'connectionId'),
);

AccountLogo? _logo(JsonMap? json) {
  if (json == null) return null;
  return AccountLogo(
    imageUrl: readString(json, 'imageUrl'),
    color: readOptionalString(json, 'color'),
  );
}

CreditLine? _credit(JsonMap? json) {
  if (json == null) return null;
  return CreditLine(
    limit: readMoney(json, 'limit'),
    available: readMoney(json, 'available'),
    usedPercent: readOptionalInt(json, 'usedPercent'),
    closesOn: readOptionalDate(json, 'closesOn'),
    dueOn: readOptionalDate(json, 'dueOn'),
    brand: readOptionalString(json, 'brand'),
  );
}

/// A status this build does not know reads as outdated, never as fine.
const Map<String, SyncState> _syncStates = {
  'UPDATED': SyncState.updated,
  'UPDATING': SyncState.updating,
  'LOGIN_ERROR': SyncState.needsAction,
  'WAITING_USER_INPUT': SyncState.needsAction,
};

AccountSync? _sync(JsonMap? json) {
  if (json == null) return null;
  return AccountSync(
    state: _syncStates[readString(json, 'status')] ?? SyncState.outdated,
    lastSyncAt: readOptionalDateTime(json, 'lastSyncAt'),
  );
}

/// The query string of `GET /transactions`; empty filters are left out.
Map<String, Object> transactionQueryToJson(
  TransactionQuery query, {
  String? cursor,
  int limit = 30,
}) {
  final entity = query.entity;
  final search = query.search.trim();
  return {
    'limit': limit,
    if (entity != null) 'entity': entityKindToJson(entity),
    'accountId': ?query.accountId,
    'categoryId': ?query.categoryId,
    if (query.uncategorized) 'uncategorized': 'true',
    if (search.isNotEmpty) 'search': search,
    'from': ?query.from?.iso,
    'to': ?query.to?.iso,
    'cursor': ?cursor,
  };
}

/// The body of `PATCH /transactions/{id}`; an empty note travels as null.
Map<String, Object?> transactionUpdateToJson(TransactionUpdate update) {
  final note = update.note;
  return {
    'categoryId': ?update.categoryId,
    if (update.categoryId != null) 'applyToSimilar': update.applyToSimilar,
    if (note != null) 'note': note.trim().isEmpty ? null : note.trim(),
  };
}
