import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/features/assets/domain/asset.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';

const Map<String, AssetKind> assetKinds = {
  'PROPERTY': AssetKind.property,
  'VEHICLE': AssetKind.vehicle,
  'OTHER': AssetKind.other,
};

const Map<String, VehicleType> vehicleTypes = {
  'CAR': VehicleType.car,
  'MOTORCYCLE': VehicleType.motorcycle,
  'TRUCK': VehicleType.truck,
};

String _keyOf<T>(Map<String, T> table, T value) =>
    table.entries.firstWhere((entry) => entry.value == value).key;

double? _readOptionalNumber(JsonMap json, String key) {
  final value = json[key];
  if (value == null || value is num) return (value as num?)?.toDouble();
  throw FormatException('Expected a number or null at "$key"', json);
}

FipeVehicle fipeFromJson(JsonMap json) => FipeVehicle(
  type: readEnum(json, 'type', vehicleTypes),
  code: readString(json, 'code'),
  modelYear: readInt(json, 'modelYear'),
);

JsonMap fipeToJson(FipeVehicle fipe) => {
  'type': vehicleTypeToJson(fipe.type),
  'code': fipe.code,
  'modelYear': fipe.modelYear,
};

RentCharge rentChargeFromJson(JsonMap json) {
  final installment = readOptionalMap(json, 'installment');
  final received = readOptionalMap(json, 'received');
  return RentCharge(
    billId: readString(json, 'billId'),
    dueDate: readDate(json, 'dueDate'),
    billTotal: readMoney(json, 'billTotal'),
    passedOn: [
      for (final line in readMapList(json, 'passedOn'))
        BillLine(
          description: readString(line, 'description'),
          amount: readMoney(line, 'amount'),
        ),
    ],
    total: readMoney(json, 'total'),
    ownerCost: readMoney(json, 'ownerCost'),
    result: readMoney(json, 'result'),
    attachmentId: readOptionalString(json, 'attachmentId'),
    installment: installment == null ? null : moneyFromJson(installment),
    received: received == null
        ? null
        : RentReceived(
            on: readDate(received, 'on'),
            amount: readMoney(received, 'amount'),
          ),
  );
}

AssetRental rentalFromJson(JsonMap json) {
  final charge = readOptionalMap(json, 'charge');
  return AssetRental(
    rent: readMoney(json, 'rent'),
    passThrough: readStringList(json, 'passThrough'),
    billFrom: readString(json, 'billFrom'),
    charge: charge == null ? null : rentChargeFromJson(charge),
  );
}

JsonMap? rentalToJson(RentalDraft? rental) => rental == null
    ? null
    : {
        'rent': rental.rent.cents,
        'passThrough': rental.words,
        'billFrom': rental.billFrom.trim(),
      };

Asset assetFromJson(JsonMap json) {
  final change = readMap(json, 'change');
  final fipe = readOptionalMap(json, 'fipe');
  final loan = readOptionalMap(json, 'loan');
  final rental = readOptionalMap(json, 'rental');
  return Asset(
    id: readString(json, 'id'),
    entity: entityKindFromJson(readString(json, 'entity')),
    kind: readEnum(json, 'kind', assetKinds),
    name: readString(json, 'name'),
    acquiredOn: readDate(json, 'acquiredOn'),
    soldOn: readOptionalDate(json, 'soldOn'),
    value: readMoney(json, 'value'),
    valuedOn: readDate(json, 'valuedOn'),
    change: readMoney(change, 'amount'),
    changePercent: _readOptionalNumber(change, 'percent'),
    fipe: fipe == null ? null : fipeFromJson(fipe),
    loan: loan == null
        ? null
        : AssetLoan(
            id: readString(loan, 'id'),
            name: readString(loan, 'name'),
            balance: readMoney(loan, 'balance'),
          ),
    equity: readMoney(json, 'equity'),
    rental: rental == null ? null : rentalFromJson(rental),
  );
}

AssetsSummary assetsFromJson(JsonMap json) => AssetsSummary(
  items: readMapList(json, 'items').map(assetFromJson).toList(),
  value: readMoney(json, 'value'),
  loanDebt: readMoney(json, 'loanDebt'),
  equity: readMoney(json, 'equity'),
);

VehicleOption vehicleOptionFromJson(JsonMap json) => VehicleOption(
  code: readString(json, 'code'),
  name: readString(json, 'name'),
  year: readOptionalString(json, 'year'),
);

CatalogVehicle catalogVehicleFromJson(JsonMap json) => CatalogVehicle(
  fipe: fipeFromJson(readMap(json, 'fipe')),
  model: readString(json, 'model'),
  price: readMoney(json, 'price'),
);

String vehicleTypeToJson(VehicleType type) => _keyOf(vehicleTypes, type);

/// What [draft] changes from [before]. Another FIPE model reprices the
/// vehicle; leaving the table sends `fipe: null` and the value by hand.
JsonMap assetEditToJson(Asset before, AssetDraft draft) {
  final priced = draft.kind == AssetKind.vehicle && draft.byFipe;
  final fipe = priced ? draft.fipe : null;
  final name = draft.name.trim();
  return {
    if (name.isNotEmpty && name != before.name) 'name': name,
    if (draft.acquiredOn != before.acquiredOn)
      'acquiredOn': draft.acquiredOn.iso,
    if (draft.loanId != before.loan?.id) 'loanId': draft.loanId,
    if (fipe != null && fipe != before.fipe) 'fipe': fipeToJson(fipe),
    if (!priced && before.fipe != null) 'fipe': null,
    if (!priced && draft.value != before.value) 'value': draft.value.cents,
    if (!_sameRental(before.rental, draft.rental))
      'rental': rentalToJson(draft.rental),
  };
}

bool _sameRental(AssetRental? before, RentalDraft? draft) => switch (draft) {
  null => before == null,
  final draft => draft.matches(before),
};

/// The table names and prices a vehicle with a FIPE code, so neither is sent.
JsonMap assetDraftToJson(AssetDraft draft) {
  final fipe = draft.kind == AssetKind.vehicle && draft.byFipe
      ? draft.fipe
      : null;
  return {
    'entity': 'PF',
    'kind': _keyOf(assetKinds, draft.kind),
    'acquiredOn': draft.acquiredOn.iso,
    'loanId': draft.loanId,
    'rental': rentalToJson(draft.rental),
    if (draft.name.trim().isNotEmpty) 'name': draft.name.trim(),
    if (draft.value.cents > 0) 'value': draft.value.cents,
    if (fipe != null) 'fipe': fipeToJson(fipe),
  };
}
