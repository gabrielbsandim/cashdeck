import 'dart:convert';

import 'package:cashdeck/core/money/money.dart';
import 'package:equatable/equatable.dart';

/// What a Pix BR Code (the EMV QR behind "Pix copia e cola") says about the
/// payment, read before the bill is captured.
final class PixBrCode extends Equatable {
  const new({
    required this.payload,
    this.merchantName,
    this.merchantCity,
    this.amount,
    this.pixKey,
    this.url,
  });

  final String payload;
  final String? merchantName;
  final String? merchantCity;

  /// Null when the payer chooses the amount.
  final Money? amount;

  /// A static code carries the key; a dynamic one a URL the bank resolves.
  final String? pixKey;
  final String? url;

  @override
  List<Object?> get props => [
    payload,
    merchantName,
    merchantCity,
    amount,
    pixKey,
    url,
  ];
}

const _header = '000201';
const _crcTag = '6304';
const _pixGui = 'br.gov.bcb.pix';

/// CRC16/CCITT-FALSE as hex, the checksum a BR Code ends with.
String crc16Ccitt(String text) {
  var crc = 0xFFFF;
  for (final byte in utf8.encode(text)) {
    crc ^= byte << 8;
    for (var bit = 0; bit < 8; bit++) {
      final carry = crc & 0x8000 != 0;
      crc = (crc << 1) & 0xFFFF;
      if (carry) crc ^= 0x1021;
    }
  }
  return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
}

/// [body] with its checksum field appended, as a bank would print it.
String withPixCrc(String body) => '$body$_crcTag${crc16Ccitt('$body$_crcTag')}';

/// Null when [raw] is not a BR Code, its fields do not parse or the CRC16
/// does not match.
PixBrCode? parsePixBrCode(String raw) {
  final payload = raw.trim();
  if (!payload.startsWith(_header) || payload.length < 12) return null;
  final checked = payload.substring(0, payload.length - 4);
  if (!checked.endsWith(_crcTag)) return null;
  final crc = payload.substring(payload.length - 4).toUpperCase();
  if (crc16Ccitt(checked) != crc) return null;
  final fields = _fields(payload);
  if (fields == null) return null;
  final account = _pixAccount(fields);
  return PixBrCode(
    payload: payload,
    merchantName: _text(fields['59']),
    merchantCity: _text(fields['60']),
    amount: _amount(fields['54']),
    pixKey: _text(account?['01']),
    url: _text(account?['25']),
  );
}

/// The first valid BR Code inside [text], which bank apps often share with a
/// sentence around it.
PixBrCode? findPixBrCode(String text) {
  final whole = parsePixBrCode(text);
  if (whole != null) return whole;
  for (final start in _indexesOf(text, _header)) {
    for (final tag in _indexesOf(text, _crcTag, from: start)) {
      final end = tag + _crcTag.length + 4;
      if (end > text.length) break;
      final found = parsePixBrCode(text.substring(start, end));
      if (found != null) return found;
    }
  }
  return null;
}

Iterable<int> _indexesOf(String text, String pattern, {int from = 0}) sync* {
  var index = text.indexOf(pattern, from);
  while (index >= 0) {
    yield index;
    index = text.indexOf(pattern, index + 1);
  }
}

/// EMV TLV: two digits of id, two of length, then the value.
Map<String, String>? _fields(String data) {
  final fields = <String, String>{};
  var index = 0;
  while (index < data.length) {
    if (index + 4 > data.length) return null;
    final length = int.tryParse(data.substring(index + 2, index + 4));
    final end = index + 4 + (length ?? data.length);
    if (length == null || end > data.length) return null;
    fields[data.substring(index, index + 2)] = data.substring(index + 4, end);
    index = end;
  }
  return fields;
}

/// Merchant account templates live in ids 26 to 51; Pix is the one whose
/// GUI is br.gov.bcb.pix.
Map<String, String>? _pixAccount(Map<String, String> fields) {
  for (var id = 26; id <= 51; id++) {
    final template = fields['$id'];
    if (template == null) continue;
    final inner = _fields(template);
    if (inner?['00']?.toLowerCase() == _pixGui) return inner;
  }
  return null;
}

String? _text(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

Money? _amount(String? value) {
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(value ?? '');
  if (match == null) return null;
  final cents = int.parse(match[1]!) * 100 + int.parse(_cents(match[2]));
  if (cents == 0) return null;
  return Money(cents);
}

String _cents(String? decimals) => (decimals ?? '').padRight(2, '0');
