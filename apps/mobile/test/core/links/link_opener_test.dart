import 'package:cashdeck/core/links/link_opener.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  test('a link opens outside the app', () async {
    final launched = <Uri>[];
    final opener = PlatformLinkOpener(
      launch: (uri, {mode = LaunchMode.platformDefault}) async {
        expect(mode, LaunchMode.externalApplication);
        launched.add(uri);
        return true;
      },
    );

    expect(await opener.open(Uri.parse('bankapp://approvals')), isTrue);
    expect(launched, [Uri.parse('bankapp://approvals')]);
  });

  test('a link nothing handles reads as not opened', () async {
    final opener = PlatformLinkOpener(
      launch: (uri, {mode = LaunchMode.platformDefault}) async =>
          throw PlatformException(code: 'ACTIVITY_NOT_FOUND'),
    );

    expect(await opener.open(Uri.parse('bankapp://')), isFalse);
  });
}
