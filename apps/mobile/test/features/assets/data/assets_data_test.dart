import 'dart:typed_data';

import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/local_file.dart';
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

    test('an edit sends only what changed', () {
      AssetDraft draft({
        String name = 'Hatch Exemplo',
        bool byFipe = true,
        FipeVehicle? fipe = testFipe,
        Money value = const Money(9_000_000),
        String? loanId = 'loan-1',
      }) => AssetDraft(
        kind: AssetKind.vehicle,
        name: name,
        acquiredOn: testAsset.acquiredOn,
        value: value,
        byFipe: byFipe,
        fipe: fipe,
        loanId: loanId,
      );
      expect(assetEditToJson(testAsset, draft()), isEmpty);
      const sedan = FipeVehicle(
        type: VehicleType.car,
        code: '007777-7',
        modelYear: 2021,
      );
      expect(
        assetEditToJson(
          testAsset,
          const AssetDraft(
            kind: AssetKind.vehicle,
            name: ' Sedan ',
            acquiredOn: CalendarDate(2024, 1, 2),
            byFipe: true,
            fipe: sedan,
          ),
        ),
        {
          'name': 'Sedan',
          'acquiredOn': '2024-01-02',
          'loanId': null,
          'fipe': {'type': 'CAR', 'code': '007777-7', 'modelYear': 2021},
        },
      );
      expect(
        assetEditToJson(
          testAsset,
          draft(byFipe: false, fipe: null, value: const Money(8_000_000)),
        ),
        {'fipe': null, 'value': 8_000_000},
      );
    });

    test('read a rented good with the charge of its latest bill', () {
      final rented = assetFromJson(
        assetJson(rental: rentalJson(installment: _money(108_500))),
      );
      expect(rented.rental, testRental);
      final unlinked = assetFromJson(assetJson(rental: rentalJson()));
      expect(unlinked.rental?.charge?.installment, isNull);
      final waiting = assetFromJson(
        assetJson(rental: rentalJson(billed: false)),
      );
      expect(waiting.rental?.charge, isNull);
    });

    test('reads the rent received for a charge, absent or null as none', () {
      final paid = assetFromJson(
        assetJson(
          rental: rentalJson(
            received: {'on': '2026-10-08', 'amount': _money(173_665)},
          ),
        ),
      );
      expect(paid.rental?.charge?.received, testReceived);
      final absent = assetFromJson(assetJson(rental: rentalJson()));
      expect(absent.rental?.charge?.received, isNull);
      final json = rentalJson();
      final charge = Map.of(json['charge']! as Map<String, Object?>)
        ..['received'] = null;
      final cleared = assetFromJson(
        assetJson(rental: {...json, 'charge': charge}),
      );
      expect(cleared.rental?.charge?.received, isNull);
    });

    test('an edit sends the rental only when it changed', () {
      const rental = RentalDraft(
        rent: Money(160_000),
        billFrom: 'Jardim Azul ',
        passThrough: 'gás',
      );
      AssetDraft draft(RentalDraft? rental) => AssetDraft(
        kind: AssetKind.vehicle,
        name: 'Hatch Exemplo',
        acquiredOn: testAsset.acquiredOn,
        byFipe: true,
        fipe: testFipe,
        loanId: 'loan-1',
        rental: rental,
      );
      final rented = assetFromJson(assetJson(rental: rentalJson()));
      expect(assetEditToJson(testAsset, draft(null)), isEmpty);
      expect(assetEditToJson(rented, draft(rental)), isEmpty);
      expect(assetEditToJson(rented, draft(null)), {'rental': null});
      expect(assetEditToJson(testAsset, draft(rental)), {
        'rental': {
          'rent': 160_000,
          'passThrough': ['gás'],
          'billFrom': 'Jardim Azul',
        },
      });
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
          'rental': null,
          'name': 'Apartamento',
          'value': 50_000_000,
        },
      );
      expect(
        assetDraftToJson(
          const AssetDraft(
            kind: AssetKind.vehicle,
            acquiredOn: day,
            byFipe: true,
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
          'rental': null,
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
              byFipe: true,
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
      expect(
        _ok(
          await repository.edit(
            testAsset,
            AssetDraft(
              kind: AssetKind.vehicle,
              name: 'Carro',
              acquiredOn: testAsset.acquiredOn,
              byFipe: true,
              fipe: testFipe,
              loanId: 'loan-1',
            ),
          ),
        ),
        testAsset,
      );
      expect(adapterOf(dio).requests.last.data, {'name': 'Carro'});
    });

    test('downloads the bill behind a rent charge', () async {
      final dio = stubDio(
        (options) => switch (options.path) {
          '/api/v1/bills/bill-1/attachments/attachment-1' => StubResponse(
            200,
            Uint8List.fromList([37, 80, 68, 70]),
            const {
              'content-type': ['application/pdf'],
            },
          ),
          _ => const StubResponse(404),
        },
      );
      final repository = ApiAssetsRepository(dio);

      final bill = _ok(await repository.rentBill(testCharge));
      expect(bill.name, 'boleto.pdf');
      expect(bill.bytes, [37, 80, 68, 70]);
      const unattached = RentCharge(
        billId: 'bill-1',
        dueDate: CalendarDate(2026, 10, 10),
        billTotal: Money(1),
        passedOn: [],
        total: Money(1),
        ownerCost: Money(1),
        result: Money(1),
      );
      expect(
        await repository.rentBill(unattached),
        const Err<LocalFile>(NotFoundFailure()),
      );
    });

    test('walks the FIPE table from brand to a priced model', () async {
      final dio = stubDio(
        (options) => switch (options.path) {
          '/api/v1/vehicles/brands' => const StubResponse(200, {
            'data': {
              'items': [
                {'code': '1', 'name': 'Marca Exemplo'},
              ],
            },
          }),
          '/api/v1/vehicles/years' => const StubResponse(200, {
            'data': {
              'items': [
                {'code': '2022', 'name': '2022'},
              ],
            },
          }),
          '/api/v1/vehicles/models' => const StubResponse(200, {
            'data': {
              'items': [
                {
                  'code': '10',
                  'name': 'Hatch Exemplo 1.0 Flex',
                  'year': '2022-5',
                },
              ],
            },
          }),
          '/api/v1/vehicles/price' => StubResponse(200, {
            'data': {
              'fipe': {'type': 'CAR', 'code': '001234-5', 'modelYear': 2022},
              'model': 'Hatch Exemplo 1.0 Flex',
              'price': _money(9_000_000),
            },
          }),
          _ => const StubResponse(404),
        },
      );
      final repository = ApiAssetsRepository(dio);

      expect(_ok(await repository.brands(VehicleType.motorcycle)), [
        const VehicleOption(code: '1', name: 'Marca Exemplo'),
      ]);
      expect(_ok(await repository.years(VehicleType.car, '1')), [
        const VehicleOption(code: '2022', name: '2022'),
      ]);
      expect(_ok(await repository.models(VehicleType.car, '1', 2022)), [
        testModel,
      ]);
      expect(
        _ok(await repository.price(VehicleType.car, '1', testModel)),
        testCatalogVehicle,
      );
      expect(
        await repository.price(
          VehicleType.car,
          '1',
          const VehicleOption(code: '10', name: 'Sem ano'),
        ),
        isA<Ok<CatalogVehicle>>(),
      );

      final queries = adapterOf(dio).requests
          .map((request) => request.queryParameters)
          .toList();
      expect(queries[0], {'type': 'MOTORCYCLE'});
      expect(queries[2], {'type': 'CAR', 'brand': '1', 'modelYear': 2022});
      expect(queries[3], {
        'type': 'CAR',
        'brand': '1',
        'year': '2022-5',
        'model': '10',
      });
      expect(queries[4]['year'], '');
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
            byFipe: true,
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
      expect(watch.rental, isNull);
    });

    test('rents a good out, keeps its charge and sends its bill', () async {
      final repository = fake();
      final home = _ok(await repository.list()).items.first;
      final charge = home.rental?.charge;
      expect(charge?.total, const Money(173_665));

      final bill = _ok(await repository.rentBill(charge!));
      expect(bill.mimeType, 'application/pdf');
      const draft = RentalDraft(
        rent: Money(170_000),
        billFrom: ' Jardim Exemplo ',
        passThrough: 'gás, água',
      );
      final edited = _ok(
        await repository.edit(
          home,
          AssetDraft(
            kind: home.kind,
            name: home.name,
            acquiredOn: home.acquiredOn,
            value: home.value,
            loanId: home.loan?.id,
            rental: draft,
          ),
        ),
      );
      expect(edited.rental?.rent, const Money(170_000));
      expect(edited.rental?.passThrough, ['gás', 'água']);
      expect(edited.rental?.charge, charge);
      final revalued = _ok(
        await repository.revalue(home.id, const Money(70_000_000)),
      );
      expect(revalued.rental, edited.rental);

      final created = _ok(
        await repository.create(
          AssetDraft(
            kind: AssetKind.property,
            name: 'Casa',
            acquiredOn: home.acquiredOn,
            value: const Money(1),
            rental: draft,
          ),
        ),
      );
      expect(created.rental?.charge, isNull);
      expect(
        await repository.rentBill(
          RentCharge(
            billId: 'x',
            dueDate: charge.dueDate,
            billTotal: charge.billTotal,
            passedOn: const [],
            total: charge.total,
            ownerCost: charge.ownerCost,
            result: charge.result,
          ),
        ),
        const Err<LocalFile>(NotFoundFailure()),
      );
    });

    test('walks a small FIPE table', () async {
      final repository = fake();
      expect(_ok(await repository.brands(VehicleType.car)), hasLength(2));
      expect(
        _ok(await repository.years(VehicleType.car, '1')).first,
        const VehicleOption(code: '2027', name: '2027'),
      );
      final models = _ok(await repository.models(VehicleType.car, '1', 2026));
      expect(models.first.year, '2026-5');
      final vehicle = _ok(
        await repository.price(VehicleType.truck, '1', models.last),
      );
      expect(vehicle.fipe.code, '001211-5');
      expect(vehicle.fipe.modelYear, 2026);
      expect(vehicle.price, fakeFipePrice);
      expect(
        (await repository.price(
          VehicleType.car,
          '1',
          const VehicleOption(code: '99', name: 'Sem modelo'),
        ) as Err).failure,
        const NotFoundFailure(),
      );
    });

    test(
      'edits a good: another model, a value by hand, a loan dropped',
      () async {
        final repository = fake();
        final car = _ok(await repository.list()).items.last;
        const sedan = FipeVehicle(
          type: VehicleType.car,
          code: '007777-7',
          modelYear: 2021,
        );
        final moved = _ok(
          await repository.edit(
            car,
            AssetDraft(
              kind: AssetKind.vehicle,
              acquiredOn: car.acquiredOn,
              byFipe: true,
              fipe: sedan,
            ),
          ),
        );
        expect(moved.fipe, sedan);
        expect(moved.name, car.name);
        final kept = _ok(
          await repository.edit(
            moved,
            AssetDraft(
              kind: AssetKind.vehicle,
              name: 'Sedan da casa',
              acquiredOn: car.acquiredOn,
              byFipe: true,
              fipe: sedan,
            ),
          ),
        );
        expect(kept.value, moved.value);
        expect(kept.name, 'Sedan da casa');
        final home = _ok(await repository.list()).items.first;
        final unlinked = _ok(
          await repository.edit(
            home,
            AssetDraft(
              kind: AssetKind.property,
              name: home.name,
              acquiredOn: home.acquiredOn,
              value: const Money(70_000_000),
            ),
          ),
        );
        expect(unlinked.loan, isNull);
        expect(unlinked.equity, const Money(70_000_000));
      },
    );

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
      expect(container.read(browseVehiclesProvider), isNotNull);
      expect(container.read(editAssetProvider), isNotNull);
      expect(container.read(loadRentBillProvider), isNotNull);
    }
  });
}
