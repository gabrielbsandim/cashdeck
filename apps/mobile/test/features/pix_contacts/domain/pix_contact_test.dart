import 'package:cashdeck/features/pix_contacts/domain/pix_contact.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';

const _cpf = '52998224725';
const _cnpj = '11222333000181';

void main() {
  test('a contact shows initials and is found by name or handle', () {
    final contact = testContact(name: 'João da Silva', handle: 'joao.silva');

    expect(contact.initials, 'JS');
    expect(testContact(name: 'Marina').initials, 'M');
    expect(testContact(name: '   ').initials, '?');
    expect(contact.mention, '@joao.silva');
    expect(contact.matches('joao'), isTrue);
    expect(contact.matches('SILVA'), isTrue);
    expect(contact.matches('@joao.s'), isTrue);
    expect(contact.matches(''), isTrue);
    expect(contact.matches('ana'), isFalse);
    expect(contact.props, hasLength(8));
  });

  test('folds accents and case, and makes a handle from a name', () {
    expect(foldText('Ação Çá Ñ'), 'acao ca n');
    expect(handleFromName('João da Silva'), 'joao.silva');
    expect(handleFromName('Marina'), 'marina');
    expect(handleFromName('  !!  '), '');
    expect(handleFromName('${'a' * 20} ${'b' * 20}'), hasLength(30));
    expect(isValidHandle('joao.silva'), isTrue);
    expect(isValidHandle('a'), isFalse);
    expect(isValidHandle('.joao'), isFalse);
    expect(isValidHandle('Joao'), isFalse);
  });

  test('each key type belongs to one choice of the form', () {
    expect(kindOf(PixKeyType.cpf), PixKeyKind.taxId);
    expect(kindOf(PixKeyType.cnpj), PixKeyKind.taxId);
    expect(kindOf(PixKeyType.phone), PixKeyKind.phone);
    expect(kindOf(PixKeyType.email), PixKeyKind.email);
    expect(kindOf(PixKeyType.evp), PixKeyKind.evp);
  });

  test('normalizes a key as the server stores it', () {
    expect(normalizePixKey(PixKeyKind.taxId, '529.982.247-25'), (
      _cpf,
      PixKeyType.cpf,
    ));
    expect(normalizePixKey(PixKeyKind.taxId, '11.222.333/0001-81'), (
      _cnpj,
      PixKeyType.cnpj,
    ));
    expect(normalizePixKey(PixKeyKind.taxId, '123'), isNull);
    expect(normalizePixKey(PixKeyKind.phone, '(41) 99999-0001'), (
      '+5541999990001',
      PixKeyType.phone,
    ));
    expect(normalizePixKey(PixKeyKind.phone, '+55 41 99999-0001'), (
      '+5541999990001',
      PixKeyType.phone,
    ));
    expect(normalizePixKey(PixKeyKind.phone, '999'), isNull);
    expect(normalizePixKey(PixKeyKind.email, ' Ana@Exemplo.com '), (
      'ana@exemplo.com',
      PixKeyType.email,
    ));
    expect(normalizePixKey(PixKeyKind.email, 'ana'), isNull);
    expect(
      normalizePixKey(PixKeyKind.evp, '123E4567-E89B-42D3-A456-426614174000'),
      ('123e4567-e89b-42d3-a456-426614174000', PixKeyType.evp),
    );
    expect(normalizePixKey(PixKeyKind.evp, 'abc'), isNull);
  });

  test('masks a key enough to recognize it', () {
    expect(maskPixKey(PixKeyType.cpf, _cpf), '***.982.247-**');
    expect(maskPixKey(PixKeyType.cpf, '123'), '123');
    expect(maskPixKey(PixKeyType.cnpj, _cnpj), '11.222.333/0001-81');
    expect(maskPixKey(PixKeyType.phone, '+5541999990001'), '(**) *****-0001');
    expect(
      maskPixKey(PixKeyType.email, 'ana@exemplo.com'),
      'an***@exemplo.com',
    );
    expect(maskPixKey(PixKeyType.email, 'al@exemplo.com'), 'a***@exemplo.com');
    expect(maskPixKey(PixKeyType.email, '@x'), '@x');
    expect(
      maskPixKey(PixKeyType.evp, '123e4567-e89b-42d3-a456-426614174000'),
      '123e4567…',
    );
  });

  test('a draft names the first rule it breaks', () {
    PixContactDraft draft({
      String name = 'Ana',
      String handle = 'ana',
      String key = 'ana@exemplo.com',
    }) => PixContactDraft(
      name: name,
      handle: handle,
      keyKind: PixKeyKind.email,
      pixKey: key,
    );

    expect(draft().problem, isNull);
    expect(draft().normalizedKey, ('ana@exemplo.com', PixKeyType.email));
    expect(draft(name: ' ').problem, ContactProblem.nameMissing);
    expect(draft(key: 'x').problem, ContactProblem.keyInvalid);
    expect(draft(handle: 'A').problem, ContactProblem.handleInvalid);
    expect(draft().props, hasLength(4));
  });
}
