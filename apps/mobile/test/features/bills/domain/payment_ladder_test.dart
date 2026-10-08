import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/bills/domain/payment_ladder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';

List<LadderStepState> _states(Bill bill) => [
  for (final status in ladderOf(bill)) status.state,
];

void main() {
  test('a fresh bill sits on the first step of its plan', () {
    final bill = testBill();

    expect(currentStepOf(bill), LadderStep.automatic);
    expect(_states(bill), [
      LadderStepState.active,
      LadderStepState.upcoming,
      LadderStepState.upcoming,
    ]);
  });

  test('a failure moves the bill one step down', () {
    final bill = testBill(
      status: BillStatus.awaitingApproval,
      attempts: [
        testAttempt(LadderStep.automatic, AttemptOutcome.failed),
        testAttempt(LadderStep.bankApproval, AttemptOutcome.waiting),
      ],
    );

    expect(currentStepOf(bill), LadderStep.bankApproval);
    expect(_states(bill), [
      LadderStepState.failed,
      LadderStepState.active,
      LadderStepState.upcoming,
    ]);
    expect(ladderOf(bill).first.attempts, hasLength(1));
  });

  test('steps outside the plan are unavailable', () {
    final bill = testBill(
      plan: const [LadderStep.automatic, LadderStep.assisted],
      attempts: [testAttempt(LadderStep.automatic, AttemptOutcome.failed)],
    );

    expect(currentStepOf(bill), LadderStep.assisted);
    expect(_states(bill), [
      LadderStepState.failed,
      LadderStepState.unavailable,
      LadderStepState.active,
    ]);
  });

  test('once paid, the remaining steps were not needed', () {
    final bill = testBill(
      status: BillStatus.paid,
      attempts: [testAttempt(LadderStep.automatic, AttemptOutcome.succeeded)],
    );

    expect(currentStepOf(bill), isNull);
    expect(_states(bill), [
      LadderStepState.done,
      LadderStepState.skipped,
      LadderStepState.skipped,
    ]);
  });

  test('a plan that failed everywhere stays on its last step', () {
    final bill = testBill(
      plan: const [LadderStep.automatic],
      attempts: [testAttempt(LadderStep.automatic, AttemptOutcome.failed)],
    );

    expect(currentStepOf(bill), LadderStep.automatic);
  });

  test('step statuses compare by value', () {
    final bill = testBill();
    expect(ladderOf(bill), ladderOf(bill));
  });
}
