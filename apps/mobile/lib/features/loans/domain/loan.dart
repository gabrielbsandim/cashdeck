import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:equatable/equatable.dart';

/// One monthly installment as the bank's schedule splits it.
final class LoanInstallment extends Equatable {
  const new({
    required this.number,
    required this.dueOn,
    required this.total,
    required this.principal,
    required this.interest,
    required this.fees,
  });

  final int number;
  final CalendarDate dueOn;
  final Money total;
  final Money principal;
  final Money interest;

  /// Insurance and the bank's monthly fee.
  final Money fees;

  @override
  List<Object?> get props => [number, dueOn, total, principal, interest, fees];
}

/// What the installments still ahead add up to.
final class LoanRemaining extends Equatable {
  const new({
    required this.count,
    required this.total,
    required this.interest,
    required this.principal,
    required this.fees,
  });

  final int count;
  final Money total;
  final Money interest;
  final Money principal;
  final Money fees;

  @override
  List<Object?> get props => [count, total, interest, principal, fees];
}

/// What the installments already paid added up to.
final class LoanPaid extends Equatable {
  const new({
    required this.total,
    required this.interest,
    required this.principal,
    required this.lateFees,
  });

  final Money total;
  final Money interest;
  final Money principal;

  /// Fines and interest for paying after the due date.
  final Money lateFees;

  @override
  List<Object?> get props => [total, interest, principal, lateFees];
}

/// A financing read from the bank's statement, with its schedule summed up.
final class Loan extends Equatable {
  const new({
    required this.id,
    required this.name,
    required this.lender,
    required this.system,
    required this.indexer,
    required this.effectiveRate,
    required this.cet,
    required this.principal,
    required this.termMonths,
    required this.paidCount,
    required this.balance,
    required this.remaining,
    required this.paid,
    this.lastDueOn,
    this.propertyValue,
    this.next,
    this.upcoming = const [],
  });

  final String id;
  final String name;
  final String lender;

  /// SAC or Price.
  final String system;
  final String indexer;

  /// Percent per year.
  final double effectiveRate;
  final double cet;
  final Money principal;
  final Money? propertyValue;
  final int termMonths;
  final int paidCount;
  final Money balance;

  /// Null once every installment is paid.
  final CalendarDate? lastDueOn;
  final LoanInstallment? next;
  final List<LoanInstallment> upcoming;
  final LoanRemaining remaining;
  final LoanPaid paid;

  /// Share of the term already paid, from 0 to 1.
  double get progress =>
      termMonths <= 0 ? 0 : (paidCount / termMonths).clamp(0, 1).toDouble();

  bool get paidLate => paid.lateFees.cents > 0;

  @override
  List<Object?> get props => [
    id,
    name,
    lender,
    system,
    indexer,
    effectiveRate,
    cet,
    principal,
    propertyValue,
    termMonths,
    paidCount,
    balance,
    lastDueOn,
    next,
    upcoming,
    remaining,
    paid,
  ];
}

/// An extra payment that keeps the installment and cuts the term.
final class Prepayment extends Equatable {
  const new({
    required this.amount,
    required this.interestSaved,
    required this.feesSaved,
    required this.monthsCut,
    required this.balanceAfter,
    this.lastDueOn,
  });

  final Money amount;
  final Money interestSaved;
  final Money feesSaved;
  final int monthsCut;

  /// Null when the prepayment pays the loan off.
  final CalendarDate? lastDueOn;
  final Money balanceAfter;

  Money get saved => interestSaved + feesSaved;

  @override
  List<Object?> get props => [
    amount,
    interestSaved,
    feesSaved,
    monthsCut,
    lastDueOn,
    balanceAfter,
  ];
}

abstract interface class LoansRepository {
  /// The person's loans, largest balance first.
  Future<Result<List<Loan>>> list();

  /// Reads the bank's statement PDF; importing it again refreshes the loan.
  Future<Result<Loan>> importStatement(LocalFile file);

  Future<Result<Prepayment>> prepayment(String id, Money amount);

  Future<Result<void>> delete(String id);
}
