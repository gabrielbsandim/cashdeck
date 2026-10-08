import 'package:cashdeck/core/files/local_file.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// The system share sheet, for text or one file.
abstract interface class FileSharer {
  Future<void> shareText(String text, {String? subject});

  Future<void> shareFile(LocalFile file, {String? subject});
}

final class FakeFileSharer implements FileSharer {
  final List<String> texts = [];
  final List<LocalFile> files = [];

  @override
  Future<void> shareText(String text, {String? subject}) async =>
      texts.add(text);

  @override
  Future<void> shareFile(LocalFile file, {String? subject}) async =>
      files.add(file);
}

typedef ShareCall = Future<ShareResult> Function(ShareParams params);

final class PlatformFileSharer implements FileSharer {
  new([ShareCall? share]) : _share = share ?? SharePlus.instance.share;

  final ShareCall _share;

  @override
  Future<void> shareText(String text, {String? subject}) =>
      _share(ShareParams(text: text, subject: subject));

  @override
  Future<void> shareFile(LocalFile file, {String? subject}) => _share(
    ShareParams(
      subject: subject,
      files: [
        XFile.fromData(file.bytes, name: file.name, mimeType: file.mimeType),
      ],
      fileNameOverrides: [file.name],
    ),
  );
}

final fileSharerProvider = Provider<FileSharer>((ref) => FakeFileSharer());
