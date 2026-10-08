import 'dart:convert';
import 'dart:typed_data';

import 'package:cashdeck/core/files/file_chooser.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/files/plain_pdf.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart' show XFile;

final class _Picked extends PlatformFile {
  @override
  String get name => 'cert.pfx';

  @override
  Uri get uri => Uri.file('/tmp/cert.pfx');

  @override
  XFile get xFile => XFile('/tmp/cert.pfx');

  @override
  int? lengthSync() => 3;

  @override
  Future<int?> length() async => 3;

  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList([1, 2, 3]);

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(Uint8List(3));
}

void main() {
  test('a file knows its extension', () {
    expect(LocalFile(name: 'Conta.PDF', bytes: Uint8List(0)).extension, 'pdf');
    expect(LocalFile(name: 'README', bytes: Uint8List(0)).extension, isEmpty);
  });

  test('the platform chooser reads the picked file', () async {
    List<String>? asked;
    Future<PlatformFile?> pick({
      FileType type = FileType.any,
      List<String>? allowedExtensions,
    }) async {
      asked = allowedExtensions;
      return allowedExtensions!.contains('pfx') ? _Picked() : null;
    }

    final chooser = PlatformFileChooser(pick: pick);
    final file = await chooser.choose(['pfx']);

    expect(asked, ['pfx']);
    expect(file?.name, 'cert.pfx');
    expect(file?.bytes, [1, 2, 3]);
    expect(await chooser.choose(['pdf']), isNull);
    expect(const PlatformFileChooser(), isA<FileChooser>());
  });

  test('the fake chooser answers what it was given', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final chooser = container.read(fileChooserProvider) as FakeFileChooser;

    expect(await chooser.choose(['pdf']), isNull);
    expect(chooser.requests.single, ['pdf']);
  });

  test('builds a PDF with the lines in it', () {
    final pdf = latin1.decode(plainPdf(['Comprovante', r'R$ (10)']));

    expect(pdf, startsWith('%PDF-1.4'));
    expect(pdf, contains('(Comprovante) Tj'));
    expect(pdf, contains(r'(R$ \(10\)) Tj'));
    expect(pdf, endsWith('%%EOF\n'));
  });
}
