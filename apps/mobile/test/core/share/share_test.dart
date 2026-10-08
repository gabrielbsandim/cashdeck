import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/links/link_opener.dart';
import 'package:cashdeck/core/share/file_sharer.dart';
import 'package:cashdeck/core/share/share_intake.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  final pdf = LocalFile(
    name: 'conta.pdf',
    bytes: Uint8List.fromList([1]),
    mimeType: 'application/pdf',
  );

  test('the platform sharer hands text and files to the sheet', () async {
    final sent = <ShareParams>[];
    final sharer = PlatformFileSharer((params) async {
      sent.add(params);
      return const ShareResult('ok', ShareResultStatus.success);
    });

    await sharer.shareText('oi', subject: 'assunto');
    await sharer.shareFile(pdf);

    expect(sent.first.text, 'oi');
    expect(sent.first.subject, 'assunto');
    expect(sent.last.fileNameOverrides, ['conta.pdf']);
    expect(sent.last.files!.single.mimeType, 'application/pdf');
  });

  test('the fake sharer records what was shared', () async {
    final sharer = FakeFileSharer();
    await sharer.shareText('oi');
    await sharer.shareFile(pdf);

    expect(sharer.texts, ['oi']);
    expect(sharer.files, [pdf]);
  });

  test('links open outside the app', () async {
    final opened = <(Uri, LaunchMode)>[];
    final opener = PlatformLinkOpener(
      launch: (uri, {mode = LaunchMode.platformDefault}) async {
        opened.add((uri, mode));
        return true;
      },
    );

    expect(await opener.open(Uri.parse('https://x.test')), isTrue);
    expect(opened.single.$2, LaunchMode.externalApplication);
    expect(await FakeLinkOpener(succeeds: false).open(Uri()), isFalse);
  });

  test('reads only PDFs and images shared in', () async {
    Future<List<int>> read(String path) async => [7, 8];

    final file = await readSharedFile(
      SharedMediaFile(
        path: '/cache/boleto.pdf',
        type: SharedMediaType.file,
        mimeType: 'application/pdf',
      ),
      read: read,
    );
    expect(file?.name, 'boleto.pdf');
    expect(file?.bytes, [7, 8]);
    expect(
      await readSharedFile(
        SharedMediaFile(path: '/cache/nota.txt', type: SharedMediaType.text),
        read: read,
      ),
      isNull,
    );
  });

  test('the platform intake yields the launch files, then new ones', () async {
    final folder = Directory.systemTemp.createTempSync('intake');
    addTearDown(() => folder.deleteSync(recursive: true));
    final shared = File('${folder.path}/fatura.pdf')..writeAsBytesSync([9]);
    final incoming = StreamController<List<SharedMediaFile>>();
    ReceiveSharingIntent.setMockValues(
      initialMedia: [
        SharedMediaFile(path: '/nope/a.txt', type: SharedMediaType.text),
      ],
      mediaStream: incoming.stream,
    );
    final files = <LocalFile>[];
    final done = Completer<void>();
    PlatformShareIntake().files().listen(files.add, onDone: done.complete);
    incoming.add([
      SharedMediaFile(path: shared.path, type: SharedMediaType.file),
    ]);
    unawaited(incoming.close());
    await done.future;

    expect(files.single.name, 'fatura.pdf');
    expect(files.single.bytes, [9]);
  });

  test('the fake intake emits what it receives', () async {
    final intake = FakeShareIntake();
    final next = intake.files().first;
    intake.receive(pdf);

    expect(await next, pdf);
  });
}
