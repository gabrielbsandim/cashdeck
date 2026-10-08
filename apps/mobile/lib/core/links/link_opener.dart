import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a link outside the app: the browser, a bank app or a sign-in page.
abstract interface class LinkOpener {
  Future<bool> open(Uri uri);
}

final class FakeLinkOpener implements LinkOpener {
  new({this.succeeds = true});

  final bool succeeds;
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return succeeds;
  }
}

typedef LaunchCall = Future<bool> Function(Uri uri, {LaunchMode mode});

final class PlatformLinkOpener implements LinkOpener {
  const new({this.launch = launchUrl});

  final LaunchCall launch;

  @override
  Future<bool> open(Uri uri) =>
      launch(uri, mode: LaunchMode.externalApplication);
}

final linkOpenerProvider = Provider<LinkOpener>((ref) => FakeLinkOpener());
