import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';

void main() {
  test('an unpaid bill past its due date is overdue', () {
    final bill = testBill(dueDate: testToday.addDays(-1));

    expect(bill.isOverdue(testToday), isTrue);
    expect(bill.isOverdue(testToday.addDays(-1)), isFalse);
  });

  test('a paid or cancelled bill is settled and never overdue', () {
    for (final status in [BillStatus.paid, BillStatus.cancelled]) {
      final bill = testBill(status: status, dueDate: testToday.addDays(-5));
      expect(bill.isSettled, isTrue);
      expect(bill.isOverdue(testToday), isFalse);
    }
  });

  test('bills and attempts compare by value', () {
    final attempt = testAttempt(LadderStep.automatic, AttemptOutcome.failed);

    expect(testBill(attempts: [attempt]), testBill(attempts: [attempt]));
    expect(testBill(id: 'a'), isNot(testBill(id: 'b')));
  });

  test('a bill marked paid by hand keeps everything else', () {
    final bill = testBill(
      attempts: [testAttempt(LadderStep.automatic, AttemptOutcome.failed)],
    );

    final paid = bill.markedPaid(testNow);

    expect(paid.status, BillStatus.paid);
    expect(paid.paidAt, testNow);
    expect(paid.paidBy, PaidBy.user);
    expect(paid.attempts, bill.attempts);
    expect(paid.paymentCode, bill.paymentCode);
  });

  test(
    'only a hand payment is undone, and only a bill in no rail is marked',
    () {
      final paid = testBill().markedPaid(testNow);
      final open = paid.markedUnpaid();

      expect(open.status, BillStatus.pending);
      expect(open.paidAt, isNull);
      expect(open.paidBy, isNull);
      expect(open.paymentCode, paid.paymentCode);
      expect(paid.canMarkUnpaid, isTrue);
      expect(paid.canMarkPaid, isFalse);
      expect(open.canMarkPaid, isTrue);
      expect(open.canMarkUnpaid, isFalse);
      expect(testBill(status: BillStatus.scheduled).canMarkPaid, isFalse);
      expect(testBill(status: BillStatus.paid).canMarkUnpaid, isFalse);
    },
  );

  test('tax guides are taxes', () {
    expect(testBill(kind: BillKind.taxBarcode).isTax, isTrue);
    expect(testBill(kind: BillKind.darfNoBarcode).isTax, isTrue);
    expect(testBill().isTax, isFalse);
  });
}
