import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/household/application/household_use_cases.dart';
import 'package:cashdeck/features/household/domain/household.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/mocks.dart';

const _household = Household([
  HouseholdMember(name: 'Ana Exemplo', taxId: '11144477735'),
]);

void main() {
  late MockHouseholdRepository repository;

  setUpAll(() => registerFallbackValue(_household));

  setUp(() => repository = MockHouseholdRepository());

  test('each use case forwards to the repository', () async {
    when(repository.get).thenAnswer((_) async => const Ok(_household));
    when(() => repository.save(_household))
        .thenAnswer((_) async => const Ok(_household));

    expect(await LoadHousehold(repository).call(), const Ok(_household));
    expect(
      await SaveHousehold(repository).call(_household),
      const Ok(_household),
    );
  });

  test('a list that breaks a rule never reaches the server', () async {
    final result = await SaveHousehold(
      repository,
    ).call(const Household([HouseholdMember(name: '', taxId: '11144477735')]));

    expect(result, const Err<Household>(UnexpectedFailure()));
    verifyNever(() => repository.save(any()));
  });
}
