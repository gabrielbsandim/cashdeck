import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/transactions/data/transaction_dtos.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:dio/dio.dart';

final class ApiTransactionsRepository implements TransactionsRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/transactions';
  static const accountsPath = '/api/v1/accounts';

  @override
  Future<Result<TransactionPage>> list(
    TransactionQuery query, {
    String? cursor,
  }) => guardRequest(() async {
    final response = await _dio.get<Object?>(
      path,
      queryParameters: transactionQueryToJson(query, cursor: cursor),
    );
    final body = asJsonMap(response.data);
    return TransactionPage(
      items: asJsonMapList(unwrapData(body)).map(transactionFromJson).toList(),
      nextCursor: readOptionalString(body, 'nextCursor'),
    );
  });

  @override
  Future<Result<TransactionUpdateResult>> update(
    String id,
    TransactionUpdate update,
  ) => guardRequest(() async {
    final response = await _dio.patch<Object?>(
      '$path/${Uri.encodeComponent(id)}',
      data: transactionUpdateToJson(update),
    );
    final data = asJsonMap(unwrapData(response.data));
    return TransactionUpdateResult(
      transaction: transactionFromJson(readMap(data, 'transaction')),
      similarUpdated: readInt(data, 'similarUpdated'),
    );
  });

  @override
  Future<Result<List<TransactionAccount>>> accounts() => guardRequest(() async {
    final response = await _dio.get<Object?>(accountsPath);
    return asJsonMapList(unwrapData(response.data))
        .map(accountFromJson)
        .toList();
  });
}

final class ApiCategoriesRepository implements CategoriesRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/categories';

  @override
  Future<Result<List<Category>>> list() => guardRequest(() async {
    final response = await _dio.get<Object?>(path);
    return asJsonMapList(unwrapData(response.data))
        .map(categoryFromJson)
        .toList();
  });
}
