import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/network/file_transfer.dart';
import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/receipts/domain/receipt.dart';
import 'package:dio/dio.dart';

Receipt receiptFromJson(JsonMap json) => Receipt(
  billId: readString(json, 'billId'),
  proof: switch (readOptionalMap(json, 'proof')) {
    null => null,
    final proof => BankProof(
      rail: readString(proof, 'rail'),
      amount: readMoney(proof, 'amount'),
      paidAt: readDateTime(proof, 'paidAt'),
      payer: readString(proof, 'payer'),
      receiver: readString(proof, 'receiver'),
      transactionId: readOptionalString(proof, 'transactionId'),
      authentication: readOptionalString(proof, 'authentication'),
    ),
  },
  attachments: [
    for (final attachment in readMapList(json, 'attachments'))
      Attachment(
        id: readString(attachment, 'id'),
        fileName: readString(attachment, 'fileName'),
      ),
  ],
);

final class ApiReceiptsRepository implements ReceiptsRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/bills';

  String _bill(String billId) => '$path/${Uri.encodeComponent(billId)}';

  Future<Receipt> _receipt(String billId) async {
    final response = await _dio.get<Object?>('${_bill(billId)}/receipt');
    return receiptFromJson(asJsonMap(unwrapData(response.data)));
  }

  @override
  Future<Result<Receipt>> receipt(String billId) =>
      guardRequest(() => _receipt(billId));

  /// The server renders it from the rail proof, or from the bill when it was
  /// marked paid by hand; it answers 422 while the bill is open.
  @override
  Future<Result<LocalFile>> document(String billId) => guardRequest(
    () => downloadFile(
      _dio,
      '${_bill(billId)}/receipt/pdf',
      fallbackName: 'comprovante-$billId.pdf',
    ),
  );

  @override
  Future<Result<Receipt>> attach(String billId, LocalFile file) =>
      guardRequest(() async {
        await _dio.post<Object?>(
          '${_bill(billId)}/attachments',
          data: uploadBody(file),
        );
        return await _receipt(billId);
      });
}
