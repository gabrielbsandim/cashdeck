import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/goals/domain/goal.dart';

final class _Stored {
  new({
    required this.id,
    required this.draft,
    this.linked,
    this.pace,
    List<GoalContribution>? contributions,
  }) : contributions = contributions ?? [];

  final String id;
  GoalDraft draft;
  final (String name, Money balance)? linked;
  final Money? pace;
  bool archived = false;
  final List<GoalContribution> contributions;
}

/// Fictional goals in memory, with a rough version of the server's
/// projection so the screens have something to show offline.
final class FakeGoalsRepository implements GoalsRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 300)});

  final Clock _clock;
  final Duration latency;
  var _counter = 0;
  late final Map<String, _Stored> _goals = {
    for (final goal in _seed()) goal.id: goal,
  };

  CalendarDate get _today => CalendarDate.brazilToday(_clock.now());

  List<_Stored> _seed() {
    final today = _today;
    return [
      _Stored(
        id: 'goal-reserve',
        draft: GoalDraft(
          name: 'Reserva de emergência',
          target: const Money(3_000_000),
          deadline: today.addDays(270),
          icon: 'shield',
          color: 'teal',
        ),
        pace: const Money(150_000),
        contributions: [
          GoalContribution(
            id: 'goal-reserve-1',
            amount: const Money(1_200_000),
            on: today.addDays(-120),
          ),
          GoalContribution(
            id: 'goal-reserve-2',
            amount: const Money(650_000),
            on: today.addDays(-20),
            note: 'Décimo terceiro',
          ),
        ],
      ),
      _Stored(
        id: 'goal-trip',
        draft: GoalDraft(
          name: 'Viagem de férias',
          target: const Money(1_200_000),
          deadline: today.addDays(120),
          accountId: 'acc-pf-checking',
          icon: 'flight',
          color: 'blue',
        ),
        linked: ('Corrente Aurora ••4410', const Money(482_015)),
        pace: const Money(80_000),
      ),
      _Stored(
        id: 'goal-laptop',
        draft: const GoalDraft(name: 'Notebook novo', target: Money(600_000)),
        pace: const Money(60_000),
        contributions: [
          GoalContribution(
            id: 'goal-laptop-1',
            amount: const Money(540_000),
            on: today.addDays(-45),
          ),
        ],
      ),
    ];
  }

  GoalSource _sourceOf(GoalDraft draft) {
    if (draft.accountId != null) return GoalSource.account;
    if (draft.investmentId != null) return GoalSource.investment;
    return GoalSource.manual;
  }

  Goal _view(_Stored stored, {bool detail = true}) {
    final draft = stored.draft;
    final saved =
        stored.linked?.$2 ??
        stored.contributions.fold<Money>(
          const Money(0),
          (sum, c) => sum + c.amount,
        );
    final target = draft.target;
    final missing = target.cents - saved.cents;
    final remaining = Money(missing < 0 ? 0 : missing);
    final percent = (saved.cents * 100 ~/ target.cents).clamp(0, 100);
    final pace = stored.pace;
    final projected = pace == null || remaining.cents == 0
        ? null
        : _today.addDays((remaining.cents / pace.cents * 30.4375).ceil());
    final deadline = draft.deadline;
    final months = deadline == null
        ? null
        : (_today.daysUntil(deadline) / 30.4375).ceil().clamp(1, 1200);
    final status = switch ((remaining.cents, deadline, projected)) {
      (0, _, _) => GoalStatus.done,
      (_, final CalendarDate ends, final CalendarDate on)
          when ends.isBefore(on) =>
        GoalStatus.behind,
      _ => GoalStatus.onTrack,
    };
    final sorted = [...stored.contributions]
      ..sort((a, b) => b.on.compareTo(a.on));
    return Goal(
      id: stored.id,
      name: draft.name,
      target: target,
      saved: saved,
      remaining: remaining,
      percent: percent,
      status: status,
      source: _sourceOf(draft),
      deadline: deadline,
      requiredMonthly: months == null
          ? null
          : Money((remaining.cents / months).ceil()),
      monthlyPace: pace,
      projectedOn: projected,
      accountId: draft.accountId,
      investmentId: draft.investmentId,
      linkedName: stored.linked?.$1,
      icon: draft.icon,
      color: draft.color,
      archived: stored.archived,
      contributions: detail ? sorted : const [],
    );
  }

  Future<Result<Goal>> _found(
    String id,
    Goal Function(_Stored stored) change,
  ) async {
    await Future<void>.delayed(latency);
    final stored = _goals[id];
    if (stored == null) return const Err(NotFoundFailure());
    return Ok(change(stored));
  }

  @override
  Future<Result<List<Goal>>> list() async {
    await Future<void>.delayed(latency);
    return Ok([
      for (final stored in _goals.values)
        if (!stored.archived) _view(stored, detail: false),
    ]);
  }

  @override
  Future<Result<Goal>> get(String id) => _found(id, _view);

  @override
  Future<Result<Goal>> create(GoalDraft draft) async {
    await Future<void>.delayed(latency);
    final id = 'goal-new-${++_counter}';
    final linked = draft.isManual ? null : ('Vinculada', const Money(0));
    final stored = _Stored(id: id, draft: draft, linked: linked);
    if (linked == null && draft.initial.cents > 0) {
      stored.contributions.add(
        GoalContribution(id: '$id-initial', amount: draft.initial, on: _today),
      );
    }
    _goals[id] = stored;
    return Ok(_view(stored));
  }

  @override
  Future<Result<Goal>> update(String id, GoalDraft draft) =>
      _found(id, (stored) {
        stored.draft = draft;
        return _view(stored);
      });

  @override
  Future<Result<Goal>> archive(String id) => _found(id, (stored) {
    stored.archived = true;
    return _view(stored);
  });

  @override
  Future<Result<void>> delete(String id) async {
    await Future<void>.delayed(latency);
    final removed = _goals.remove(id);
    if (removed == null) return const Err(NotFoundFailure());
    return const Ok(null);
  }

  @override
  Future<Result<Goal>> contribute(String id, Money amount, {String? note}) =>
      _found(id, (stored) {
        stored.contributions.add(
          GoalContribution(
            id: '$id-${++_counter}',
            amount: amount,
            on: _today,
            note: note,
          ),
        );
        return _view(stored);
      });

  @override
  Future<Result<Goal>> removeContribution(String id, String contributionId) =>
      _found(id, (stored) {
        stored.contributions.removeWhere((c) => c.id == contributionId);
        return _view(stored);
      });
}
