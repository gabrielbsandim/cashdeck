import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/domain/tax_id.dart';
import 'package:flutter/services.dart';

/// Masks a CPF as 000.000.000-00 and a CNPJ as 00.000.000/0000-00.
class TaxIdInputFormatter extends TextInputFormatter {
  new(this.kind);

  final EntityKind kind;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = TaxIds.format(kind, newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
