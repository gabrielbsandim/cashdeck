import 'package:cashdeck/features/entities/domain/entity_scope.dart';

/// CPF for a person, CNPJ for a company, with the check digits the server
/// verifies. A CNPJ may be alphanumeric in its first twelve characters.
abstract final class TaxIds {
  static final _cpfShape = RegExp(r'^\d{11}$');
  static final _cnpjShape = RegExp(r'^[0-9A-Z]{12}\d{2}$');
  static final _repeated = RegExp(r'^(.)\1*$');
  static final _notDigit = RegExp('[^0-9]');
  static final _notAlphanumeric = RegExp('[^0-9A-Z]');

  static const _cpfSeparators = {3: '.', 6: '.', 9: '-'};
  static const _cnpjSeparators = {2: '.', 5: '.', 8: '/', 12: '-'};
  static const _cnpjFirstWeights = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
  static const List<int> _cnpjSecondWeights = [6, ..._cnpjFirstWeights];

  static int lengthOf(EntityKind kind) => switch (kind) {
    EntityKind.personal => 11,
    EntityKind.company => 14,
  };

  /// [raw] without the mask, uppercased and cut to the kind's length.
  static String clean(EntityKind kind, String raw) {
    final stray = switch (kind) {
      EntityKind.personal => _notDigit,
      EntityKind.company => _notAlphanumeric,
    };
    final value = raw.toUpperCase().replaceAll(stray, '');
    final length = lengthOf(kind);
    return value.length > length ? value.substring(0, length) : value;
  }

  /// The mask applied to as much of [raw] as was typed.
  static String format(EntityKind kind, String raw) {
    final separators = switch (kind) {
      EntityKind.personal => _cpfSeparators,
      EntityKind.company => _cnpjSeparators,
    };
    final buffer = StringBuffer();
    for (final (index, char) in clean(kind, raw).split('').indexed) {
      buffer
        ..write(separators[index] ?? '')
        ..write(char);
    }
    return buffer.toString();
  }

  static bool isValid(EntityKind kind, String raw) {
    final value = clean(kind, raw);
    return switch (kind) {
      EntityKind.personal => isValidCpf(value),
      EntityKind.company => isValidCnpj(value),
    };
  }

  static bool isValidCpf(String value) {
    if (!_cpfShape.hasMatch(value) || _repeated.hasMatch(value)) return false;
    final first = _cpfDigit(value.substring(0, 9));
    final second = _cpfDigit(value.substring(0, 10));
    return value.endsWith('$first$second');
  }

  static bool isValidCnpj(String value) {
    if (!_cnpjShape.hasMatch(value) || _repeated.hasMatch(value)) return false;
    final first = _cnpjDigit(value.substring(0, 12), _cnpjFirstWeights);
    final second = _cnpjDigit(value.substring(0, 13), _cnpjSecondWeights);
    return value.endsWith('$first$second');
  }

  static int _cpfDigit(String body) {
    final start = body.length + 1;
    var sum = 0;
    for (final (index, unit) in body.codeUnits.indexed) {
      sum += (unit - 48) * (start - index);
    }
    final rest = sum * 10 % 11;
    return rest == 10 ? 0 : rest;
  }

  // Letters weigh their ASCII code minus 48, which leaves a numeric CNPJ
  // with the classic result.
  static int _cnpjDigit(String body, List<int> weights) {
    var sum = 0;
    for (final (index, unit) in body.codeUnits.indexed) {
      sum += (unit - 48) * weights[index];
    }
    final rest = sum % 11;
    return rest < 2 ? 0 : 11 - rest;
  }
}
