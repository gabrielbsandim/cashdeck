import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/card_import/domain/card_statement.dart';
import 'package:dio/dio.dart';

CardStatement cardStatementFromJson(JsonMap json) => CardStatement(
  id: readString(json, 'id'),
  card: readString(json, 'card'),
  issuer: readString(json, 'issuer'),
  closing: readDate(json, 'closing'),
  due: readDate(json, 'due'),
  rate: readInt(json, 'rate'),
  iofBps: readInt(json, 'iofBps'),
  lines: [
    for (final line in readMapList(json, 'lines'))
      StatementLine(
        id: readString(line, 'id'),
        merchant: readString(line, 'merchant'),
        date: readDate(line, 'date'),
        amount: readMoney(line, 'amount'),
        needsReview: readBool(line, 'needsReview'),
      ),
  ],
);

final class ApiCardImportRepository implements CardImportRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/card-statements';

  /// No draft waiting reads as not found, which the screen already shows.
  @override
  Future<Result<CardStatement>> statement() =>
      guardRequest<CardStatement?>(() async {
        final data = unwrapData((await _dio.get<Object?>('$path/latest')).data);
        return data == null ? null : cardStatementFromJson(asJsonMap(data));
      }).then(
        (result) => switch (result) {
          Ok(value: final statement?) => Ok(statement),
          Ok() => const Err(NotFoundFailure()),
          Err(:final failure) => Err(failure),
        },
      );

  @override
  Future<Result<String>> createBill(
    CardStatement statement,
    Set<String> lineIds,
  ) => guardRequest(() async {
    final response = await _dio.post<Object?>(
      '$path/${Uri.encodeComponent(statement.id)}/bill',
      data: {'lineIds': lineIds.toList()},
    );
    return readString(asJsonMap(unwrapData(response.data)), 'billId');
  });
}
