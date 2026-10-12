import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/assets/assets_providers.dart';
import 'package:cashdeck/features/assets/data/api_assets_repository.dart';
import 'package:cashdeck/features/assets/data/asset_dtos.dart';
import 'package:cashdeck/features/assets/data/fake_assets_repository.dart';
import 'package:cashdeck/features/assets/domain/asset.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';
import '../../../support/stub_http_adapter.dart';
import '../asset_builders.dart';

T _ok<T>(Result<T> result) => (result as Ok<T>).value;

Map<String, Object?> _money(int cents) => {'cents': cents, 'currency': 'BRL'};

void main() {
  group('dtos', () {
    test('read an asset with its FIPE code and loan', () {
      expect(assetFromJson(assetJson()), testAsset);

      final plain = assetFromJson(
        assetJson(percent: null, fipe: null, loan: null, soldOn: '2026-10-01'),
      );
      expect(plain.changePercent, isNull);
      expect(plain.fipe, isNull);
      expect(plain.loan, isNull);
      expect(plain.sold, isTrue);
      expect(plain.soldOn, const CalendarDate(2026, 10, 1));
    });

    test('a percent that is not a number fails the read', () {
      expect(
        () => assetFromJson(assetJson(percent: 'high')),
        throwsFormatException,
      );
    });

    test('send a value by hand, or only the FIPE code for a vehicle', () {
      const day = CalendarDate(2025, 6, 10);
      expect(
        assetDraftToJson(
          const AssetDraft(
            kind: AssetKind.property,
            name: ' Apartamento ',
            acquiredOn: day,
            value: Money(50_000_000),
            fipe: testFipe,
            loanId: 'loan-1',
          ),
        ),
        {
          'entity': 'PF',
          'kind': 'PROPERTY',
          'acquiredOn': '2025-06-10',
          'loanId': 'loan-1',
          'name': 'Apartamento',
          'value': 50_000_000,
        },
      );
      expect(
        assetDraftToJson(
          const AssetDraft(
            kind: AssetKind.vehicle,
            acquiredOn: day,
            fipe: FipeVehicle(
              type: VehicleType.motorcycle,
              code: '811084-3',
              modelYear: 2019,
            ),
          ),
        ),
        {
          'entity': 'PF',
          'kind': 'VEHICLE',
          'acquiredOn': '2025-06-10',
          'loanId': null,
          'fipe': {'type': 'MOTORCYCLE', 'code': '811084-3', 'modelYear': 2019},
        },
      );
    });
  });

  group('api', () {
    test('lists, creates, revalues, marks sold and deletes', () async {
      final dio = stubDio(
        (options) => switch ((options.method, options.path)) {
          ('GET', '/api/v1/assets') => StubResponse(200, {
            'data': {
              'items': [assetJson()],
              'value': _money(9_000_000),
              'loanDebt': _money(3_000_000),
              'equity': _money(6_000_000),
            },
          }),
          ('POST', '/api/v1/assets') => StubResponse(201, {
            'data': assetJson(id: 'asset-2'),
          }),
          ('PATCH', '/api/v1/assets/asset-1') => StubResponse(200, {
            'data': assetJson(),
          }),
          ('DELETE', '/api/v1/assets/asset-1') => const StubResponse(200, {
            'data': {'id': 'asset-1'},
          }),
          _ => const StubResponse(404),
        },
      );
      final repository = ApiAssetsRepository(dio);

      final summary = _ok(await repository.list());
      expect(summary.items, [testAsset]);
      expect(summary.loanDebt, const Money(3_000_000));
      expect(
        _ok(
          await repository.create(
            const AssetDraft(
              kind: AssetKind.vehicle,
              acquiredOn: CalendarDate(2024, 5, 20),
              fipe: testFipe,
            ),
          ),
        ).id,
        'asset-2',
      );
      expect(
        _ok(await repository.revalue('asset-1', const Money(8_000_000))),
        testAsset,
      );
      expect(
        _ok(
          await repository.markSold(
            'asset-1',
            const CalendarDate(2026, 10, 12),
          ),
        ),
        testAsset,
      );
      expect(await repository.delete('asset-1'), isA<Ok<void>>());

      final requests = adapterOf(dio).requests;
      expect((requests[1].data as Map)['fipe'], {
        'type': 'CAR',
        'code': '001234-5',
        'modelYear': 2022,
      });
      expect(requests[2].data, {'value': 8_000_000});
      expect(requests[3].data, {'soldOn': '2026-10-12'});
    });

    test('a code the table does not know comes back as not found', () async {
      final dio = stubDio(
        (_) => const StubResponse(404, {
          'error': {'code': 'NOT_FOUND', 'message': 'FIPE vehicle not found'},
        }),
      );
      final result = await ApiAssetsRepository(dio).create(
        const AssetDraft(
          kind: AssetKind.vehicle,
          acquiredOn: CalendarDate(2024, 5, 20),
          fipe: testFipe,
        ),
      );
      expect((result as Err).failure, isA<NotFoundFailure>());
    });
  });

  group('fake', () {
    FakeAssetsRepository fake() =>
        FakeAssetsRepository(FixedClock(testNow), latency: Duration.zero);

    test('seeds a home with its loan and a car, then adds goods', () async {
      final repository = fake();
      final seeded = _ok(await repository.list());
      expect(seeded.items.map((asset) => asset.kind), [
        AssetKind.property,
        AssetKind.vehicle,
      ]);
      expect(seeded.loanDebt, const Money(17_400_000));

      final priced = _ok(
        await repository.create(
          const AssetDraft(
            kind: AssetKind.vehicle,
            acquiredOn: CalendarDate(2024, 5, 20),
            fipe: testFipe,
          ),
        ),
      );
      expect(priced.value, fakeFipePrice);
      expect(priced.name, 'FIPE 001234-5');

      final watch = _ok(
        await repository.create(
          const AssetDraft(
            kind: AssetKind.other,
            name: ' Relógio ',
            acquiredOn: CalendarDate(2024, 5, 20),
            value: Money(300_000),
            fipe: testFipe,
          ),
        ),
      );
      expect(watch.name, 'Relógio');
      expect(watch.fipe, isNull);
      expect(watch.value, const Money(300_000));
    });

    test('revalues, marks sold and deletes', () async {
      final repository = fake();
      final home = _ok(
        await repository.revalue('asset-home', const Money(63_000_000)),
      );
      expect(home.value, const Money(63_000_000));
      expect(home.equity, const Money(45_600_000));
      final car = _ok(
        await repository.revalue('asset-car', const Money(9_000_000)),
      );
      expect(car.equity, const Money(9_000_000));

      final sold = _ok(
        await repository.markSold('asset-car', const CalendarDate(2026, 10, 8)),
      );
      expect(sold.sold, isTrue);
      expect(sold.value, const Money(0));

      expect(await repository.delete('asset-car'), isA<Ok<void>>());
      expect(
        (await repository.delete('asset-car') as Err).failure,
        const NotFoundFailure(),
      );
      expect(
        (await repository.revalue('missing', const Money(1)) as Err).failure,
        const NotFoundFailure(),
      );
    });
  });

  test('the backend picks the repository', () {
    for (final (backend, type) in [
      (Backend.fake, FakeAssetsRepository),
      (Backend.api, ApiAssetsRepository),
    ]) {
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(
            AppConfig(backend: backend, apiBaseUrl: 'https://api.test'),
          ),
          clockProvider.overrideWithValue(FixedClock(testNow)),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(assetsRepositoryProvider).runtimeType, type);
      expect(container.read(listAssetsProvider), isNotNull);
      expect(container.read(createAssetProvider), isNotNull);
      expect(container.read(revalueAssetProvider), isNotNull);
      expect(container.read(markAssetSoldProvider), isNotNull);
      expect(container.read(deleteAssetProvider), isNotNull);
    }
  });
}
