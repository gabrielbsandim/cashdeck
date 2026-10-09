import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/scan/code_scanner.dart';
import 'package:cashdeck/features/bills/data/fake_bills_repository.dart';
import 'package:cashdeck/features/capture/domain/pix_br_code.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';

void main() {
  test('the checksum is CRC16/CCITT-FALSE', () {
    expect(crc16Ccitt('123456789'), '29B1');
    expect(withPixCrc('000201'), '0002016304${crc16Ccitt('0002016304')}');
  });

  test('reads a static code: recipient, city, amount and key', () {
    final payload = testPixCode();

    expect(
      parsePixBrCode(' $payload '),
      PixBrCode(
        payload: payload,
        merchantName: 'LOJA EXEMPLO',
        merchantCity: 'CURITIBA',
        amount: const Money(11990),
        pixKey: 'loja@exemplo.com',
      ),
    );
    expect(parsePixBrCode(payload.toLowerCase()), isNull);
  });

  test('the amount is optional and read in cents', () {
    expect(parsePixBrCode(testPixCode(amount: null))?.amount, isNull);
    expect(parsePixBrCode(testPixCode(amount: '0.00'))?.amount, isNull);
    expect(
      parsePixBrCode(testPixCode(amount: '10'))?.amount,
      const Money(1000),
    );
    expect(
      parsePixBrCode(testPixCode(amount: '10.5'))?.amount,
      const Money(1050),
    );
    expect(parsePixBrCode(testPixCode(amount: '1,00'))?.amount, isNull);
  });

  test('reads the sample codes the fakes use', () {
    expect(parsePixBrCode(sampleScannedCode)?.merchantName, 'ENERGIA LUMINA');
    expect(
      parsePixBrCode(FakeBillsRepository.bolepixCode)?.amount,
      const Money(11990),
    );
  });

  test('a dynamic code carries a URL; other templates are skipped', () {
    final body =
        tlv('00', '01') +
        tlv('27', tlv('00', 'com.outro.arranjo')) +
        tlv('28', 'x') +
        tlv('26', tlv('00', 'BR.GOV.BCB.PIX') + tlv('25', 'pix.exemplo/qr/1')) +
        tlv('59', ' ') +
        tlv('60', 'RECIFE');
    final code = parsePixBrCode(withPixCrc(body));

    expect(code?.url, 'pix.exemplo/qr/1');
    expect(code?.pixKey, isNull);
    expect(code?.merchantName, isNull);
    expect(code?.props, hasLength(6));
  });

  test('a code without a Pix template still parses its fields', () {
    final code = parsePixBrCode(withPixCrc(tlv('00', '01') + tlv('59', 'A')));

    expect(code?.merchantName, 'A');
    expect(code?.pixKey, isNull);
  });

  test('a wrong header, checksum or field layout is not a code', () {
    final payload = testPixCode();
    final flipped =
        '${payload.substring(0, payload.length - 1)}'
        '${payload.endsWith('0') ? '1' : '0'}';

    expect(parsePixBrCode('https://exemplo.com'), isNull);
    expect(parsePixBrCode('000201'), isNull);
    expect(parsePixBrCode(flipped), isNull);
    expect(parsePixBrCode('${payload.substring(0, 20)}6305ABCD'), isNull);
    expect(parsePixBrCode(withPixCrc('00020126XXabc')), isNull);
    expect(parsePixBrCode(withPixCrc('0002015')), isNull);
    expect(parsePixBrCode(withPixCrc('0002019907ab')), isNull);
  });

  test('finds a code inside a longer message', () {
    final payload = testPixCode();

    expect(
      findPixBrCode('Pague com Pix: $payload Obrigado!')?.payload,
      payload,
    );
    expect(
      findPixBrCode('000201 rascunho 6304 e depois $payload')?.payload,
      payload,
    );
    expect(findPixBrCode('termina em 0002016304AB'), isNull);
    expect(findPixBrCode('nada aqui'), isNull);
  });
}
