import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/network/file_transfer.dart';
import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/loans/data/loan_dtos.dart';
import 'package:cashdeck/features/loans/domain/loan.dart';
import 'package:dio/dio.dart';

final class ApiLoansRepository implements LoansRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/loans';

  /// A statement runs to hundreds of installments, slower than a plain call.
  static const readTimeout = Duration(seconds: 60);

  String _loan(String id) => '$path/${Uri.encodeComponent(id)}';

  @override
  Future<Result<List<Loan>>> list() => guardRequest(() async {
    final response = await _dio.get<Object?>(path);
    final body = asJsonMap(unwrapData(response.data));
    return readMapList(body, 'items').map(loanFromJson).toList();
  });

  @override
  Future<Result<Loan>> importStatement(LocalFile file) =>
      guardRequest(() async {
        final response = await _dio.post<Object?>(
          '$path/import',
          data: {...uploadBody(file), 'entity': 'PF'},
          options: Options(receiveTimeout: readTimeout),
        );
        return loanFromJson(asJsonMap(unwrapData(response.data)));
      });

  @override
  Future<Result<Prepayment>> prepayment(String id, Money amount) =>
      guardRequest(() async {
        final response = await _dio.get<Object?>(
          '${_loan(id)}/prepayment',
          queryParameters: {'amount': amount.cents},
        );
        return prepaymentFromJson(asJsonMap(unwrapData(response.data)));
      });

  @override
  Future<Result<void>> delete(String id) =>
      guardRequest(() => _dio.delete<Object?>(_loan(id)));
}
