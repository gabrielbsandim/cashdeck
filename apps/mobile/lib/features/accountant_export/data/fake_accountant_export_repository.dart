import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/accountant_export/domain/accountant_export.dart';

final class FakeAccountantExportRepository
    implements AccountantExportRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 300)});

  final Clock _clock;
  final Duration latency;
  static const accountant = 'contabilidade@exemplo.com';
  final List<ExportRecord> _sent = [];

  CalendarDate get _today => CalendarDate.brazilToday(_clock.now());

  CalendarDate _monthStart(int back) {
    final index = _today.year * 12 + _today.month - 1 - back;
    return CalendarDate(index ~/ 12, index % 12 + 1, 1);
  }

  @override
  Future<Result<ExportPlan>> plan(ExportPeriod period) async {
    await Future<void>.delayed(latency);
    final scale = switch (period) {
      ExportPeriod.lastMonth || ExportPeriod.custom => 1,
      ExportPeriod.lastQuarter => 3,
    };
    final month = _monthStart(1);
    return Ok(
      ExportPlan(
        from: switch (period) {
          ExportPeriod.lastQuarter => _monthStart(3),
          ExportPeriod.lastMonth || ExportPeriod.custom => month,
        },
        items: [
          ExportItem(
            kind: ExportItemKind.statements,
            count: '2',
            files: 2 * scale,
            bytes: 400_000 * scale,
          ),
          ExportItem(
            kind: ExportItemKind.invoices,
            count: '${6 * scale}',
            files: 12 * scale,
            bytes: 2_400_000 * scale,
          ),
          ExportItem(
            kind: ExportItemKind.taxGuides,
            count: '${3 * scale}',
            files: 6 * scale,
            bytes: 1_200_000 * scale,
          ),
          ExportItem(
            kind: ExportItemKind.expenses,
            count: '${41 * scale}',
            files: 190 * scale,
            bytes: 33_000_000 * scale,
          ),
          ExportItem(
            kind: ExportItemKind.payroll,
            count: '${month.month.toString().padLeft(2, '0')}/${month.year}',
            files: 4 * scale,
            bytes: 1_000_000 * scale,
          ),
          const ExportItem(
            kind: ExportItemKind.reconciliation,
            count: '1',
            files: 1,
            bytes: 80_000,
            selectedByDefault: false,
          ),
        ],
      ),
    );
  }

  @override
  Future<Result<List<ExportRecord>>> history() async {
    await Future<void>.delayed(latency);
    return Ok([
      ..._sent.reversed,
      ExportRecord(
        month: _monthStart(2),
        sentOn: CalendarDate(_monthStart(1).year, _monthStart(1).month, 5),
        to: accountant,
      ),
    ]);
  }

  @override
  Future<Result<ExportRecord>> generate(
    ExportPeriod period,
    Set<ExportItemKind> items,
  ) async {
    await Future<void>.delayed(latency);
    if (items.isEmpty) return const Err(ValidationFailure('items'));
    final record = ExportRecord(
      month: _monthStart(1),
      sentOn: _today,
      to: accountant,
    );
    _sent.add(record);
    return Ok(record);
  }
}
