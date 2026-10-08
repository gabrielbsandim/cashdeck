import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:equatable/equatable.dart';

enum ExportPeriod { lastMonth, lastQuarter, custom }

enum ExportItemKind {
  statements,
  invoices,
  taxGuides,
  expenses,
  payroll,
  reconciliation,
}

final class ExportItem extends Equatable {
  const new({
    required this.kind,
    required this.count,
    required this.files,
    required this.bytes,
    this.selectedByDefault = true,
  });

  final ExportItemKind kind;

  /// What the row shows on the right: accounts, documents or a month.
  final String count;
  final int files;
  final int bytes;
  final bool selectedByDefault;

  @override
  List<Object?> get props => [kind, count, files, bytes, selectedByDefault];
}

/// The company's documents for a period, and the ZIP they add up to.
final class ExportPlan extends Equatable {
  const new({required this.from, required this.items});

  final CalendarDate from;
  final List<ExportItem> items;

  (int files, int bytes) sizeOf(Set<ExportItemKind> selected) {
    var files = 0;
    var bytes = 0;
    for (final item in items) {
      if (!selected.contains(item.kind)) continue;
      files += item.files;
      bytes += item.bytes;
    }
    return (files, bytes);
  }

  @override
  List<Object?> get props => [from, items];
}

final class ExportRecord extends Equatable {
  const new({required this.month, required this.sentOn, required this.to});

  final CalendarDate month;
  final CalendarDate sentOn;
  final String to;

  @override
  List<Object?> get props => [month, sentOn, to];
}

abstract interface class AccountantExportRepository {
  Future<Result<ExportPlan>> plan(ExportPeriod period);

  Future<Result<List<ExportRecord>>> history();

  Future<Result<ExportRecord>> generate(
    ExportPeriod period,
    Set<ExportItemKind> items,
  );
}
