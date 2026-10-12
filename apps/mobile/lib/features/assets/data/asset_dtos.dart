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

Asset assetFromJson(JsonMap json) {
  final change = readMap(json, 'change');
  final fipe = readOptionalMap(json, 'fipe');
  final loan = readOptionalMap(json, 'loan');
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
    if (draft.name.trim().isNotEmpty) 'name': draft.name.trim(),
    if (draft.value.cents > 0) 'value': draft.value.cents,
    if (fipe != null) 'fipe': fipeToJson(fipe),
  };
}
