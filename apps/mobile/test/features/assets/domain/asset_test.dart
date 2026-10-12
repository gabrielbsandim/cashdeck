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
  FipeVehicle? fipe,
}) => AssetDraft(
  kind: kind,
  name: name,
  acquiredOn: acquiredOn,
  value: value,
  fipe: fipe,
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

  test('a vehicle priced by FIPE needs a valid code and model year only', () {
    final vehicle = _draft(
      kind: AssetKind.vehicle,
      name: '',
      value: const Money(0),
      fipe: testFipe,
    );
    expect(vehicle.problemOn(_today), isNull);
    expect(
      _draft(
        kind: AssetKind.vehicle,
        fipe: const FipeVehicle(
          type: VehicleType.car,
          code: '1234',
          modelYear: 2022,
        ),
      ).problemOn(_today),
      AssetProblem.fipeCode,
    );
    for (final year in [0, 1949, 2028]) {
      expect(
        _draft(
          kind: AssetKind.vehicle,
          fipe: FipeVehicle(
            type: VehicleType.car,
            code: testFipe.code,
            modelYear: year,
          ),
        ).problemOn(_today),
        AssetProblem.modelYear,
      );
    }
    expect(
      _draft(fipe: testFipe, name: '').problemOn(_today),
      AssetProblem.name,
      reason: 'only a vehicle is priced by the table',
    );
  });

  test('values compare by every field', () {
    expect(testAsset.sold, isFalse);
    expect(testAsset.props, hasLength(13));
    expect(testFipe.props, [VehicleType.car, '001234-5', 2022]);
    expect(testAsset.loan?.props, hasLength(3));
    expect(summaryOf([testAsset]).props, hasLength(4));
    expect(summaryOf(const []).isEmpty, isTrue);
    expect(_draft().props, hasLength(6));
  });
}
