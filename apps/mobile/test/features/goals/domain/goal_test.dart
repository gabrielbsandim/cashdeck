import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/goals/domain/goal.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';
import '../goal_builders.dart';

void main() {
  test('a goal knows its fraction, whether it is done and takes money', () {
    final half = goalAt(50);
    expect(half.fraction, 0.5);
    expect(half.isDone, isFalse);
    expect(half.takesContributions, isTrue);
    expect(goalAt(100).isDone, isTrue);
    expect(goalAt(10, source: GoalSource.account).takesContributions, isFalse);
    expect(half, goalAt(50));
    const contribution = GoalContribution(
      id: 'c1',
      amount: Money(-500),
      on: testToday,
      note: 'Saque',
    );
    expect(
      contribution,
      isNot(
        const GoalContribution(id: 'c1', amount: Money(500), on: testToday),
      ),
    );
  });

  test('only the change that crosses the target is celebrated', () {
    expect(justReached(goalAt(90), goalAt(100)), isTrue);
    expect(justReached(goalAt(100), goalAt(100)), isFalse);
    expect(justReached(goalAt(40), goalAt(60)), isFalse);
    expect(justReached(null, goalAt(100)), isFalse);
  });

  test('a draft names the first rule it breaks', () {
    const valid = GoalDraft(name: 'Reserva', target: Money(10_000));
    expect(valid.problemOn(testToday), isNull);
    expect(
      const GoalDraft(name: ' ', target: Money(10_000)).problemOn(testToday),
      GoalProblem.nameMissing,
    );
    expect(
      const GoalDraft(name: 'Reserva', target: Money(0)).problemOn(testToday),
      GoalProblem.targetMissing,
    );
    expect(
      GoalDraft(
        name: 'Reserva',
        target: const Money(10_000),
        deadline: testToday.addDays(-1),
      ).problemOn(testToday),
      GoalProblem.deadlinePast,
    );
    expect(
      const GoalDraft(
        name: 'Reserva',
        target: Money(10_000),
        deadline: CalendarDate(2027, 1, 1),
      ).problemOn(testToday),
      isNull,
    );
    expect(valid, isNot(GoalDraft(name: 'Reserva', target: goalAt(1).target)));
  });
}
