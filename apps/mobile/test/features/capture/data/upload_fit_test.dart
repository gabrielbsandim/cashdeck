import 'dart:typed_data';

import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/features/capture/data/upload_fit.dart';
import 'package:cashdeck/features/capture/domain/bill_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  LocalFile file(String name, int size) =>
      LocalFile(name: name, bytes: Uint8List(size));

  Future<Uint8List?> never(Uint8List _) =>
      throw StateError('a PDF or a small photo is never shrunk');

  test('a PDF goes as is, or not at all over the cap', () async {
    final small = file('conta.pdf', 10);

    expect(await fitForUpload(small, shrink: never), small);
    expect(
      await fitForUpload(file('grande.pdf', maxUploadBytes + 1), shrink: never),
      isNull,
    );
  });

  test('a small photo goes as is', () async {
    final photo = file('foto.jpg', shrinkAbove);

    expect(await fitForUpload(photo, shrink: never), photo);
  });

  test('a big photo is re-encoded as JPEG', () async {
    final fitted = await fitForUpload(
      file('foto.heic', shrinkAbove + 1),
      shrink: (_) async => Uint8List(10),
    );

    expect(fitted?.name, 'foto.jpg');
    expect(fitted?.mimeType, 'image/jpeg');
    expect(fitted?.bytes, hasLength(10));
    expect(
      (await fitForUpload(
        file('captura.da.tela.png', shrinkAbove + 1),
        shrink: (_) async => Uint8List(1),
      ))?.name,
      'captura.da.tela.jpg',
    );
  });

  test('a photo that does not shrink keeps its bytes, if it fits', () async {
    final photo = file('foto.png', shrinkAbove + 1);

    expect(await fitForUpload(photo, shrink: (_) async => null), photo);
    expect(
      await fitForUpload(
        photo,
        shrink: (_) async => Uint8List(shrinkAbove + 2),
      ),
      photo,
    );
    expect(
      await fitForUpload(
        file('enorme.heic', maxUploadBytes + 1),
        shrink: (_) async => null,
      ),
      isNull,
    );
  });

  group('shrinkImageNow', () {
    Uint8List png(int width, int height) =>
        img.encodePng(img.Image(width: width, height: height));

    test('caps the longest side and keeps the aspect', () {
      final wide = img.decodeJpg(shrinkImageNow(png(300, 100), maxSide: 150)!)!;
      final tall = img.decodeJpg(shrinkImageNow(png(100, 300), maxSide: 150)!)!;

      expect((wide.width, wide.height), (150, 50));
      expect((tall.width, tall.height), (50, 150));
    });

    test('a small image keeps its size; garbage is null', () {
      final same = img.decodeJpg(shrinkImageNow(png(40, 20))!)!;

      expect((same.width, same.height), (40, 20));
      expect(shrinkImageNow(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('runs off the UI isolate', () async {
      expect(await shrinkImage(png(10, 10)), isNotNull);
    });
  });
}
