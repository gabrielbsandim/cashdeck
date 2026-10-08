import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/automation/domain/automation.dart';
import 'package:dio/dio.dart';

AutomationStatus automationFromJson(JsonMap json) =>
    AutomationStatus(pausedSince: readOptionalDateTime(json, 'pausedSince'));

final class ApiAutomationRepository implements AutomationRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/automation';

  AutomationStatus _read(Response<Object?> response) =>
      automationFromJson(asJsonMap(unwrapData(response.data)));

  @override
  Future<Result<AutomationStatus>> status() =>
      guardRequest(() async => _read(await _dio.get<Object?>(path)));

  @override
  Future<Result<AutomationStatus>> pause() => guardRequest(
    () async => _read(
      await _dio.post<Object?>('$path/pause', data: const <String, Object?>{}),
    ),
  );

  @override
  Future<Result<AutomationStatus>> resume() => guardRequest(
    () async => _read(
      await _dio.post<Object?>('$path/resume', data: const <String, Object?>{}),
    ),
  );
}
