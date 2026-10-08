import 'package:cashdeck/core/files/local_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The system file picker, limited to extensions given without the dot. Null when
/// the user cancels.
abstract interface class FileChooser {
  Future<LocalFile?> choose(List<String> extensions);
}

final class FakeFileChooser implements FileChooser {
  new([this.next]);

  LocalFile? next;
  final List<List<String>> requests = [];

  @override
  Future<LocalFile?> choose(List<String> extensions) async {
    requests.add(extensions);
    return next;
  }
}

typedef PickPlatformFile = Future<PlatformFile?> Function({
  FileType type,
  List<String>? allowedExtensions,
});

final class PlatformFileChooser implements FileChooser {
  const new({this.pick = FilePicker.pickFile});

  final PickPlatformFile pick;

  @override
  Future<LocalFile?> choose(List<String> extensions) async {
    final file = await pick(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (file == null) return null;
    return LocalFile(name: file.name, bytes: await file.readAsBytes());
  }
}

final fileChooserProvider = Provider<FileChooser>((ref) => FakeFileChooser());
