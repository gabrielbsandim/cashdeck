import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:equatable/equatable.dart';

/// What a line of the breakdown is: a step of the monthly plan (the typical
/// income, the savings target, what the month spent on cards and from the
/// accounts), something still owed, what a budget of the month still allows,
/// or the share of the bills the reserve already covers.
enum SafeToSpendLineKind {
  income,
  savings,
  spentCard,
  spentAccount,
  bill,
  fixed,
  subscription,
  card,
  budget,
  reserve,
}

/// Where the breakdown starts: a person's typical month, which lasts to the
/// month end, or the checking balance, which lasts until the next income.
enum SafeToSpendBasis { month, cash }

/// The month the plan starts from.
final class SpendingPlan extends Equatable {
  const new({
    required this.income,
    required this.savings,
    required this.savingsSet,
    required this.months,
    Money? typical,
    this.received = const Money(0),
    this.sources = 0,
  }) : typical = typical ?? income;

  /// The larger of the typical income and what already came in this month.
  final Money income;

  /// The median income of the closed months read.
  final Money typical;
  final Money received;
  final Money savings;

  /// False while the target is what a typical month leaves over.
  final bool savingsSet;
  final int months;

  /// Payers chosen as income; none means every credit not own money.
  final int sources;

  bool get fromReceived =>
      received.cents > 0 && received.cents >= typical.cents;

  @override
  List<Object?> get props => [
    income,
    typical,
    received,
    savings,
    savingsSet,
    months,
    sources,
  ];
}

/// A payer counted as income, known by its CPF or CNPJ digits.
final class IncomeSource extends Equatable {
  const new({required this.taxId, required this.name});

  final String taxId;
  final String name;

  @override
  List<Object?> get props => [taxId, name];
}

/// A payer of the last six months the person can count as income.
final class IncomeSourceCandidate extends Equatable {
  const new({
    required this.source,
    required this.total,
    required this.months,
    required this.lastOn,
    required this.selected,
  });

  final IncomeSource source;
  final Money total;
  final int months;
  final CalendarDate lastOn;
  final bool selected;

  @override
  List<Object?> get props => [source, total, months, lastOn, selected];
}

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

/// How much the person can still spend this month, or the company until its
/// next income, without touching what is already owed. The server decides
/// every figure.
final class SafeToSpend extends Equatable {
  const new({
    required this.asOf,
    required this.cash,
    required this.total,
    required this.daily,
    required this.days,
    required this.until,
    required this.shortBy,
    this.basis = SafeToSpendBasis.cash,
    this.income,
    this.plan,
    this.cashShortBy = const Money(0),
    this.lines = const [],
  });

  final CalendarDate asOf;

  /// The checking balance the breakdown starts from.
  final Money cash;
  final Money total;
  final Money daily;
  final int days;

  /// The month end, or on cash the income day when one is known.
  final CalendarDate until;
  final Money shortBy;
  final SafeToSpendBasis basis;
  final ExpectedIncome? income;
  final SpendingPlan? plan;

  /// What checking and the reserve miss of what falls due in 30 days.
  final Money cashShortBy;
  final List<SafeToSpendLine> lines;

  bool get isShort => shortBy.cents > 0;

  bool get isCashShort => cashShortBy.cents > 0;

  @override
  List<Object?> get props => [
    asOf,
    cash,
    total,
    daily,
    days,
    until,
    shortBy,
    basis,
    income,
    plan,
    cashShortBy,
    lines,
  ];
}
