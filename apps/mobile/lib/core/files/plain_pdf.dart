import 'dart:convert';
import 'dart:typed_data';

const _page =
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
    '/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>';
const _font =
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
    '/Encoding /WinAnsiEncoding >>';

/// A one-page PDF with [lines] in Helvetica, enough for the fake backend to
/// hand the share sheet a real document. Latin-1 text only.
Uint8List plainPdf(List<String> lines) {
  String escape(String line) => line
      .replaceAll(r'\', r'\\')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)');
  final text = StringBuffer('BT /F1 12 Tf 56 780 Td 16 TL\n');
  for (final line in lines) {
    text.write('(${escape(line)}) Tj T*\n');
  }
  text.write('ET');
  final stream = latin1.encode(text.toString());
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    _page,
    '<< /Length ${stream.length} >>\nstream\n${latin1.decode(stream)}\nendstream',
    _font,
  ];
  final out = BytesBuilder()..add(latin1.encode('%PDF-1.4\n'));
  final offsets = <int>[];
  for (var index = 0; index < objects.length; index++) {
    offsets.add(out.length);
    out.add(latin1.encode('${index + 1} 0 obj\n${objects[index]}\nendobj\n'));
  }
  final xref = out.length;
  final table = StringBuffer('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    table.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  table.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  out.add(latin1.encode(table.toString()));
  return out.toBytes();
}
