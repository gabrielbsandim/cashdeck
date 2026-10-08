import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/bills/data/bill_dtos.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/bills/domain/bills_repository.dart';
import 'package:dio/dio.dart';

final class ApiBillsRepository implements BillsRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/bills';

  @override
  Future<Result<List<Bill>>> list() => guardRequest(() async {
    final response = await _dio.get<Object?>(path);
    return asJsonMapList(unwrapData(response.data)).map(billFromJson).toList();
  });

  @override
  Future<Result<Bill>> get(String id) => guardRequest(() async {
    final response = await _dio.get<Object?>(
      '$path/${Uri.encodeComponent(id)}',
    );
    return billFromJson(asJsonMap(unwrapData(response.data)));
  });

  @override
  Future<Result<Bill>> markPaid(String id) => guardRequest(() async {
    final response = await _dio.post<Object?>(
      '$path/${Uri.encodeComponent(id)}/mark-paid',
      data: const <String, Object?>{},
    );
    return billFromJson(asJsonMap(unwrapData(response.data)));
  });

  @override
  Future<Result<Bill>> confirmPayment(String id) => guardRequest(() async {
    final response = await _dio.post<Object?>(
      '$path/${Uri.encodeComponent(id)}/pay',
      data: const {'confirmed': true},
    );
    return billFromJson(asJsonMap(unwrapData(response.data)));
  });
}
