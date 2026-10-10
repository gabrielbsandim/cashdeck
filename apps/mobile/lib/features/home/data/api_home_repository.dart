import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/home/data/home_dtos.dart';
import 'package:cashdeck/features/home/domain/home_repository.dart';
import 'package:cashdeck/features/home/domain/home_summary.dart';
import 'package:dio/dio.dart';

final class ApiHomeRepository implements HomeRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/home';

  Future<JsonMap> _get(String section) async {
    final response = await _dio.get<Object?>('$path/$section');
    return asJsonMap(unwrapData(response.data));
  }

  Future<JsonMap> _post(String action) async {
    final response = await _dio.post<Object?>(
      '$path/company/$action',
      data: const <String, Object?>{},
    );
    return asJsonMap(unwrapData(response.data));
  }

  @override
  Future<Result<PersonalSummary>> personal() =>
      guardRequest(() async => personalFromJson(await _get('personal')));

  @override
  Future<Result<FundingPlan>> funding() =>
      guardRequest(() async => fundingFromJson(await _get('personal/funding')));

  @override
  Future<Result<CompanySummary>> company() =>
      guardRequest(() async => companyFromJson(await _get('company')));

  @override
  Future<Result<ConsolidatedSummary>> consolidated() => guardRequest(
    () async => consolidatedFromJson(await _get('consolidated')),
  );

  @override
  Future<Result<CompanySummary>> approveDraft(String id) => guardRequest(
    () async => companyFromJson(
      await _post('drafts/${Uri.encodeComponent(id)}/approve'),
    ),
  );

  @override
  Future<Result<CompanySummary>> issueInvoiceFor(String receiptId) =>
      guardRequest(
        () async => companyFromJson(
          await _post('unbilled/${Uri.encodeComponent(receiptId)}/invoice'),
        ),
      );
}
