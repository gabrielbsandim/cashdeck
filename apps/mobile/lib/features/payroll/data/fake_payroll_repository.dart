import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/payroll/domain/payroll.dart';

/// Eleven earlier months at the same payroll, the current one open.
final class FakePayrollRepository implements PayrollRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 300)});

  final Clock _clock;
  final Duration latency;
  PayrollMonth? _saved;

  static CalendarDate _monthsBack(CalendarDate first, int months) {
    final index = first.year * 12 + first.month - 1 - months;
    return CalendarDate(index ~/ 12, index % 12 + 1, 1);
  }

  static PayrollMonth _standard(CalendarDate month) => PayrollMonth(
    month: month,
    proLabore: const Money(600_000),
    salaries: const Money(125_000),
    fgts: const Money(10_000),
  );

  PayrollSheet _sheet() {
    final today = CalendarDate.brazilToday(_clock.now());
    final first = CalendarDate(today.year, today.month, 1);
    return PayrollSheet(
      current: _saved ?? _standard(first),
      history: [
        for (var back = 1; back <= 11; back++)
          _standard(_monthsBack(first, back)),
      ],
      revenue12: const Money(28_740_000),
    );
  }

  @override
  Future<Result<PayrollSheet>> sheet() async {
    await Future<void>.delayed(latency);
    return Ok(_sheet());
  }

  @override
  Future<Result<PayrollSheet>> save(PayrollMonth month) async {
    await Future<void>.delayed(latency);
    _saved = month;
    return Ok(_sheet());
  }
}
