import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/features/capture/domain/bill_draft.dart';
import 'package:image/image.dart' as img;

/// Re-encodes a photo as a smaller JPEG; null when it cannot be decoded here.
typedef ImageShrinker = Future<Uint8List?> Function(Uint8List bytes);

const _photos = {'jpg', 'jpeg', 'png', 'heic', 'heif'};

/// Photos above this are re-encoded even when they would fit, so a phone
/// camera's 4 MB shot travels as a few hundred KB.
const shrinkAbove = 900000;

/// [file] ready for `POST /capture/files`, or null when it cannot fit under
/// [maxUploadBytes]. A PDF is never touched.
Future<LocalFile?> fitForUpload(
  LocalFile file, {
  ImageShrinker shrink = shrinkImage,
}) async {
  final photo = _photos.contains(file.extension);
  if (!photo || file.bytes.length <= shrinkAbove) return _withinCap(file);
  final shrunk = await shrink(file.bytes);
  if (shrunk == null || shrunk.length >= file.bytes.length) {
    return _withinCap(file);
  }
  return _withinCap(
    LocalFile(
      name: _jpegName(file.name),
      bytes: shrunk,
      mimeType: 'image/jpeg',
    ),
  );
}

LocalFile? _withinCap(LocalFile file) =>
    file.bytes.length <= maxUploadBytes ? file : null;

/// Only called for photos, whose names always carry an extension.
String _jpegName(String name) =>
    '${name.substring(0, name.lastIndexOf('.'))}.jpg';

/// Decoding a 12 MP photo takes long enough to drop frames, so it runs off
/// the UI isolate.
Future<Uint8List?> shrinkImage(Uint8List bytes) =>
    Isolate.run(() => shrinkImageNow(bytes));

/// The longest side capped at [maxSide], EXIF rotation applied, as JPEG.
/// HEIC has no pure Dart decoder, so it answers null.
Uint8List? shrinkImageNow(
  Uint8List bytes, {
  int maxSide = 2000,
  int quality = 80,
}) {
  final decoded = _decode(bytes);
  if (decoded == null) return null;
  final upright = img.bakeOrientation(decoded);
  if (max(upright.width, upright.height) <= maxSide) {
    return img.encodeJpg(upright, quality: quality);
  }
  final resized = upright.width >= upright.height
      ? img.copyResize(upright, width: maxSide)
      : img.copyResize(upright, height: maxSide);
  return img.encodeJpg(resized, quality: quality);
}

/// The decoders probe every format and throw on truncated input, which here
/// only means the original goes as it is.
img.Image? _decode(Uint8List bytes) {
  try {
    return img.decodeImage(bytes);
  } on Object {
    return null;
  }
}
