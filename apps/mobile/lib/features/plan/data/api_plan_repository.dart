import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/plan/data/plan_dtos.dart';
import 'package:cashdeck/features/plan/domain/life_plan.dart';
import 'package:dio/dio.dart';

final class ApiPlanRepository implements PlanRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/plan';

  String _goal(String id) => '$path/goals/${Uri.encodeComponent(id)}';

  Future<Result<LifePlan>> _read(Future<Response<Object?>> request) =>
      guardRequest(
        () async =>
            lifePlanFromJson(asJsonMap(unwrapData((await request).data))),
      );

  @override
  Future<Result<LifePlan>> load() => _read(_dio.get<Object?>(path));

  @override
  Future<Result<LifePlan>> create(PlanGoalDraft draft) =>
      _read(_dio.post<Object?>('$path/goals', data: planGoalToJson(draft)));

  @override
  Future<Result<LifePlan>> update(String id, PlanGoalDraft draft) =>
      _read(_dio.put<Object?>(_goal(id), data: planGoalToJson(draft)));

  @override
  Future<Result<LifePlan>> remove(String id) =>
      _read(_dio.delete<Object?>(_goal(id)));

  @override
  Future<Result<LifePlan>> reorder(List<String> ids) =>
      _read(_dio.put<Object?>('$path/order', data: {'ids': ids}));

  @override
  Future<Result<PlanAdvice>> advise({String? goalId}) => guardRequest(() async {
    final response = await _dio.post<Object?>(
      '$path/advice',
      data: {'goalId': goalId},
    );
    return planAdviceFromJson(asJsonMap(unwrapData(response.data)));
  });

  @override
  Future<Result<LifePlan>> arrange(PlanAdvice advice) => _read(
    _dio.put<Object?>('$path/arrangement', data: planArrangementToJson(advice)),
  );

  @override
  Future<Result<LifePlan>> saveSettings(PlanSettings settings) => _read(
    _dio.put<Object?>('$path/settings', data: planSettingsToJson(settings)),
  );
}
