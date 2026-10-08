import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/capture/data/capture_dtos.dart';
import 'package:cashdeck/features/capture/domain/capture_sources.dart';
import 'package:cashdeck/features/capture/domain/scanned_code.dart';
import 'package:cashdeck/features/entities/data/entity_directory.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:dio/dio.dart';

final class ApiCaptureRepository implements CaptureRepository {
  new(this._dio) : _entities = EntityDirectory(_dio);

  final Dio _dio;
  final EntityDirectory _entities;

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

  /// The contract has no endpoint that reads a shared PDF or photo yet.
  @override
  Future<Result<void>> submitFile(LocalFile file, EntityKind owner) async =>
      const Err(UnsupportedFailure());

  @override
  Future<Result<void>> submitCode(ScannedCode code, EntityKind owner) =>
      guardRequest(() async {
        await _dio.post<Object?>(
          billsPath,
          data: {
            'entityId': await _entities.idOf(owner),
            'source': 'CAMERA',
            switch (code.kind) {
              ScannedKind.pix => 'pixCode',
              ScannedKind.boleto || ScannedKind.taxGuide => 'paymentCode',
            }: code.value,
          },
        );
      });
}
