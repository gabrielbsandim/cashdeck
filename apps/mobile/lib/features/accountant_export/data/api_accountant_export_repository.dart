import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/network/file_transfer.dart';
import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/accountant_export/domain/accountant_export.dart';
import 'package:dio/dio.dart';

const Map<ExportPeriod, String> _periods = {
  ExportPeriod.lastMonth: 'LAST_MONTH',
  ExportPeriod.lastQuarter: 'LAST_QUARTER',
  ExportPeriod.custom: 'CUSTOM',
};

const Map<String, ExportItemKind> _kinds = {
  'STATEMENTS': ExportItemKind.statements,
  'INVOICES': ExportItemKind.invoices,
  'TAX_GUIDES': ExportItemKind.taxGuides,
  'EXPENSES': ExportItemKind.expenses,
  'PAYROLL': ExportItemKind.payroll,
  'RECONCILIATION': ExportItemKind.reconciliation,
};

String _kindToJson(ExportItemKind kind) =>
    _kinds.entries.firstWhere((entry) => entry.value == kind).key;

ExportPlan exportPlanFromJson(JsonMap json) => ExportPlan(
  from: readDate(json, 'from'),
  items: [
    for (final item in readMapList(json, 'items'))
      ExportItem(
        kind: readEnum(item, 'kind', _kinds),
        count: '${readInt(item, 'count')}',
        files: readInt(item, 'files'),
        bytes: readInt(item, 'bytes'),
        selectedByDefault: readBool(item, 'selectedByDefault'),
      ),
  ],
);

ExportRecord exportRecordFromJson(JsonMap json) => ExportRecord(
  id: readString(json, 'id'),
  month: readDate(json, 'month'),
  sentOn: readDate(json, 'sentOn'),
  to: readOptionalString(json, 'to'),
);

final class ApiAccountantExportRepository
    implements AccountantExportRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/accountant-export';

  @override
  Future<Result<ExportPlan>> plan(ExportPeriod period) =>
      guardRequest(() async {
        final response = await _dio.get<Object?>(
          '$path/plan',
          queryParameters: {'period': _periods[period]},
        );
        return exportPlanFromJson(asJsonMap(unwrapData(response.data)));
      });

  @override
  Future<Result<List<ExportRecord>>> history() => guardRequest(() async {
    final response = await _dio.get<Object?>('$path/history');
    return asJsonMapList(unwrapData(response.data))
        .map(exportRecordFromJson)
        .toList();
  });

  @override
  Future<Result<ExportRecord>> generate(
    ExportPeriod period,
    Set<ExportItemKind> items,
  ) => guardRequest(() async {
    final response = await _dio.post<Object?>(
      path,
      data: {
        'period': _periods[period],
        'items': [for (final kind in items) _kindToJson(kind)],
      },
    );
    return exportRecordFromJson(asJsonMap(unwrapData(response.data)));
  });

  @override
  Future<Result<LocalFile>> archive(ExportRecord record) => guardRequest(
    () => downloadFile(
      _dio,
      '$path/${Uri.encodeComponent(record.id)}/download',
      fallbackName: 'contador-${record.month.iso.substring(0, 7)}.zip',
    ),
  );
}
