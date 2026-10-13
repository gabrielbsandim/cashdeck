import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/household/data/api_household_repository.dart';
import 'package:cashdeck/features/household/data/fake_household_repository.dart';
import 'package:cashdeck/features/household/data/household_dtos.dart';
import 'package:cashdeck/features/household/domain/household.dart';
import 'package:cashdeck/features/household/household_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/stub_http_adapter.dart';

const _member = HouseholdMember(name: 'Ana Exemplo', taxId: '11144477735');
const _household = Household([_member]);
const _json = {
  'members': [
    {'name': 'Ana Exemplo', 'taxId': '11144477735'},
  ],
};

void main() {
  group('dtos', () {
    test('read and write the members', () {
      expect(householdFromJson(_json), _household);
      expect(householdFromJson({'members': <Object>[]}), const Household([]));
      expect(householdToJson(_household), _json);
    });

    test('a wrong shape is a format error', () {
      expect(
        () => householdFromJson({
          'members': [
            {'name': 'Ana Exemplo'},
          ],
        }),
        throwsFormatException,
      );
    });
  });

  group('api', () {
    test('reads the household and puts the whole list', () async {
      final dio = stubDio((options) {
        final key = '${options.method} ${options.path}';
        return switch (key) {
          'GET /api/v1/household' => const StubResponse(200, {'data': _json}),
          'PUT /api/v1/household' => const StubResponse(200, {'data': _json}),
          _ => const StubResponse(404),
        };
      });
      final repository = ApiHouseholdRepository(dio);

      expect(await repository.get(), const Ok(_household));
      expect(await repository.save(_household), const Ok(_household));

      final put = adapterOf(dio).requests.last;
      expect(put.method, 'PUT');
      expect(put.data, _json);
    });

    test('a refused CPF shows the server message', () async {
      final dio = stubDio(
        (_) => const StubResponse(422, {
          'error': {
            'code': 'VALIDATION_ERROR',
            'message': 'A household member needs a CPF.',
          },
        }),
      );

      expect(
        await ApiHouseholdRepository(dio).save(_household),
        const Err<Household>(
          ValidationFailure('A household member needs a CPF.'),
        ),
      );
    });

    test('an unexpected body is an unexpected failure', () async {
      final dio = stubDio((_) => const StubResponse(200, {'data': 'x'}));

      expect(
        await ApiHouseholdRepository(dio).get(),
        const Err<Household>(UnexpectedFailure()),
      );
    });
  });

  group('fake', () {
    test('starts with a fictional member and keeps what is saved', () async {
      final fake = FakeHouseholdRepository(latency: Duration.zero);

      expect(await fake.get(), const Ok(_household));
      expect(await fake.save(const Household([])), const Ok(Household([])));
      expect(await fake.get(), const Ok(Household([])));
    });

    test('refuses a list the server would refuse', () async {
      final fake = FakeHouseholdRepository(latency: Duration.zero);

      final result = await fake.save(
        const Household([HouseholdMember(name: 'Ana', taxId: '11144477734')]),
      );

      expect(result, isA<Err<Household>>());
      expect(await fake.get(), const Ok(_household));
    });
  });

  test('the provider picks fake or api by the backend', () {
    final fake = ProviderContainer();
    addTearDown(fake.dispose);
    final api = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(backend: Backend.api, apiBaseUrl: 'https://api.test'),
        ),
      ],
    );
    addTearDown(api.dispose);

    expect(
      fake.read(householdRepositoryProvider),
      isA<FakeHouseholdRepository>(),
    );
    expect(
      api.read(householdRepositoryProvider),
      isA<ApiHouseholdRepository>(),
    );
    expect(fake.read(loadHouseholdProvider), isNotNull);
    expect(fake.read(saveHouseholdProvider), isNotNull);
  });
}
