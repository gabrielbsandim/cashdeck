import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/assets/domain/asset.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';

Map<String, Object?> _money(int cents) => {'cents': cents, 'currency': 'BRL'};

Map<String, Object?> assetJson({
  String id = 'asset-1',
  Object? percent = 4.5,
  Object? fipe = const {'type': 'CAR', 'code': '001234-5', 'modelYear': 2022},
  Object? loan = const {
    'id': 'loan-1',
    'name': 'Banco Exemplo 1001',
    'balance': {'cents': 3_000_000, 'currency': 'BRL'},
  },
  String? soldOn,
  Object? rental,
}) => {
  'id': id,
  'entity': 'PF',
  'kind': 'VEHICLE',
  'name': 'Hatch Exemplo',
  'acquiredOn': '2024-05-20',
  'soldOn': soldOn,
  'value': _money(9_000_000),
  'valuedOn': '2026-10-01',
  'change': {'amount': _money(-400_000), 'percent': percent},
  'fipe': fipe,
  'loan': loan,
  'equity': _money(6_000_000),
  'rental': rental,
};

const testFipe = FipeVehicle(
  type: VehicleType.car,
  code: '001234-5',
  modelYear: 2022,
);

const testModel = VehicleOption(
  code: '10',
  name: 'Hatch Exemplo 1.0 Flex',
  year: '2022-5',
);

const testCatalogVehicle = CatalogVehicle(
  fipe: testFipe,
  model: 'Hatch Exemplo 1.0 Flex',
  price: Money(9_000_000),
);

const testAsset = Asset(
  id: 'asset-1',
  entity: EntityKind.personal,
  kind: AssetKind.vehicle,
  name: 'Hatch Exemplo',
  acquiredOn: CalendarDate(2024, 5, 20),
  value: Money(9_000_000),
  valuedOn: CalendarDate(2026, 10, 1),
  change: Money(-400_000),
  changePercent: 4.5,
  fipe: testFipe,
  loan: AssetLoan(
    id: 'loan-1',
    name: 'Banco Exemplo 1001',
    balance: Money(3_000_000),
  ),
  equity: Money(6_000_000),
);

AssetsSummary summaryOf(List<Asset> items) => AssetsSummary(
  items: items,
  value: items.fold(const Money(0), (sum, asset) => sum + asset.value),
  loanDebt: const Money(0),
  equity: items.fold(const Money(0), (sum, asset) => sum + asset.equity),
);

const testCharge = RentCharge(
  billId: 'bill-1',
  dueDate: CalendarDate(2026, 10, 10),
  billTotal: Money(59_769),
  passedOn: [BillLine(description: 'Consumo de gás', amount: Money(13_665))],
  total: Money(173_665),
  ownerCost: Money(46_104),
  attachmentId: 'attachment-1',
  installment: Money(108_500),
  result: Money(5_396),
);

const testReceived = RentReceived(
  on: CalendarDate(2026, 10, 8),
  amount: Money(173_665),
);

const testRental = AssetRental(
  rent: Money(160_000),
  passThrough: ['gás'],
  billFrom: 'Jardim Azul',
  charge: testCharge,
);

Map<String, Object?> rentalJson({
  bool billed = true,
  Object? installment,
  Map<String, Object?>? received,
}) => {
  'rent': _money(160_000),
  'passThrough': ['gás'],
  'billFrom': 'Jardim Azul',
  'charge': !billed
      ? null
      : {
          'billId': 'bill-1',
          'dueDate': '2026-10-10',
          'billTotal': _money(59_769),
          'passedOn': [
            {'description': 'Consumo de gás', 'amount': _money(13_665)},
          ],
          'total': _money(173_665),
          'ownerCost': _money(46_104),
          'attachmentId': 'attachment-1',
          'installment': installment,
          'result': _money(5_396),
          'received': ?received,
        },
};
