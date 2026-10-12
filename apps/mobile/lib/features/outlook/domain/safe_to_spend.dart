import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:equatable/equatable.dart';

/// What a line of the breakdown is: something owed before the next income,
/// what a budget of the month still allows, or the share of the bills the
/// reserve already covers.
enum SafeToSpendLineKind { bill, fixed, subscription, card, budget, reserve }

/// One step from the checking balance to the free amount. A deduction is
/// negative; the reserve line is positive.
final class SafeToSpendLine extends Equatable {
  const new({
    required this.kind,
    required this.label,
    required this.amount,
    this.on,
  });

  final SafeToSpendLineKind kind;

  /// The payee, card, fixed payment or budget category; blank when the
  /// server has no name.
  final String label;
  final Money amount;
  final CalendarDate? on;

  @override
  List<Object?> get props => [kind, label, amount, on];
}

final class ExpectedIncome extends Equatable {
  const new({required this.on, required this.amount});

  final CalendarDate on;
  final Money amount;

  @override
  List<Object?> get props => [on, amount];
}

/// How much the person or the company can spend each day until the next
/// income without touching what is already owed. The server decides every
/// figure.
final class SafeToSpend extends Equatable {
  const new({
    required this.asOf,
    required this.cash,
    required this.total,
    required this.daily,
    required this.days,
    required this.until,
    required this.shortBy,
    this.income,
    this.lines = const [],
  });

  final CalendarDate asOf;

  /// The checking balance the breakdown starts from.
  final Money cash;
  final Money total;
  final Money daily;
  final int days;

  /// The income day, or the month end when no income is known.
  final CalendarDate until;
  final Money shortBy;
  final ExpectedIncome? income;
  final List<SafeToSpendLine> lines;

  bool get isShort => shortBy.cents > 0;

  @override
  List<Object?> get props => [
    asOf,
    cash,
    total,
    daily,
    days,
    until,
    shortBy,
    income,
    lines,
  ];
}
