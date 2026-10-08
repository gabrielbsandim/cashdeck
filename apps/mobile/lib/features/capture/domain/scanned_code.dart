import 'package:equatable/equatable.dart';

enum ScannedKind { pix, boleto, taxGuide }

/// A code read by the camera, sorted by what it pays.
final class ScannedCode extends Equatable {
  const new({required this.kind, required this.value});

  final ScannedKind kind;
  final String value;

  @override
  List<Object?> get props => [kind, value];
}

/// A Pix BR Code starts with the EMV header; a barcode is 44 digits, and
/// tax and utility guides (arrecadação) start with 8. Anything else is null.
ScannedCode? classifyScannedCode(String raw) {
  final text = raw.trim();
  if (text.startsWith('000201')) {
    return ScannedCode(kind: ScannedKind.pix, value: text);
  }
  final digits = text.replaceAll(RegExp(r'\D'), '');
  if (digits.length != text.replaceAll(RegExp(r'[\s.-]'), '').length) {
    return null;
  }
  if (digits.length < 44 || digits.length > 48) return null;
  final kind = digits.startsWith('8')
      ? ScannedKind.taxGuide
      : ScannedKind.boleto;
  return ScannedCode(kind: kind, value: digits);
}
