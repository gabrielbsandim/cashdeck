import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/features/goals/domain/goal.dart';

Goal goalAt(int percent, {GoalSource source = GoalSource.manual}) => Goal(
  id: 'goal-1',
  name: 'Viagem',
  target: const Money(100_000),
  saved: Money(percent * 1_000),
  remaining: Money((100 - percent) * 1_000),
  percent: percent,
  status: percent >= 100 ? GoalStatus.done : GoalStatus.onTrack,
  source: source,
);
