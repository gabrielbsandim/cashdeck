import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:equatable/equatable.dart';

/// One month of payroll: the owner's pro-labore, salaries and FGTS.
final class PayrollMonth extends Equatable {
  const new({
    required this.month,
    required this.proLabore,
    required this.salaries,
    required this.fgts,
  });

  /// The first day of the month.
  final CalendarDate month;
  final Money proLabore;
  final Money salaries;
  final Money fgts;

  Money get total => proLabore + salaries + fgts;

  PayrollMonth copyWith({Money? proLabore, Money? salaries, Money? fgts}) =>
      PayrollMonth(
        month: month,
        proLabore: proLabore ?? this.proLabore,
        salaries: salaries ?? this.salaries,
        fgts: fgts ?? this.fgts,
      );

  @override
  List<Object?> get props => [month, proLabore, salaries, fgts];
}

enum SimplesAnnex { iii, v }

/// Fator R: twelve months of payroll over twelve months of revenue. At 28%
/// or more the service falls in Anexo III of the Simples, else Anexo V.
final class FatorR extends Equatable {
  const new({required this.payroll12, required this.revenue12});

  factory of({
    required PayrollMonth current,
    required List<PayrollMonth> history,
    required Money revenue12,
  }) => FatorR(
    payroll12: history
        .take(11)
        .fold(current.total, (sum, month) => sum + month.total),
    revenue12: revenue12,
  );

  static const threshold = 0.28;

  final Money payroll12;
  final Money revenue12;

  double get ratio =>
      revenue12.cents == 0 ? 0 : payroll12.cents / revenue12.cents;

  SimplesAnnex get annex =>
      ratio >= threshold ? SimplesAnnex.iii : SimplesAnnex.v;

  @override
  List<Object?> get props => [payroll12, revenue12];
}

final class PayrollSheet extends Equatable {
  const new({
    required this.current,
    required this.history,
    required this.revenue12,
  });

  final PayrollMonth current;

  /// Earlier months, most recent first.
  final List<PayrollMonth> history;
  final Money revenue12;

  @override
  List<Object?> get props => [current, history, revenue12];
}

abstract interface class PayrollRepository {
  Future<Result<PayrollSheet>> sheet();

  Future<Result<PayrollSheet>> save(PayrollMonth month);
}
