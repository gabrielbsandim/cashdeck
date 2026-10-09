import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/data/api_entity_profile_repository.dart';
import 'package:cashdeck/features/entities/data/fake_entity_profile_repository.dart';
import 'package:cashdeck/features/entities/domain/entity_profile.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/entities_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/stub_http_adapter.dart';

T _ok<T>(Result<T> result) => (result as Ok<T>).value;

const _company = EntityProfile(
  id: 'company',
  kind: EntityKind.company,
  name: 'Empresa',
  taxId: '11222333000181',
  taxRegime: TaxRegime.simplesNacional,
);

const _personal = EntityProfile(
  id: 'personal',
  kind: EntityKind.personal,
  name: 'Pessoal',
  taxId: '52998224725',
);

final JsonMap _companyJson = {
  'id': 'company',
  'kind': 'PJ',
  'name': 'Empresa',
  'taxId': '11222333000181',
  'taxRegime': 'SIMPLES_NACIONAL',
};

void main() {
  group('fake', () {
    test('lists the person first and saves a clean tax id', () async {
      final repository = FakeEntityProfileRepository(latency: Duration.zero);

      expect(_ok(await repository.list()).map((profile) => profile.name), [
        'Conta pessoal',
        'Empresa Exemplo Ltda',
      ]);

      final saved = _ok(
        await repository.update(
          _company.copyWith(
            name: '  Empresa Nova  ',
            taxId: '11.444.777/0001-61',
            taxRegime: TaxRegime.lucroPresumido,
          ),
        ),
      );

      expect(saved.name, 'Empresa Nova');
      expect(saved.taxId, '11444777000161');
      expect(saved.taxRegime, TaxRegime.lucroPresumido);
      expect(_ok(await repository.list()).last, saved);
    });

    test('answers like the server for a bad id or an unknown entity', () async {
      final repository = FakeEntityProfileRepository(latency: Duration.zero);

      expect(
        await repository.update(_personal.copyWith(taxId: '52998224724')),
        const Err<EntityProfile>(
          ValidationFailure(FakeEntityProfileRepository.invalidTaxIdMessage),
        ),
      );
      expect(
        await repository.update(
          const EntityProfile(
            id: 'other',
            kind: EntityKind.personal,
            name: 'Outro',
            taxId: '52998224725',
          ),
        ),
        const Err<EntityProfile>(NotFoundFailure()),
      );
    });
  });

  group('api', () {
    test('reads both entities and patches one', () async {
      final dio = stubDio((options) {
        if (options.method == 'GET') {
          return StubResponse(200, {
            'data': [
              {
                'id': 'personal',
                'kind': 'PF',
                'name': 'Pessoal',
                'taxId': '52998224725',
                'taxRegime': null,
              },
              _companyJson,
            ],
          });
        }
        return StubResponse(200, {
          'data': {..._companyJson, 'name': 'Empresa Nova', 'taxRegime': 'MEI'},
        });
      });
      final repository = ApiEntityProfileRepository(dio);

      expect(_ok(await repository.list()), [_personal, _company]);
      final saved = _ok(
        await repository.update(
          _company.copyWith(name: 'Empresa Nova', taxRegime: TaxRegime.mei),
        ),
      );

      expect(saved.name, 'Empresa Nova');
      expect(saved.taxRegime, TaxRegime.mei);
      final patch = adapterOf(dio).requests.last;
      expect('${patch.method} ${patch.path}', 'PATCH /api/v1/entities/company');
      expect(patch.data, {
        'name': 'Empresa Nova',
        'taxId': '11222333000181',
        'taxRegime': 'MEI',
      });
    });

    test('a person sends no regime and every regime maps', () async {
      final regimes = ['LUCRO_PRESUMIDO', 'LUCRO_REAL'];
      final dio = stubDio(
        (options) => StubResponse(200, {
          'data': {..._companyJson, 'taxRegime': regimes.removeAt(0)},
        }),
      );
      final repository = ApiEntityProfileRepository(dio);

      final first = _ok(await repository.update(_personal));
      final second = _ok(await repository.update(_personal));

      expect(adapterOf(dio).requests.first.data, {
        'name': 'Pessoal',
        'taxId': '52998224725',
      });
      expect(first.taxRegime, TaxRegime.lucroPresumido);
      expect(second.taxRegime, TaxRegime.lucroReal);
    });

    test('shows the server message of a 422', () async {
      final repository = ApiEntityProfileRepository(
        stubDio(
          (_) => const StubResponse(422, {
            'error': {'code': 'VALIDATION', 'message': 'Tax id is not valid.'},
          }),
        ),
      );

      expect(
        await repository.update(_personal),
        const Err<EntityProfile>(ValidationFailure('Tax id is not valid.')),
      );
    });

    test('an unknown regime is a format error', () async {
      final repository = ApiEntityProfileRepository(
        stubDio(
          (_) => StubResponse(200, {
            'data': [
              {..._companyJson, 'taxRegime': 'OTHER'},
            ],
          }),
        ),
      );

      expect(
        await repository.list(),
        const Err<List<EntityProfile>>(UnexpectedFailure()),
      );
    });
  });

  test('the backend picks the repository', () {
    final fake = ProviderContainer();
    final api = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(backend: Backend.api, apiBaseUrl: 'https://x.test'),
        ),
      ],
    );
    addTearDown(fake.dispose);
    addTearDown(api.dispose);

    expect(
      fake.read(entityProfileRepositoryProvider),
      isA<FakeEntityProfileRepository>(),
    );
    expect(
      api.read(entityProfileRepositoryProvider),
      isA<ApiEntityProfileRepository>(),
    );
  });
}
