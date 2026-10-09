import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// A file picked, shared in or produced on the device, held in memory.
final class LocalFile extends Equatable {
  const new({required this.name, required this.bytes, this.mimeType});

  final String name;
  final Uint8List bytes;
  final String? mimeType;

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  /// What the server is told the file is; the picker may not say.
  String get contentType =>
      mimeType ?? _types[extension] ?? 'application/octet-stream';

  static const _types = {
    'pdf': 'application/pdf',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'heic': 'image/heic',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'wav': 'audio/wav',
    'ogg': 'audio/ogg',
    'zip': 'application/zip',
    'pfx': 'application/x-pkcs12',
    'p12': 'application/x-pkcs12',
    'crt': 'application/x-x509-ca-cert',
    'cer': 'application/x-x509-ca-cert',
    'pem': 'application/x-pem-file',
    'key': 'application/x-pem-file',
  };

  @override
  List<Object?> get props => [name, bytes, mimeType];
}
