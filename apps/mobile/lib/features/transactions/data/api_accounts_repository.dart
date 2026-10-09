import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/transactions/data/transaction_dtos.dart';
import 'package:cashdeck/features/transactions/domain/accounts_repository.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:dio/dio.dart';

final class ApiAccountsRepository implements AccountsRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/accounts';

  @override
  Future<Result<TransactionAccount>> rename(String id, String name) =>
      guardRequest(() async {
        final response = await _dio.patch<Object?>(
          '$path/${Uri.encodeComponent(id)}',
          data: {'name': name},
        );
        return accountFromJson(asJsonMap(unwrapData(response.data)));
      });
}
