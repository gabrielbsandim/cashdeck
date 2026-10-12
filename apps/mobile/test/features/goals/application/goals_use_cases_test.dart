import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/goals/application/goals_use_cases.dart';
import 'package:cashdeck/features/goals/domain/goal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/builders.dart';
import '../goal_builders.dart';

final class MockGoalsRepository extends Mock implements GoalsRepository;

const _draft = GoalDraft(name: 'Reserva', target: Money(10_000));

void main() {
  late MockGoalsRepository repository;

  setUpAll(() {
    registerFallbackValue(_draft);
    registerFallbackValue(const Money(0));
  });

  setUp(() => repository = MockGoalsRepository());

  test('each use case forwards to the repository', () async {
    final goal = goalAt(40);
    when(repository.list).thenAnswer((_) async => Ok([goal]));
    when(() => repository.get('goal-1')).thenAnswer((_) async => Ok(goal));
    when(() => repository.create(_draft)).thenAnswer((_) async => Ok(goal));
    when(() => repository.update('goal-1', _draft))
        .thenAnswer((_) async => Ok(goal));
    when(() => repository.archive('goal-1')).thenAnswer((_) async => Ok(goal));
    when(() => repository.delete('goal-1'))
        .thenAnswer((_) async => const Ok(null));
    when(
      () => repository.contribute(
        'goal-1',
        const Money(-500),
        note: any(named: 'note'),
      ),
    ).thenAnswer((_) async => Ok(goal));
    when(() => repository.removeContribution('goal-1', 'c1'))
        .thenAnswer((_) async => Ok(goal));

    expect(await ListGoals(repository).call(), Ok([goal]));
    expect(await GetGoal(repository).call('goal-1'), Ok(goal));
    expect(await SaveGoal(repository).call(_draft, today: testToday), Ok(goal));
    expect(
      await SaveGoal(repository).call(_draft, today: testToday, id: 'goal-1'),
      Ok(goal),
    );
    expect(await ArchiveGoal(repository).call('goal-1'), Ok(goal));
    expect(await DeleteGoal(repository).call('goal-1'), const Ok<void>(null));
    expect(
      await ContributeToGoal(repository)
          .call('goal-1', const Money(-500), note: '  Saque '),
      Ok(goal),
    );
    expect(
      await ContributeToGoal(repository)
          .call('goal-1', const Money(-500), note: '  '),
      Ok(goal),
    );
    expect(
      await ContributeToGoal(repository).call('goal-1', const Money(-500)),
      Ok(goal),
    );
    expect(await RemoveContribution(repository).call('goal-1', 'c1'), Ok(goal));
    verify(
      () => repository.contribute('goal-1', const Money(-500), note: 'Saque'),
    ).called(1);
    verify(() => repository.contribute('goal-1', const Money(-500))).called(2);
  });

  test('a broken draft or a zero amount never reaches the server', () async {
    expect(
      await SaveGoal(repository).call(
        const GoalDraft(name: '', target: Money(10_000)),
        today: testToday,
      ),
      const Err<Goal>(UnexpectedFailure()),
    );
    expect(
      await ContributeToGoal(repository).call('goal-1', const Money(0)),
      const Err<Goal>(UnexpectedFailure()),
    );
    verifyZeroInteractions(repository);
  });
}
