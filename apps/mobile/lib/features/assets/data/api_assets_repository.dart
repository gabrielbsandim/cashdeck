import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/assets/data/asset_dtos.dart';
import 'package:cashdeck/features/assets/domain/asset.dart';
import 'package:dio/dio.dart';

final class ApiAssetsRepository implements AssetsRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/assets';

  String _asset(String id) => '$path/${Uri.encodeComponent(id)}';

  Future<Result<Asset>> _patch(String id, JsonMap body) =>
      guardRequest(() async {
        final response = await _dio.patch<Object?>(_asset(id), data: body);
        return assetFromJson(asJsonMap(unwrapData(response.data)));
      });

  @override
  Future<Result<AssetsSummary>> list() => guardRequest(() async {
    final response = await _dio.get<Object?>(path);
    return assetsFromJson(asJsonMap(unwrapData(response.data)));
  });

  @override
  Future<Result<Asset>> create(AssetDraft draft) => guardRequest(() async {
    final response = await _dio.post<Object?>(
      path,
      data: assetDraftToJson(draft),
    );
    return assetFromJson(asJsonMap(unwrapData(response.data)));
  });

  @override
  Future<Result<Asset>> edit(Asset before, AssetDraft draft) =>
      _patch(before.id, assetEditToJson(before, draft));

  @override
  Future<Result<Asset>> revalue(String id, Money value) =>
      _patch(id, {'value': value.cents});

  @override
  Future<Result<Asset>> markSold(String id, CalendarDate on) =>
      _patch(id, {'soldOn': on.iso});

  @override
  Future<Result<void>> delete(String id) =>
      guardRequest(() => _dio.delete<Object?>(_asset(id)));

  static const vehiclesPath = '/api/v1/vehicles';

  Future<JsonMap> _catalog(String step, Map<String, Object> query) async {
    final response = await _dio.get<Object?>(
      '$vehiclesPath/$step',
      queryParameters: query,
    );
    return asJsonMap(unwrapData(response.data));
  }

  Future<Result<List<VehicleOption>>> _options(
    String step,
    Map<String, Object> query,
  ) => guardRequest(() async {
    final json = await _catalog(step, query);
    return readMapList(json, 'items').map(vehicleOptionFromJson).toList();
  });

  @override
  Future<Result<List<VehicleOption>>> brands(VehicleType type) =>
      _options('brands', {'type': vehicleTypeToJson(type)});

  @override
  Future<Result<List<VehicleOption>>> years(VehicleType type, String brand) =>
      _options('years', {'type': vehicleTypeToJson(type), 'brand': brand});

  @override
  Future<Result<List<VehicleOption>>> models(
    VehicleType type,
    String brand,
    int modelYear,
  ) => _options('models', {
    'type': vehicleTypeToJson(type),
    'brand': brand,
    'modelYear': modelYear,
  });

  @override
  Future<Result<CatalogVehicle>> price(
    VehicleType type,
    String brand,
    VehicleOption model,
  ) => guardRequest(() async {
    final json = await _catalog('price', {
      'type': vehicleTypeToJson(type),
      'brand': brand,
      'year': model.year ?? '',
      'model': model.code,
    });
    return catalogVehicleFromJson(json);
  });
}
