import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/network/file_transfer.dart';
import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/capture/data/capture_dtos.dart';
import 'package:cashdeck/features/capture/data/upload_fit.dart';
import 'package:cashdeck/features/capture/domain/bill_draft.dart';
import 'package:cashdeck/features/capture/domain/capture_sources.dart';
import 'package:cashdeck/features/entities/data/entity_directory.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:dio/dio.dart';

final class ApiCaptureRepository implements CaptureRepository {
  new(this._dio, {this._shrink = shrinkImage})
    : _entities = EntityDirectory(_dio);

  final Dio _dio;
  final EntityDirectory _entities;
  final ImageShrinker _shrink;

  static const path = '/api/v1/capture';
  static const billsPath = '/api/v1/bills';

  String _mailbox(String id) => '$path/mailboxes/${Uri.encodeComponent(id)}';

  CaptureSources _sources(Response<Object?> response) =>
      captureSourcesFromJson(asJsonMap(unwrapData(response.data)));

  @override
  Future<Result<CaptureSources>> sources() => guardRequest(
    () async => _sources(await _dio.get<Object?>('$path/sources')),
  );

  @override
  Future<Result<CaptureSources>> readNow(String mailboxId) => guardRequest(
    () async => _sources(
      await _dio.post<Object?>(
        '${_mailbox(mailboxId)}/read',
        data: const <String, Object?>{},
      ),
    ),
  );

  @override
  Future<Result<CaptureSources>> disconnect(String mailboxId) => guardRequest(
    () async => _sources(await _dio.delete<Object?>(_mailbox(mailboxId))),
  );

  @override
  Future<Result<CaptureSources>> setDda(EntityKind owner, {required bool on}) =>
      guardRequest(
        () async => _sources(
          await _dio.put<Object?>(
            '$path/dda/${entityKindToJson(owner)}',
            data: {'enabled': on},
          ),
        ),
      );

  @override
  Future<Result<Uri>> mailboxAuthorizationUrl(EntityKind owner) =>
      guardRequest(() async {
        final response = await _dio.post<Object?>(
          '$path/mailboxes/oauth/start',
          data: {'entity': entityKindToJson(owner)},
        );
        final url = readString(asJsonMap(unwrapData(response.data)), 'url');
        return Uri.parse(url);
      });

  @override
  Future<Result<CaptureOutcome>> submitFile(
    LocalFile file,
    EntityKind owner,
  ) async {
    final upload = await fitForUpload(file, shrink: _shrink);
    if (upload == null) return Ok(CaptureFileTooLarge(file.bytes.length));
    return await guardRequest(
      () => _send('$path/files', {
        ...uploadBody(upload),
        'entity': entityKindToJson(owner),
      }, size: upload.bytes.length),
    );
  }

  @override
  Future<Result<CaptureOutcome>> capture(BillDraft draft) =>
      guardRequest(() async {
        final body = {
          'entityId': await _entities.idOf(draft.owner),
          ...captureBody(draft),
        };
        return await _send(billsPath, body);
      });

  /// A file upload passes [size]; its 413 and its 422 without a known code
  /// mean too large and nothing readable.
  Future<CaptureOutcome> _send(String to, JsonMap body, {int? size}) async {
    try {
      final response = await _dio.post<Object?>(to, data: body);
      return BillCaptured(
        billId: readString(asJsonMap(unwrapData(response.data)), 'id'),
        duplicate: response.statusCode == 200,
      );
    } on DioException catch (exception) {
      final outcome = captureOutcomeOf(exception.response, fileSize: size);
      if (outcome == null) rethrow;
      return outcome;
    }
  }
}
