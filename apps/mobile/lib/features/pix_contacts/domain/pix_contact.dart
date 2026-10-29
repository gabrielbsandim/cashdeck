import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/domain/tax_id.dart';
import 'package:equatable/equatable.dart';

/// CPF and CNPJ share one choice in the form; the digits tell them apart.
enum PixKeyType { cpf, cnpj, email, phone, evp }

/// Someone the user sends Pix to, called by name or by @handle in the chat.
final class PixContact extends Equatable {
  const new({
    required this.id,
    required this.name,
    required this.handle,
    required this.pixKey,
    required this.pixKeyType,
    required this.createdAt,
    this.timesPaid = 0,
    this.lastPaidAt,
  });

  final String id;
  final String name;

  /// Without the leading @.
  final String handle;
  final String pixKey;
  final PixKeyType pixKeyType;
  final int timesPaid;
  final DateTime? lastPaidAt;
  final DateTime createdAt;

  String get mention => '@$handle';

  /// Up to two letters, from the first and the last word of the name.
  String get initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '?';
    final first = words.first.characters1;
    if (words.length == 1) return first;
    return '$first${words.last.characters1}';
  }

  /// Accent and case insensitive, over the name and the handle.
  bool matches(String query) {
    final wanted = foldText(query.trim().replaceFirst('@', ''));
    if (wanted.isEmpty) return true;
    return foldText(name).contains(wanted) || handle.contains(wanted);
  }

  @override
  List<Object?> get props => [
    id,
    name,
    handle,
    pixKey,
    pixKeyType,
    timesPaid,
    lastPaidAt,
    createdAt,
  ];
}

extension on String {
  String get characters1 => isEmpty ? '' : substring(0, 1).toUpperCase();
}

const Map<String, String> _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', //
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', //
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', //
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', //
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', //
  'ç': 'c', 'ñ': 'n',
};

/// Lowercase, without accents, so "João" and "joao" match.
String foldText(String text) {
  final lower = text.toLowerCase();
  final buffer = StringBuffer();
  for (final char in lower.split('')) {
    buffer.write(_accents[char] ?? char);
  }
  return buffer.toString();
}

final _handleShape = RegExp(r'^[a-z0-9][a-z0-9._]{1,29}$');

bool isValidHandle(String handle) => _handleShape.hasMatch(handle);

/// "João da Silva" becomes "joao.silva": the first and the last word.
String handleFromName(String name) {
  final words = foldText(name)
      .replaceAll(RegExp('[^a-z0-9 ]'), ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return '';
  final parts = words.length == 1 ? words : [words.first, words.last];
  final handle = parts.join('.');
  return handle.length > 30 ? handle.substring(0, 30) : handle;
}

/// The four choices the form offers; CPF and CNPJ are one.
enum PixKeyKind { taxId, phone, email, evp }

PixKeyKind kindOf(PixKeyType type) => switch (type) {
  PixKeyType.cpf || PixKeyType.cnpj => PixKeyKind.taxId,
  PixKeyType.phone => PixKeyKind.phone,
  PixKeyType.email => PixKeyKind.email,
  PixKeyType.evp => PixKeyKind.evp,
};

final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _evp = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final _notDigit = RegExp('[^0-9]');

/// [raw] as the server stores it, with its type, or null when it is not a
/// key of [kind]. A phone without the country code gets +55.
(String, PixKeyType)? normalizePixKey(PixKeyKind kind, String raw) {
  final trimmed = raw.trim();
  final digits = trimmed.replaceAll(_notDigit, '');
  return switch (kind) {
    PixKeyKind.taxId when TaxIds.isValidCpf(digits) => (digits, PixKeyType.cpf),
    PixKeyKind.taxId when TaxIds.isValidCnpj(digits) => (
      digits,
      PixKeyType.cnpj,
    ),
    PixKeyKind.phone when digits.length == 10 || digits.length == 11 => (
      '+55$digits',
      PixKeyType.phone,
    ),
    PixKeyKind.phone when digits.length >= 12 && digits.length <= 13 => (
      '+$digits',
      PixKeyType.phone,
    ),
    PixKeyKind.email when _email.hasMatch(trimmed) => (
      trimmed.toLowerCase(),
      PixKeyType.email,
    ),
    PixKeyKind.evp when _evp.hasMatch(trimmed.toLowerCase()) => (
      trimmed.toLowerCase(),
      PixKeyType.evp,
    ),
    _ => null,
  };
}

/// Enough of [key] to recognize it in a list without showing all of it.
String maskPixKey(PixKeyType type, String key) => switch (type) {
  PixKeyType.cpf => TaxIds.maskCpf(key),
  PixKeyType.cnpj when key.length == 14 =>
    '${key.substring(0, 2)}.${key.substring(2, 5)}.${key.substring(5, 8)}'
        '/${key.substring(8, 12)}-${key.substring(12)}',
  PixKeyType.phone when key.length >= 4 =>
    '(**) *****-${key.substring(key.length - 4)}',
  PixKeyType.email => _maskEmail(key),
  PixKeyType.evp when key.length > 8 => '${key.substring(0, 8)}…',
  _ => key,
};

String _maskEmail(String key) {
  final at = key.indexOf('@');
  if (at < 1) return key;
  final visible = at < 3 ? key.substring(0, 1) : key.substring(0, 2);
  return '$visible***${key.substring(at)}';
}

enum ContactProblem { nameMissing, keyInvalid, handleInvalid }

/// What the form holds before it is saved.
final class PixContactDraft extends Equatable {
  const new({
    required this.name,
    required this.handle,
    required this.keyKind,
    required this.pixKey,
  });

  final String name;
  final String handle;
  final PixKeyKind keyKind;
  final String pixKey;

  (String, PixKeyType)? get normalizedKey => normalizePixKey(keyKind, pixKey);

  /// The first rule the draft breaks, or null when it can be saved.
  ContactProblem? get problem {
    if (name.trim().isEmpty) return ContactProblem.nameMissing;
    if (normalizedKey == null) return ContactProblem.keyInvalid;
    return isValidHandle(handle.trim()) ? null : ContactProblem.handleInvalid;
  }

  @override
  List<Object?> get props => [name, handle, keyKind, pixKey];
}

/// Who a Pix goes to: a saved contact, or a new name and key that becomes one
/// once the Pix is sent.
final class PixPayee extends Equatable {
  const new contact(String this.contactId) : draft = null;

  const new newKey(PixContactDraft this.draft) : contactId = null;

  final String? contactId;
  final PixContactDraft? draft;

  @override
  List<Object?> get props => [contactId, draft];
}

/// The holder the central bank directory names for the key, or the name the
/// user gave when the lookup failed.
final class PixRecipientCheck extends Equatable {
  const new({
    required this.name,
    required this.verified,
    this.taxId,
    this.bank,
  });

  final String name;
  final String? taxId;
  final String? bank;
  final bool verified;

  @override
  List<Object?> get props => [name, taxId, bank, verified];
}

final class PixPreview extends Equatable {
  const new({
    required this.name,
    required this.pixKey,
    required this.pixKeyType,
    required this.isNew,
    required this.recipient,
  });

  final String name;
  final String pixKey;
  final PixKeyType pixKeyType;
  final bool isNew;
  final PixRecipientCheck recipient;

  @override
  List<Object?> get props => [name, pixKey, pixKeyType, isNew, recipient];
}

abstract interface class PixContactsRepository {
  /// Most recently paid first, then by name.
  Future<Result<List<PixContact>>> list({String? search});

  Future<Result<PixContact>> create(PixContactDraft draft);

  Future<Result<PixContact>> update(String id, PixContactDraft draft);

  Future<Result<void>> delete(String id);

  Future<Result<PixPreview>> preview(PixPayee payee, EntityKind entity);

  /// Sends now; resolves with the bill the Pix became, which holds its receipt.
  Future<Result<String>> send(PixPayee payee, EntityKind entity, Money amount);
}
