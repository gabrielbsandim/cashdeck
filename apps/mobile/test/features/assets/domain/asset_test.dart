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
}) => AssetDraft(
  kind: kind,
  name: name,
  acquiredOn: acquiredOn,
  value: value,
  byFipe: byFipe,
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

  test('values compare by every field', () {
    expect(testAsset.sold, isFalse);
    expect(testAsset.props, hasLength(13));
    expect(testFipe.props, [VehicleType.car, '001234-5', 2022]);
    expect(testAsset.loan?.props, hasLength(3));
    expect(summaryOf([testAsset]).props, hasLength(4));
    expect(summaryOf(const []).isEmpty, isTrue);
    expect(_draft().props, hasLength(7));
    expect(testModel.props, ['10', 'Hatch Exemplo 1.0 Flex', '2022-5']);
    expect(testCatalogVehicle.props, hasLength(3));
  });
}
