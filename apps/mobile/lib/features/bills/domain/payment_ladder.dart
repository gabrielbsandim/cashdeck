import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:equatable/equatable.dart';

enum LadderStepState { done, active, failed, upcoming, skipped, unavailable }

final class LadderStepStatus extends Equatable {
  const new({required this.step, required this.state, required this.attempts});

  final LadderStep step;
  final LadderStepState state;

  /// The attempts made on this step, oldest first.
  final List<PaymentAttempt> attempts;

  @override
  List<Object?> get props => [step, state, attempts];
}

/// The step a bill is on: the first one in its plan that has not failed.
/// Null once the bill is paid or cancelled.
LadderStep? currentStepOf(Bill bill) {
  if (bill.isSettled) return null;
  for (final step in bill.plan) {
    if (_lastOutcome(bill, step) != AttemptOutcome.failed) return step;
  }
  return bill.plan.lastOrNull;
}

/// Every step of the ladder, including the ones this bill's plan lacks.
List<LadderStepStatus> ladderOf(Bill bill) {
  final current = currentStepOf(bill);
  return [
    for (final step in LadderStep.values)
      LadderStepStatus(
        step: step,
        state: _stateOf(bill, step, current),
        attempts: [
          for (final attempt in bill.attempts)
            if (attempt.step == step) attempt,
        ],
      ),
  ];
}

LadderStepState _stateOf(Bill bill, LadderStep step, LadderStep? current) {
  if (!bill.plan.contains(step)) return LadderStepState.unavailable;
  final outcome = _lastOutcome(bill, step);
  if (outcome == AttemptOutcome.succeeded) return LadderStepState.done;
  if (outcome == AttemptOutcome.failed) return LadderStepState.failed;
  if (step == current) return LadderStepState.active;
  if (current == null) return LadderStepState.skipped;
  return LadderStepState.upcoming;
}

AttemptOutcome? _lastOutcome(Bill bill, LadderStep step) =>
    bill.attempts.where((attempt) => attempt.step == step).lastOrNull?.outcome;
