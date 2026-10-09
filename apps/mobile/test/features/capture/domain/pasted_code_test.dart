import 'package:cashdeck/features/capture/domain/pasted_code.dart';
import 'package:cashdeck/features/capture/domain/pix_br_code.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';

void main() {
  const boletoDigits = '23793381286000000000300000000400198760000011990';

  test('a Pix copy-and-paste wins, whole or inside a sentence', () {
    final payload = testPixCode();

    expect(readPastedCode(payload), PastedPixCode(parsePixBrCode(payload)!));
    expect(
      readPastedCode('Pix copia e cola:\n$payload\nválido até hoje'),
      isA<PastedPixCode>().having((c) => c.code.payload, 'payload', payload),
    );
  });

  test('a boleto or guide line reads as digits, with or without dots', () {
    expect(readPastedCode(testBoletoLine), const PastedBarcode(boletoDigits));
    expect(readPastedCode(boletoDigits), const PastedBarcode(boletoDigits));
    final guide = readPastedCode(testGuideLine)! as PastedBarcode;
    expect(guide.digits, hasLength(48));
    expect(guide.isTaxGuide, isTrue);
    expect(const PastedBarcode(boletoDigits).isTaxGuide, isFalse);
    expect(readPastedCode('2' * 44), PastedBarcode('2' * 44));
    expect(
      readPastedCode('Linha digitável: $testBoletoLine. Vence amanhã.'),
      const PastedBarcode(boletoDigits),
    );
    expect(
      readPastedCode('Pedido 123 4567 8901 2345 6789 0123 4567 89'),
      isNull,
    );
  });

  test('reads the five kinds of Pix key, normalized', () {
    expect(
      readPastedCode('0A1B2C3D-4E5F-4a6b-8c7d-9e0f1a2b3c4d'),
      const PastedPixKey(
        PixKeyType.random,
        '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
      ),
    );
    expect(
      readPastedCode(' Contas@Exemplo.com '),
      const PastedPixKey(PixKeyType.email, 'contas@exemplo.com'),
    );
    expect(
      readPastedCode('111.444.777-35'),
      const PastedPixKey(PixKeyType.cpf, '11144477735'),
    );
    expect(
      readPastedCode('11.222.333/0001-81'),
      const PastedPixKey(PixKeyType.cnpj, '11222333000181'),
    );
    expect(
      readPastedCode('12.abc.345/01de-35'),
      const PastedPixKey(PixKeyType.cnpj, '12ABC34501DE35'),
    );
    expect(
      readPastedCode('(11) 98765-4321'),
      const PastedPixKey(PixKeyType.phone, '+5511987654321'),
    );
    expect(
      readPastedCode('+55 11 98765-4321'),
      const PastedPixKey(PixKeyType.phone, '+5511987654321'),
    );
    expect(
      readPastedCode('(11) 3456-7890'),
      const PastedPixKey(PixKeyType.phone, '+551134567890'),
    );
  });

  test('anything else reads as nothing', () {
    expect(readPastedCode('  '), isNull);
    expect(readPastedCode('olá, tudo bem?'), isNull);
    expect(readPastedCode('111.111.111-11'), isNull);
    expect(readPastedCode('11.222.333/0001-82'), isNull);
    expect(readPastedCode('+1 555 123 4567'), isNull);
    expect(readPastedCode('12345'), isNull);
    expect(readPastedCode('${'a' * 70}@exemplo.com'), isNull);
  });

  test('tax ids check their digits', () {
    expect(isValidCpf('11144477735'), isTrue);
    expect(isValidCpf('11144477736'), isFalse);
    expect(isValidCpf('11144477725'), isFalse);
    expect(isValidCpf('1114447773'), isFalse);
    expect(isValidCpf('00000000000'), isFalse);
    expect(isValidCnpj('11222333000181'), isTrue);
    expect(isValidCnpj('11222333000171'), isFalse);
    expect(isValidCnpj('00000000000000'), isFalse);
    expect(isValidCnpj('1122233300018'), isFalse);
  });

  test('codes compare by value', () {
    expect(const PastedBarcode('1').props, ['1']);
    expect(const PastedPixKey(PixKeyType.cpf, '1').props, hasLength(2));
  });
}
