import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cashdeck/core/files/local_file.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Files other apps share into Cashdeck: a bill PDF from the bank or the
/// mail app, or a photo of one.
abstract interface class ShareIntake {
  /// What launched the app, then whatever arrives while it runs.
  Stream<LocalFile> files();
}

final class FakeShareIntake implements ShareIntake {
  final StreamController<LocalFile> _controller =
      StreamController<LocalFile>.broadcast();

  void receive(LocalFile file) => _controller.add(file);

  @override
  Stream<LocalFile> files() => _controller.stream;
}

const _accepted = {'pdf', 'jpg', 'jpeg', 'png', 'heic'};

/// Reads [shared] from the cache folder the plugin copies it to; anything
/// that is not a PDF or an image is ignored.
Future<LocalFile?> readSharedFile(
  SharedMediaFile shared, {
  Future<List<int>> Function(String path)? read,
}) async {
  final name = shared.path.split('/').last;
  final file = LocalFile(name: name, bytes: Uint8List(0));
  if (!_accepted.contains(file.extension)) return null;
  final bytes = await (read ?? (path) => File(path).readAsBytes())(shared.path);
  return LocalFile(
    name: name,
    bytes: Uint8List.fromList(bytes),
    mimeType: shared.mimeType,
  );
}

final class PlatformShareIntake implements ShareIntake {
  new([ReceiveSharingIntent? plugin])
    : _plugin = plugin ?? ReceiveSharingIntent.instance;

  final ReceiveSharingIntent _plugin;

  @override
  Stream<LocalFile> files() async* {
    final initial = await _plugin.getInitialMedia();
    yield* _read(initial);
    await _plugin.reset();
    await for (final batch in _plugin.getMediaStream()) {
      yield* _read(batch);
    }
  }

  Stream<LocalFile> _read(List<SharedMediaFile> batch) async* {
    for (final shared in batch) {
      final file = await readSharedFile(shared);
      if (file != null) yield file;
    }
  }
}

final shareIntakeProvider = Provider<ShareIntake>((ref) => FakeShareIntake());
