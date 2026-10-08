import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';
import 'package:cashdeck/features/transactions/domain/internal_transfer.dart';
import 'package:dio/dio.dart';

const Map<String, TransferKind> _kinds = {
  'PROFIT_DISTRIBUTION': TransferKind.profitDistribution,
  'PRO_LABORE': TransferKind.proLabore,
};

TransferParty _party(JsonMap json) => TransferParty(
  owner: readEntityKind(json, 'owner'),
  holder: readString(json, 'holder'),
  account: readString(json, 'account'),
);

TransferDetail transferFromJson(JsonMap json) => TransferDetail(
  id: readString(json, 'id'),
  kind: readEnum(json, 'kind', _kinds),
  amount: readMoney(json, 'amount'),
  at: readDateTime(json, 'at'),
  rail: readString(json, 'rail'),
  from: _party(readMap(json, 'from')),
  to: _party(readMap(json, 'to')),
  document: readOptionalString(json, 'document'),
);

final class ApiTransfersRepository implements TransfersRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/transfers';

  @override
  Future<Result<TransferDetail>> transfer(String id) => guardRequest(() async {
    final response = await _dio.get<Object?>(
      '$path/${Uri.encodeComponent(id)}',
    );
    return transferFromJson(asJsonMap(unwrapData(response.data)));
  });

  /// The contract names the document but has no route to download it yet.
  @override
  Future<Result<LocalFile>> document(String id) async =>
      const Err(UnsupportedFailure());
}
