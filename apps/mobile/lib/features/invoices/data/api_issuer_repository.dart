import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/network/file_transfer.dart';
import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/invoices/domain/issuer_setup.dart';
import 'package:dio/dio.dart';

const Map<String, IssuerKind> _kinds = {
  'NATIONAL': IssuerKind.national,
  'MUNICIPAL': IssuerKind.municipal,
};

ServiceCode serviceCodeFromJson(JsonMap json) =>
    ServiceCode(readString(json, 'code'), readString(json, 'description'));

/// Null, before the first save, reads as [IssuerSetup.blank].
IssuerSetup issuerFromJson(Object? data) {
  if (data == null) return IssuerSetup.blank;
  final json = asJsonMap(data);
  return IssuerSetup(
    kind: readEnum(json, 'kind', _kinds),
    city: readString(json, 'city'),
    certificateName: readOptionalString(json, 'certificateName'),
    certificateExpiresOn: readOptionalDate(json, 'certificateExpiresOn'),
    municipalRegistration: readString(json, 'municipalRegistration'),
    serviceCode: serviceCodeFromJson(readMap(json, 'serviceCode')),
  );
}

final class ApiIssuerRepository implements IssuerRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/invoices';

  @override
  Future<Result<IssuerSetup>> setup() => guardRequest(() async {
    final response = await _dio.get<Object?>('$path/issuer');
    return issuerFromJson(unwrapData(response.data));
  });

  @override
  Future<Result<List<ServiceCode>>> serviceCodes() => guardRequest(() async {
    final response = await _dio.get<Object?>('$path/service-codes');
    return asJsonMapList(unwrapData(response.data))
        .map(serviceCodeFromJson)
        .toList();
  });

  @override
  Future<Result<IssuerSetup>> save(IssuerSetup setup) => guardRequest(() async {
    final response = await _dio.put<Object?>(
      '$path/issuer',
      data: {
        'kind': setup.kind.name.toUpperCase(),
        'city': setup.city,
        'municipalRegistration': setup.municipalRegistration,
        'serviceCode': setup.serviceCode.code,
      },
    );
    return issuerFromJson(unwrapData(response.data));
  });

  @override
  Future<Result<TestEmission>> emitTest(IssuerSetup setup) =>
      guardRequest(() async {
        final response = await _dio.post<Object?>(
          '$path/issuer/test',
          data: const <String, Object?>{},
        );
        final json = asJsonMap(unwrapData(response.data));
        return TestEmission(
          protocol: readString(json, 'protocol'),
          elapsed: Duration(milliseconds: readInt(json, 'elapsedMs')),
        );
      });

  @override
  Future<Result<IssuerSetup>> uploadCertificate(
    LocalFile file,
    String password,
    CalendarDate expiresOn,
  ) => guardRequest(() async {
    final response = await _dio.put<Object?>(
      '$path/issuer/certificate',
      data: {
        ...uploadBody(file),
        'password': password,
        'expiresOn': expiresOn.iso,
      },
    );
    return issuerFromJson(unwrapData(response.data));
  });
}
