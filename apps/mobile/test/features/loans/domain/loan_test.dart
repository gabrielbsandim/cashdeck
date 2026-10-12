import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/features/loans/domain/loan.dart';
import 'package:flutter_test/flutter_test.dart';

import '../loan_builders.dart';

void main() {
  test('progress is the share of the term paid, never past the end', () {
    expect(loanWith(paidCount: 105).progress, 0.25);
    expect(loanWith(paidCount: 500).progress, 1);
    expect(loanWith(termMonths: 0).progress, 0);
  });

  test('a loan paid late says so', () {
    expect(loanWith().paidLate, isFalse);
    expect(loanWith(lateFees: 9_300).paidLate, isTrue);
  });

  test('a prepayment saves its interest and fees together', () {
    expect(testPrepayment.saved, const Money(3_790_000));
  });

  test('values compare by their fields', () {
    expect(loanWith(), loanWith());
    expect(loanWith(lateFees: 1), isNot(loanWith()));
    LoanRemaining remaining(int count) => LoanRemaining(
      count: count,
      total: const Money(1),
      interest: const Money(1),
      principal: const Money(1),
      fees: const Money(1),
    );
    expect(remaining(2), remaining(2));
    expect(remaining(2), isNot(remaining(3)));
    expect(loanWith().paid, loanWith().paid);
    expect(testInstallment, loanWith().next);
    expect(testPrepayment, testPrepayment);
    expect(testPrepayment.props, hasLength(6));
  });
}
