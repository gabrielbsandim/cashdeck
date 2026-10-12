import 'package:flutter/services.dart';
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

  /// False when nothing on the phone handles [uri]; Android reports that by
  /// throwing.
  @override
  Future<bool> open(Uri uri) async {
    try {
      return await launch(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return false;
    }
  }
}

/// Opens the first of [links] the phone can handle; false when none could.
Future<bool> openFirst(LinkOpener opener, Iterable<Uri> links) async {
  for (final link in links) {
    if (await opener.open(link)) return true;
  }
  return false;
}

final linkOpenerProvider = Provider<LinkOpener>((ref) => FakeLinkOpener());
