import 'package:cashdeck/features/household/domain/household.dart';
import 'package:flutter_test/flutter_test.dart';

const _cpf = '11144477735';
const _member = HouseholdMember(name: 'Ana Exemplo', taxId: _cpf);

void main() {
  test('a member shows only the middle of the CPF', () {
    expect(_member.maskedTaxId, '***.444.777-**');
    expect(_member, const HouseholdMember(name: 'Ana Exemplo', taxId: _cpf));
  });

  test('names the first rule a new member breaks', () {
    const empty = Household([]);
    const one = Household([_member]);
    final full = Household(List.filled(Household.maxMembers, _member));

    expect(empty.problemOf('Bia Exemplo', '111.444.777-35'), isNull);
    expect(full.isFull, isTrue);
    expect(full.problemOf('Bia', '111.444.777-35'), MemberProblem.full);
    expect(empty.problemOf('  ', '111.444.777-35'), MemberProblem.nameMissing);
    expect(
      empty.problemOf('a' * (Household.maxNameLength + 1), _cpf),
      MemberProblem.nameTooLong,
    );
    expect(empty.problemOf('Bia', '111.444.777-34'), MemberProblem.cpfInvalid);
    expect(one.problemOf('Bia', '111.444.777-35'), MemberProblem.cpfTaken);
  });

  test('a list is valid only within the server rules', () {
    expect(const Household([]).isValid, isTrue);
    expect(const Household([_member]).isValid, isTrue);
    expect(const Household([_member, _member]).isValid, isFalse);
    expect(Household(List.filled(11, _member)).isValid, isFalse);
    expect(
      const Household([HouseholdMember(name: ' ', taxId: _cpf)]).isValid,
      isFalse,
    );
    expect(
      Household([
        HouseholdMember(name: 'a' * (Household.maxNameLength + 1), taxId: _cpf),
      ]).isValid,
      isFalse,
    );
    expect(
      const Household([HouseholdMember(name: 'Ana', taxId: '11144477734')])
          .isValid,
      isFalse,
    );
  });

  test('adds a member cleaned and removes one by CPF', () {
    final added = const Household([]).adding(' Ana Exemplo ', '111.444.777-35');

    expect(added, const Household([_member]));
    expect(added.includes(_cpf), isTrue);
    expect(added.removing(_member), const Household([]));
  });
}
