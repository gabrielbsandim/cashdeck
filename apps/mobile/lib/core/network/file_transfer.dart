import 'dart:convert';
import 'dart:typed_data';

import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:dio/dio.dart';

/// Uploads travel as JSON with a base64 payload, at most 5 MB decoded.
JsonMap uploadBody(LocalFile file) => {
  'fileName': file.name,
  'mimeType': file.contentType,
  'base64': base64Encode(file.bytes),
};

/// Downloads a raw file, naming it from `Content-Disposition` when the
/// server sends one.
Future<LocalFile> downloadFile(
  Dio dio,
  String path, {
  required String fallbackName,
}) async {
  final response = await dio.get<List<int>>(
    path,
    options: Options(responseType: ResponseType.bytes),
  );
  final bytes = response.data;
  if (bytes == null) throw const FormatException('Expected a file body');
  return LocalFile(
    name:
        fileNameOf(response.headers.value('content-disposition')) ??
        fallbackName,
    bytes: Uint8List.fromList(bytes),
    mimeType: response.headers.value(Headers.contentTypeHeader),
  );
}

String? fileNameOf(String? disposition) {
  if (disposition == null) return null;
  final match = RegExp('filename="?([^";]+)"?').firstMatch(disposition);
  return match?[1];
}
