import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/assets/domain/asset.dart';
import 'package:flutter_test/flutter_test.dart';

import '../asset_builders.dart';

const _today = CalendarDate(2026, 10, 12);

AssetDraft _draft({
  AssetKind kind = AssetKind.property,
  String name = 'Apartamento',
  CalendarDate acquiredOn = const CalendarDate(2025, 6, 10),
  Money value = const Money(50_000_000),
  bool byFipe = false,
  FipeVehicle? fipe,
  RentalDraft? rental,
}) => AssetDraft(
  kind: kind,
  name: name,
  acquiredOn: acquiredOn,
  value: value,
  byFipe: byFipe,
  fipe: fipe,
  rental: rental,
);

const _rental = RentalDraft(
  rent: Money(160_000),
  billFrom: ' Jardim Azul ',
  passThrough: 'gás, , água ',
);

void main() {
  test('a draft names the first thing missing', () {
    expect(_draft().problemOn(_today), isNull);
    expect(
      _draft(acquiredOn: const CalendarDate(2026, 10, 13)).problemOn(_today),
      AssetProblem.futureDate,
    );
    expect(_draft(name: '  ').problemOn(_today), AssetProblem.name);
    expect(_draft(value: const Money(0)).problemOn(_today), AssetProblem.value);
  });

  test('a vehicle priced by FIPE needs only the model from the table', () {
    expect(
      _draft(
        kind: AssetKind.vehicle,
        name: '',
        value: const Money(0),
        byFipe: true,
        fipe: testFipe,
      ).problemOn(_today),
      isNull,
    );
    expect(
      _draft(kind: AssetKind.vehicle, byFipe: true).problemOn(_today),
      AssetProblem.vehicle,
    );
    expect(
      _draft(byFipe: true, fipe: testFipe, name: '').problemOn(_today),
      AssetProblem.name,
      reason: 'only a vehicle is priced by the table',
    );
  });

  test('a rented good needs the rent and the building on the bill', () {
    expect(_draft(rental: _rental).problemOn(_today), isNull);
    expect(
      _draft(
        rental: const RentalDraft(rent: Money(0), billFrom: 'Jardim'),
      ).problemOn(_today),
      AssetProblem.rent,
    );
    expect(
      _draft(
        rental: const RentalDraft(rent: Money(1), billFrom: ' '),
      ).problemOn(_today),
      AssetProblem.billFrom,
    );
  });

  test('a rental draft reads its words and tells whether it changed', () {
    expect(_rental.words, ['gás', 'água']);
    const rental = AssetRental(
      rent: Money(160_000),
      passThrough: ['gás', 'água'],
      billFrom: 'Jardim Azul',
    );
    expect(_rental.matches(rental), isTrue);
    expect(_rental.matches(null), isFalse);
    expect(
      _rental.matches(
        const AssetRental(
          rent: Money(160_000),
          passThrough: ['água', 'gás'],
          billFrom: 'Jardim Azul',
        ),
      ),
      isFalse,
    );
    expect(
      _rental.matches(
        const AssetRental(
          rent: Money(160_000),
          passThrough: ['gás'],
          billFrom: 'Jardim Azul',
        ),
      ),
      isFalse,
    );
    expect(_rental.props, hasLength(3));
    expect(rental.props, hasLength(4));
    expect(testRental.charge?.props, hasLength(9));
    expect(testRental.charge?.passedOn.single.props, hasLength(2));
  });

  test('values compare by every field', () {
    expect(testAsset.sold, isFalse);
    expect(testAsset.props, hasLength(14));
    expect(testFipe.props, [VehicleType.car, '001234-5', 2022]);
    expect(testAsset.loan?.props, hasLength(3));
    expect(summaryOf([testAsset]).props, hasLength(4));
    expect(summaryOf(const []).isEmpty, isTrue);
    expect(_draft().props, hasLength(8));
    expect(testModel.props, ['10', 'Hatch Exemplo 1.0 Flex', '2022-5']);
    expect(testCatalogVehicle.props, hasLength(3));
  });
}
