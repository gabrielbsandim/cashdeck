import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cashdeck/core/files/local_file.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Something another app shared into Cashdeck.
sealed class SharedContent extends Equatable {
  const new();
}

/// A bill PDF from the bank or the mail app, or a photo of one.
final class SharedFile extends SharedContent {
  const new(this.file);

  final LocalFile file;

  @override
  List<Object?> get props => [file];
}

/// Text such as a Pix copy-and-paste or a boleto line, often with a sentence
/// around it.
final class SharedText extends SharedContent {
  const new(this.text);

  final String text;

  @override
  List<Object?> get props => [text];
}

abstract interface class ShareIntake {
  /// What launched the app, then whatever arrives while it runs.
  Stream<SharedContent> received();
}

final class FakeShareIntake implements ShareIntake {
  final StreamController<SharedContent> _controller =
      StreamController<SharedContent>.broadcast();

  void receive(LocalFile file) => _controller.add(SharedFile(file));

  void receiveText(String text) => _controller.add(SharedText(text));

  @override
  Stream<SharedContent> received() => _controller.stream;
}

const _accepted = {'pdf', 'jpg', 'jpeg', 'png', 'heic'};

/// Reads [shared] from the cache folder the plugin copies it to; text comes
/// in the path itself. A file that is not a PDF or an image is ignored.
Future<SharedContent?> readShared(
  SharedMediaFile shared, {
  Future<List<int>> Function(String path)? read,
}) async {
  final text = shared.path.trim();
  if (shared.type == SharedMediaType.text) {
    return text.isEmpty ? null : SharedText(text);
  }
  final name = shared.path.split('/').last;
  final file = LocalFile(name: name, bytes: Uint8List(0));
  if (!_accepted.contains(file.extension)) return null;
  final bytes = await (read ?? (path) => File(path).readAsBytes())(shared.path);
  return SharedFile(
    LocalFile(
      name: name,
      bytes: Uint8List.fromList(bytes),
      mimeType: shared.mimeType,
    ),
  );
}

final class PlatformShareIntake implements ShareIntake {
  new([ReceiveSharingIntent? plugin])
    : _plugin = plugin ?? ReceiveSharingIntent.instance;

  final ReceiveSharingIntent _plugin;

  @override
  Stream<SharedContent> received() async* {
    final initial = await _plugin.getInitialMedia();
    yield* _read(initial);
    await _plugin.reset();
    await for (final batch in _plugin.getMediaStream()) {
      yield* _read(batch);
    }
  }

  Stream<SharedContent> _read(List<SharedMediaFile> batch) async* {
    for (final shared in batch) {
      final content = await readShared(shared);
      if (content != null) yield content;
    }
  }
}

final shareIntakeProvider = Provider<ShareIntake>((ref) => FakeShareIntake());
