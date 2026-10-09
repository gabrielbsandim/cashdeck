import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/open_finance/domain/item_lookup.dart';
import 'package:dio/dio.dart';

ItemLookup itemLookupFromJson(JsonMap json) => switch (readString(
  json,
  'status',
)) {
  'FOUND' => ItemFound(
    institution: readString(json, 'institution'),
    consentUntil: readOptionalDate(json, 'consentUntil'),
    accounts: [
      for (final account in readMapList(json, 'accounts'))
        FoundAccount(
          id: readString(account, 'id'),
          name: readString(account, 'name'),
          balance: readMoney(account, 'balance'),
        ),
    ],
  ),
  'NOT_FOUND' => const ItemNotFound(),
  'ALREADY_CONNECTED' => ItemAlreadyConnected(readEntityKind(json, 'owner')),
  final other => throw FormatException('Unknown lookup status', other),
};

final class ApiOpenFinanceRepository implements OpenFinanceRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/open-finance';

  @override
  Future<Result<ItemLookup>> lookup(String itemId) => guardRequest(() async {
    final response = await _dio.post<Object?>(
      '$path/lookup',
      data: {'itemId': itemId.trim().toLowerCase()},
    );
    return itemLookupFromJson(asJsonMap(unwrapData(response.data)));
  });

  @override
  Future<Result<int>> import(
    String itemId,
    Set<String> accountIds,
    EntityKind owner,
  ) => guardRequest(() async {
    final response = await _dio.post<Object?>(
      '$path/connections',
      data: {
        'itemId': itemId.trim().toLowerCase(),
        'entity': entityKindToJson(owner),
        'accountIds': accountIds.toList(),
      },
    );
    return readInt(asJsonMap(unwrapData(response.data)), 'imported');
  });

  @override
  Future<Result<int>> sync(String connectionId, {required int days}) =>
      guardRequest(() async {
        final response = await _dio.post<Object?>(
          '$path/connections/$connectionId/sync',
          queryParameters: {'days': days},
        );
        return readInt(asJsonMap(unwrapData(response.data)), 'transactions');
      });
}
