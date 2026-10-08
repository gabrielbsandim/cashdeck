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

  @override
  List<Object?> get props => [name, bytes, mimeType];
}
