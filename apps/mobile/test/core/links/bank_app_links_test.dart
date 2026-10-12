import 'package:cashdeck/core/links/bank_app_links.dart';
import 'package:cashdeck/core/links/link_opener.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  test(
    'a rail names the bank app by its plain name, with and without "banco"',
    () {
      expect(bankAppLinks('Pix via API · Banco Aurora').map((uri) => '$uri'), [
        'bancoaurora://',
        'aurora://',
      ]);
      expect(bankAppLinks('Banco Atlântico').map((uri) => '$uri'), [
        'bancoatlantico://',
        'atlantico://',
      ]);
      expect(bankAppLinks('Cooperativa Sul').map((uri) => '$uri'), [
        'cooperativasul://',
      ]);
      expect(bankAppLinks(' · '), isEmpty);
    },
  );

  test('opens the first link the phone answers and stops there', () async {
    final opener = _Picky({'aurora://'});

    expect(await openFirst(opener, bankAppLinks('Banco Aurora')), isTrue);
    expect(opener.tried, ['bancoaurora://', 'aurora://']);
    expect(await openFirst(opener, const []), isFalse);
    expect(await openFirst(_Picky({}), bankAppLinks('Banco Aurora')), isFalse);
  });

  test('a link nothing handles reads as not opened', () async {
    final opener = PlatformLinkOpener(
      launch: (uri, {mode = LaunchMode.platformDefault}) async =>
          throw PlatformException(code: 'ACTIVITY_NOT_FOUND'),
    );

    expect(await opener.open(Uri.parse('aurora://')), isFalse);
  });
}

final class _Picky implements LinkOpener {
  new(this.answers);

  final Set<String> answers;
  final List<String> tried = [];

  @override
  Future<bool> open(Uri uri) async {
    tried.add('$uri');
    return answers.contains('$uri');
  }
}
