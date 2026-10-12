import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/goals/data/goal_dtos.dart';
import 'package:cashdeck/features/goals/domain/goal.dart';
import 'package:dio/dio.dart';

final class ApiGoalsRepository implements GoalsRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/goals';

  String _goal(String id) => '$path/${Uri.encodeComponent(id)}';

  Goal _read(Response<Object?> response) =>
      goalFromJson(asJsonMap(unwrapData(response.data)));

  @override
  Future<Result<List<Goal>>> list() => guardRequest(() async {
    final response = await _dio.get<Object?>(
      path,
      queryParameters: {'entity': 'PF'},
    );
    return asJsonMapList(unwrapData(response.data)).map(goalFromJson).toList();
  });

  @override
  Future<Result<Goal>> get(String id) =>
      guardRequest(() async => _read(await _dio.get<Object?>(_goal(id))));

  @override
  Future<Result<Goal>> create(GoalDraft draft) => guardRequest(
    () async =>
        _read(await _dio.post<Object?>(path, data: goalCreateToJson(draft))),
  );

  @override
  Future<Result<Goal>> update(String id, GoalDraft draft) => guardRequest(
    () async => _read(
      await _dio.patch<Object?>(_goal(id), data: goalUpdateToJson(draft)),
    ),
  );

  @override
  Future<Result<Goal>> archive(String id) => guardRequest(
    () async =>
        _read(await _dio.patch<Object?>(_goal(id), data: {'archived': true})),
  );

  @override
  Future<Result<void>> delete(String id) =>
      guardRequest(() => _dio.delete<Object?>(_goal(id)));

  @override
  Future<Result<Goal>> contribute(String id, Money amount, {String? note}) =>
      guardRequest(
        () async => _read(
          await _dio.post<Object?>(
            '${_goal(id)}/contributions',
            data: {'amountCents': amount.cents, 'note': ?note},
          ),
        ),
      );

  @override
  Future<Result<Goal>> removeContribution(String id, String contributionId) =>
      guardRequest(
        () async => _read(
          await _dio.delete<Object?>(
            '${_goal(id)}/contributions/${Uri.encodeComponent(contributionId)}',
          ),
        ),
      );
}
