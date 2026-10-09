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

  test('reads PDFs, images and text shared in, nothing else', () async {
    Future<List<int>> read(String path) async => [7, 8];

    final file = await readShared(
      SharedMediaFile(
        path: '/cache/boleto.pdf',
        type: SharedMediaType.file,
        mimeType: 'application/pdf',
      ),
      read: read,
    );
    final shared = (file! as SharedFile).file;
    expect(shared.name, 'boleto.pdf');
    expect(shared.bytes, [7, 8]);
    expect(
      await readShared(
        SharedMediaFile(path: '/cache/nota.txt', type: SharedMediaType.file),
        read: read,
      ),
      isNull,
    );
    expect(
      await readShared(
        SharedMediaFile(path: ' Pague: 000201 ', type: SharedMediaType.text),
      ),
      const SharedText('Pague: 000201'),
    );
    expect(
      await readShared(SharedMediaFile(path: '  ', type: SharedMediaType.text)),
      isNull,
    );
  });

  test('the platform intake yields the launch items, then new ones', () async {
    final folder = Directory.systemTemp.createTempSync('intake');
    addTearDown(() => folder.deleteSync(recursive: true));
    final shared = File('${folder.path}/fatura.pdf')..writeAsBytesSync([9]);
    final incoming = StreamController<List<SharedMediaFile>>();
    ReceiveSharingIntent.setMockValues(
      initialMedia: [
        SharedMediaFile(path: 'linha digitável', type: SharedMediaType.text),
        SharedMediaFile(path: '/nope/a.txt', type: SharedMediaType.file),
      ],
      mediaStream: incoming.stream,
    );
    final items = <SharedContent>[];
    final done = Completer<void>();
    PlatformShareIntake().received().listen(items.add, onDone: done.complete);
    incoming.add([
      SharedMediaFile(path: shared.path, type: SharedMediaType.file),
    ]);
    unawaited(incoming.close());
    await done.future;

    expect(items.first, const SharedText('linha digitável'));
    final file = (items.last as SharedFile).file;
    expect(file.name, 'fatura.pdf');
    expect(file.bytes, [9]);
  });

  test('the fake intake emits what it receives', () async {
    final intake = FakeShareIntake();
    final next = intake.received().take(2).toList();
    intake
      ..receive(pdf)
      ..receiveText('000201');

    expect(await next, [SharedFile(pdf), const SharedText('000201')]);
  });
}
