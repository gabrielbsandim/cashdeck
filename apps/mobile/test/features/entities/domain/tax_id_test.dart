import 'package:cashdeck/features/entities/domain/entity_profile.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/domain/tax_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const personal = EntityKind.personal;
  const company = EntityKind.company;

  test('accepts the check digits of a CPF and a CNPJ', () {
    expect(TaxIds.isValid(personal, '529.982.247-25'), isTrue);
    expect(TaxIds.isValid(company, '11.222.333/0001-81'), isTrue);
    expect(TaxIds.isValid(company, '11444777000161'), isTrue);
  });

  test(
    'rejects a wrong digit, a short id, a repeated one and the wrong kind',
    () {
      expect(TaxIds.isValid(personal, '52998224724'), isFalse);
      expect(TaxIds.isValid(personal, '5299822472'), isFalse);
      expect(TaxIds.isValid(personal, '111.111.111-11'), isFalse);
      expect(TaxIds.isValid(personal, '11222333000181'), isFalse);
      expect(TaxIds.isValid(company, '11222333000182'), isFalse);
      expect(TaxIds.isValid(company, '00000000000000'), isFalse);
      expect(TaxIds.isValid(company, '52998224725'), isFalse);
      expect(TaxIds.isValidCnpj('ABCDEFGHIJKLMN'), isFalse);
      expect(TaxIds.isValidCpf('0000000000A'), isFalse);
    },
  );

  test('cleans and masks what was typed so far', () {
    expect(TaxIds.clean(personal, '529.982.247-25 99'), '52998224725');
    expect(TaxIds.clean(company, '1a.222'), '1A222');
    expect(TaxIds.format(personal, '5299'), '529.9');
    expect(TaxIds.format(personal, '52998224725'), '529.982.247-25');
    expect(TaxIds.format(company, '11222333000181'), '11.222.333/0001-81');
    expect(TaxIds.format(company, ''), '');
    expect(TaxIds.lengthOf(company), 14);
  });

  test('a profile copies with new values and compares by value', () {
    const profile = EntityProfile(
      id: 'company',
      kind: company,
      name: 'Empresa',
      taxId: '11222333000181',
      taxRegime: TaxRegime.simplesNacional,
    );

    final edited = profile.copyWith(
      name: 'Outra',
      taxId: '11444777000161',
      taxRegime: TaxRegime.lucroReal,
    );

    expect(edited.name, 'Outra');
    expect(edited.taxId, '11444777000161');
    expect(edited.taxRegime, TaxRegime.lucroReal);
    expect(profile.copyWith(), profile);
    expect(profile.props, hasLength(5));
  });
}
