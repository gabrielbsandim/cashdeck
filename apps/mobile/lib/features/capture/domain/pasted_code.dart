import 'package:cashdeck/features/capture/domain/pix_br_code.dart';
import 'package:equatable/equatable.dart';

enum PixKeyType { cpf, cnpj, email, phone, random }

/// What a pasted or shared text pays: a Pix copy-and-paste, a boleto or
/// tax guide line, or a Pix key.
sealed class PastedCode extends Equatable {
  const new();
}

final class PastedPixCode extends PastedCode {
  const new(this.code);

  final PixBrCode code;

  @override
  List<Object?> get props => [code];
}

/// A barcode (44 digits) or digitable line (47 for a boleto, 48 for a
/// guide), digits only.
final class PastedBarcode extends PastedCode {
  const new(this.digits);

  final String digits;

  /// Arrecadação lines (utilities, DAS, DARF) start with 8.
  bool get isTaxGuide => digits.startsWith('8');

  @override
  List<Object?> get props => [digits];
}

final class PastedPixKey extends PastedCode {
  const new(this.type, this.value);

  final PixKeyType type;

  /// Normalized the way the DICT stores it: digits, lowercase or +55.
  final String value;

  @override
  List<Object?> get props => [type, value];
}

const _barcodeLengths = {44, 47, 48};

/// Reads [text] as the most specific code it holds; null for anything else.
/// The whole text is tried first, then a code inside a longer message.
PastedCode? readPastedCode(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final pix = parsePixBrCode(trimmed);
  if (pix != null) return PastedPixCode(pix);
  final barcode = _barcode(trimmed);
  if (barcode != null) return PastedBarcode(barcode);
  final key = readPixKey(trimmed);
  if (key != null) return key;
  final inner = findPixBrCode(trimmed);
  if (inner != null) return PastedPixCode(inner);
  for (final match in RegExp(r'\d[\d .-]{42,}\d').allMatches(trimmed)) {
    final found = _barcode(match[0]!);
    if (found != null) return PastedBarcode(found);
  }
  return null;
}

String? _barcode(String text) {
  final digits = text.replaceAll(RegExp(r'[\s.-]'), '');
  if (!RegExp(r'^\d+$').hasMatch(digits)) return null;
  return _barcodeLengths.contains(digits.length) ? digits : null;
}

final _random = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final _numeric = RegExp(r'^\+?[\d\s.()/-]+$');
final _alphanumericCnpj = RegExp(r'^[0-9A-Z]{12}\d{2}$');

/// A Pix key in any of its five forms. An 11 digit number that is a valid CPF
/// reads as one; otherwise it reads as a phone with its area code.
PastedPixKey? readPixKey(String text) {
  final trimmed = text.trim();
  if (_random.hasMatch(trimmed)) {
    return PastedPixKey(PixKeyType.random, trimmed.toLowerCase());
  }
  if (_email.hasMatch(trimmed) && trimmed.length <= 77) {
    return PastedPixKey(PixKeyType.email, trimmed.toLowerCase());
  }
  final compact = trimmed.replaceAll(RegExp(r'[\s./-]'), '').toUpperCase();
  if (_alphanumericCnpj.hasMatch(compact) && isValidCnpj(compact)) {
    return PastedPixKey(PixKeyType.cnpj, compact);
  }
  if (!_numeric.hasMatch(trimmed)) return null;
  return _numericKey(trimmed);
}

PastedPixKey? _numericKey(String text) {
  final digits = text.replaceAll(RegExp(r'\D'), '');
  if (text.startsWith('+')) return _phone(digits);
  if (digits.length == 11 && isValidCpf(digits)) {
    return PastedPixKey(PixKeyType.cpf, digits);
  }
  return _phone('55$digits');
}

/// +55, a two digit area code, then 8 digits (landline) or 9 starting with 9.
PastedPixKey? _phone(String digits) {
  final match = RegExp(r'^55([1-9]\d)(9\d{8}|[2-5]\d{7})$').firstMatch(digits);
  if (match == null) return null;
  return PastedPixKey(PixKeyType.phone, '+$digits');
}

bool isValidCpf(String digits) {
  if (!RegExp(r'^\d{11}$').hasMatch(digits)) return false;
  if (RegExp(r'^(\d)\1{10}$').hasMatch(digits)) return false;
  final values = digits.codeUnits.map((unit) => unit - 48).toList();
  return _mod11(values.sublist(0, 9), 10) == values[9] &&
      _mod11(values.sublist(0, 10), 11) == values[10];
}

int _mod11(List<int> values, int firstWeight) {
  var sum = 0;
  for (final (index, value) in values.indexed) {
    sum += value * (firstWeight - index);
  }
  final rest = sum % 11;
  return rest < 2 ? 0 : 11 - rest;
}

/// Numeric and the alphanumeric CNPJ issued since July 2026: letters count
/// as their ASCII code minus 48, the check digits stay numeric.
bool isValidCnpj(String text) {
  if (!_alphanumericCnpj.hasMatch(text)) return false;
  if (RegExp(r'^(\d)\1{13}$').hasMatch(text)) return false;
  final values = text.codeUnits.map((unit) => unit - 48).toList();
  return _cnpjDigit(values.sublist(0, 12)) == values[12] &&
      _cnpjDigit(values.sublist(0, 13)) == values[13];
}

int _cnpjDigit(List<int> values) {
  var sum = 0;
  var weight = values.length - 7;
  for (final value in values) {
    sum += value * weight;
    weight = weight == 2 ? 9 : weight - 1;
  }
  final rest = sum % 11;
  return rest < 2 ? 0 : 11 - rest;
}
