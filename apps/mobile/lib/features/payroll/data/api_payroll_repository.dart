import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/payroll/domain/payroll.dart';
import 'package:dio/dio.dart';

PayrollMonth payrollMonthFromJson(JsonMap json) => PayrollMonth(
  month: readDate(json, 'month'),
  proLabore: readMoney(json, 'proLabore'),
  salaries: readMoney(json, 'salaries'),
  fgts: readMoney(json, 'fgts'),
);

const Map<String, SimplesAnnex> _annexes = {
  'III': SimplesAnnex.iii,
  'V': SimplesAnnex.v,
};

PayrollSheet payrollSheetFromJson(JsonMap json) => PayrollSheet(
  current: payrollMonthFromJson(readMap(json, 'current')),
  history: readMapList(json, 'history').map(payrollMonthFromJson).toList(),
  revenue12: readMoney(json, 'revenue12'),
  declaredAnnex: _annexes[readOptionalString(json, 'declaredAnnex')],
);

String? _annexToJson(SimplesAnnex? annex) => switch (annex) {
  SimplesAnnex.iii => 'III',
  SimplesAnnex.v => 'V',
  null => null,
};

final class ApiPayrollRepository implements PayrollRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/payroll';

  @override
  Future<Result<PayrollSheet>> sheet() => guardRequest(() async {
    final response = await _dio.get<Object?>(path);
    return payrollSheetFromJson(asJsonMap(unwrapData(response.data)));
  });

  @override
  Future<Result<PayrollSheet>> save(PayrollMonth month) =>
      guardRequest(() async {
        final response = await _dio.put<Object?>(
          '$path/${month.month.iso.substring(0, 7)}',
          data: {
            'proLaboreCents': month.proLabore.cents,
            'salariesCents': month.salaries.cents,
            'fgtsCents': month.fgts.cents,
          },
        );
        return payrollSheetFromJson(asJsonMap(unwrapData(response.data)));
      });

  @override
  Future<Result<PayrollSheet>> declareAnnex(SimplesAnnex? annex) =>
      guardRequest(() async {
        final response = await _dio.put<Object?>(
          '$path/annex',
          data: {'annex': _annexToJson(annex)},
        );
        return payrollSheetFromJson(asJsonMap(unwrapData(response.data)));
      });
}
