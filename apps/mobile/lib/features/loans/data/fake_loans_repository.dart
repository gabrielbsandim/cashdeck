import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/loans/domain/loan.dart';

const _amortization = 50_000;
const _monthlyRate = 0.009;
const _monthlyFees = 6_000;

/// Fictional SAC loans in memory, with a rough prepayment estimate so the
/// screens have something to show offline.
final class FakeLoansRepository implements LoansRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 300)});

  final Clock _clock;
  final Duration latency;
  late final Map<String, Loan> _loans = {
    for (final loan in [_seed('loan-home', 'Banco Exemplo 1001', 12)])
      loan.id: loan,
  };

  CalendarDate get _today => CalendarDate.brazilToday(_clock.now());

  LoanInstallment _installment(int number, CalendarDate dueOn, int balance) {
    final interest = (balance * _monthlyRate).round();
    return LoanInstallment(
      number: number,
      dueOn: dueOn,
      total: Money(_amortization + interest + _monthlyFees),
      principal: const Money(_amortization),
      interest: Money(interest),
      fees: const Money(_monthlyFees),
    );
  }

  Loan _seed(String id, String name, int paidCount) {
    const term = 360;
    final balance = (term - paidCount) * _amortization;
    final interest = (balance * _monthlyRate * (term - paidCount) / 2).round();
    final today = _today;
    final first = today.addDays(9);
    final upcoming = [
      for (var index = 0; index < 12; index++)
        _installment(
          paidCount + index + 1,
          first.addDays(index * 30),
          balance - index * _amortization,
        ),
    ];
    return Loan(
      id: id,
      name: name,
      lender: 'Banco Exemplo',
      system: 'SAC',
      indexer: 'TR',
      effectiveRate: 11.5,
      cet: 12.1,
      principal: const Money(term * _amortization),
      propertyValue: const Money(25_000_000),
      termMonths: term,
      paidCount: paidCount,
      balance: Money(balance),
      balanceOn: today.addDays(-3),
      lastDueOn: first.addDays((term - paidCount - 1) * 30),
      next: upcoming.first,
      upcoming: upcoming,
      remaining: LoanRemaining(
        count: term - paidCount,
        total: Money(balance + interest + (term - paidCount) * _monthlyFees),
        interest: Money(interest),
        principal: Money(balance),
        fees: Money((term - paidCount) * _monthlyFees),
      ),
      paid: LoanPaid(
        total: Money(paidCount * 200_000),
        interest: Money(paidCount * 140_000),
        principal: Money(paidCount * _amortization),
        lateFees: const Money(4_210),
      ),
    );
  }

  Future<void> _wait() => Future<void>.delayed(latency);

  @override
  Future<Result<List<Loan>>> list() async {
    await _wait();
    final loans = _loans.values.toList()
      ..sort((a, b) => b.balance.compareTo(a.balance));
    return Ok(loans);
  }

  @override
  Future<Result<Loan>> importStatement(LocalFile file) async {
    await _wait();
    if (file.extension != 'pdf') {
      return const Err(ValidationFailure('The file is not a loan statement.'));
    }
    final loan = _seed('loan-${_loans.length + 1}', 'Banco Exemplo 2002', 3);
    _loans[loan.id] = loan;
    return Ok(loan);
  }

  @override
  Future<Result<Prepayment>> prepayment(String id, Money amount) async {
    await _wait();
    final loan = _loans[id];
    if (loan == null) return const Err(NotFoundFailure());
    final cut = (amount.cents ~/ _amortization).clamp(0, loan.remaining.count);
    final left = loan.remaining.count - cut;
    return Ok(
      Prepayment(
        amount: amount,
        interestSaved: Money((amount.cents * _monthlyRate * left).round()),
        feesSaved: Money(cut * _monthlyFees),
        monthsCut: cut,
        lastDueOn: loan.lastDueOn.addDays(-cut * 30),
        balanceAfter: loan.balance - amount,
      ),
    );
  }

  @override
  Future<Result<void>> delete(String id) async {
    await _wait();
    if (_loans.remove(id) == null) return const Err(NotFoundFailure());
    return const Ok(null);
  }
}
