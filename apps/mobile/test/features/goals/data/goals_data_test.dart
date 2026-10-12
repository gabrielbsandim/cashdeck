import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/goals/data/api_goals_repository.dart';
import 'package:cashdeck/features/goals/data/fake_goals_repository.dart';
import 'package:cashdeck/features/goals/data/goal_dtos.dart';
import 'package:cashdeck/features/goals/domain/goal.dart';
import 'package:cashdeck/features/goals/goals_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';
import '../../../support/stub_http_adapter.dart';

T _ok<T>(Result<T> result) => (result as Ok<T>).value;

Map<String, dynamic> _money(int cents) => {'cents': cents, 'currency': 'BRL'};

Map<String, dynamic> goalJson({
  String id = 'goal-1',
  String status = 'ON_TRACK',
  Object? deadline = '2027-06-30',
  Object? pace = 50_000,
}) => {
  'id': id,
  'entity': 'PF',
  'name': 'Reserva',
  'icon': null,
  'color': null,
  'target': _money(300_000),
  'saved': _money(120_000),
  'remaining': _money(180_000),
  'percent': 40,
  'status': status,
  'deadline': deadline,
  'requiredMonthly': deadline == null ? null : _money(20_000),
  'monthlyPace': pace == null ? null : _money(pace as int),
  'projectedOn': pace == null ? null : '2027-02-01',
  'source': 'MANUAL',
  'accountId': null,
  'investmentId': null,
  'linkedName': null,
  'createdAt': '2026-09-01T12:00:00.000Z',
  'archivedAt': null,
  'contributions': [
    {
      'id': 'c1',
      'amount': _money(-5_000),
      'on': '2026-10-01',
      'note': 'Saque',
      'createdAt': '2026-10-01T12:00:00.000Z',
    },
  ],
};

void main() {
  group('dtos', () {
    test('read a goal with its projection and contributions', () {
      final goal = goalFromJson(goalJson());
      expect(goal.status, GoalStatus.onTrack);
      expect(goal.source, GoalSource.manual);
      expect(goal.deadline, const CalendarDate(2027, 6, 30));
      expect(goal.requiredMonthly, const Money(20_000));
      expect(goal.monthlyPace, const Money(50_000));
      expect(goal.projectedOn, const CalendarDate(2027, 2, 1));
      expect(goal.contributions.single.amount, const Money(-5_000));
      expect(goal.archived, isFalse);

      final open = goalFromJson(
        goalJson(status: 'BEHIND', deadline: null, pace: null),
      );
      expect(open.status, GoalStatus.behind);
      expect(open.deadline, isNull);
      expect(open.requiredMonthly, isNull);
      expect(open.monthlyPace, isNull);
      expect(
        goalFromJson({
          ...goalJson(status: 'DONE'),
          'source': 'INVESTMENT',
          'archivedAt': '2026-10-08T12:00:00.000Z',
        }),
        isA<Goal>()
            .having((goal) => goal.status, 'status', GoalStatus.done)
            .having((goal) => goal.source, 'source', GoalSource.investment)
            .having((goal) => goal.archived, 'archived', isTrue),
      );
      expect(
        goalFromJson({...goalJson(), 'source': 'ACCOUNT'}).source,
        GoalSource.account,
      );
    });

    test('an investment link, icon and colour travel both ways', () {
      final goal = goalFromJson({
        ...goalJson(),
        'source': 'INVESTMENT',
        'investmentId': 'inv-1',
        'icon': 'flight',
        'color': 'teal',
      });
      expect(goal.investmentId, 'inv-1');
      expect(goal.icon, 'flight');
      expect(goal.color, 'teal');
      const draft = GoalDraft(
        name: 'Viagem',
        target: Money(100),
        investmentId: 'inv-1',
        icon: 'flight',
        color: 'teal',
        initial: Money(10),
      );
      expect(draft.isManual, isFalse);
      expect(goalCreateToJson(draft), {
        'entity': 'PF',
        'name': 'Viagem',
        'targetCents': 100,
        'investmentId': 'inv-1',
        'icon': 'flight',
        'color': 'teal',
      });
      expect(goalUpdateToJson(draft), {
        'name': 'Viagem',
        'targetCents': 100,
        'deadline': null,
        'accountId': null,
        'investmentId': 'inv-1',
        'icon': 'flight',
        'color': 'teal',
      });
    });

    test('a draft travels trimmed; an update clears what was removed', () {
      const draft = GoalDraft(
        name: ' Reserva ',
        target: Money(300_000),
        deadline: CalendarDate(2027, 6, 30),
        initial: Money(10_000),
      );
      expect(goalCreateToJson(draft), {
        'entity': 'PF',
        'name': 'Reserva',
        'targetCents': 300_000,
        'deadline': '2027-06-30',
        'initialCents': 10_000,
      });
      expect(
        goalCreateToJson(
          const GoalDraft(
            name: 'Viagem',
            target: Money(100),
            accountId: 'acc-1',
            initial: Money(10),
          ),
        ),
        {
          'entity': 'PF',
          'name': 'Viagem',
          'targetCents': 100,
          'accountId': 'acc-1',
        },
      );
      expect(
        goalUpdateToJson(const GoalDraft(name: 'Viagem', target: Money(100))),
        {
          'name': 'Viagem',
          'targetCents': 100,
          'deadline': null,
          'accountId': null,
          'investmentId': null,
          'icon': null,
          'color': null,
        },
      );
    });
  });

  test('the api reads and changes goals', () async {
    final dio = stubDio((options) {
      final key = '${options.method} ${options.path}';
      final body = {'data': goalJson()};
      return switch (key) {
        'GET /api/v1/goals' => StubResponse(200, {
          'data': [goalJson()],
        }),
        'DELETE /api/v1/goals/goal-1' => const StubResponse(200, {
          'data': {'id': 'goal-1'},
        }),
        'POST /api/v1/goals' ||
        'POST /api/v1/goals/goal-1/contributions' => StubResponse(201, body),
        _ => StubResponse(200, body),
      };
    });
    final repository = ApiGoalsRepository(dio);
    const draft = GoalDraft(name: 'Reserva', target: Money(300_000));

    expect(_ok(await repository.list()).single.id, 'goal-1');
    expect(_ok(await repository.get('goal-1')).name, 'Reserva');
    expect(_ok(await repository.create(draft)).id, 'goal-1');
    expect(_ok(await repository.update('goal-1', draft)).id, 'goal-1');
    expect(_ok(await repository.archive('goal-1')).id, 'goal-1');
    expect(await repository.delete('goal-1'), isA<Ok<void>>());
    expect(
      _ok(
        await repository.contribute('goal-1', const Money(500), note: 'Bônus'),
      ).id,
      'goal-1',
    );
    expect(
      _ok(await repository.removeContribution('goal-1', 'c 1')).id,
      'goal-1',
    );
    final requests = adapterOf(dio).requests;
    expect(requests.first.queryParameters, {'entity': 'PF'});
    expect(requests[4].data, {'archived': true});
    expect(requests[6].data, {'amountCents': 500, 'note': 'Bônus'});
    expect(requests.last.path, '/api/v1/goals/goal-1/contributions/c%201');
  });

  group('fake', () {
    late FakeGoalsRepository repository;

    setUp(
      () => repository = FakeGoalsRepository(
        FixedClock(testNow),
        latency: Duration.zero,
      ),
    );

    test('seeds goals in every state and projects them', () async {
      final goals = _ok(await repository.list());
      expect(goals.map((goal) => goal.id), [
        'goal-reserve',
        'goal-trip',
        'goal-laptop',
      ]);
      expect(goals.every((goal) => goal.contributions.isEmpty), isTrue);
      final trip = goals[1];
      expect(trip.source, GoalSource.account);
      expect(trip.linkedName, isNotNull);
      expect(trip.status, GoalStatus.behind);
      final laptop = goals[2];
      expect(laptop.percent, 90);
      expect(laptop.requiredMonthly, isNull);
      final reserve = _ok(await repository.get('goal-reserve'));
      expect(reserve.contributions.first.note, 'Décimo terceiro');
      expect(reserve.status, GoalStatus.onTrack);
    });

    test('creates, contributes, edits, archives and deletes', () async {
      final created = _ok(
        await repository.create(
          const GoalDraft(
            name: 'Carro',
            target: Money(1_000),
            initial: Money(400),
          ),
        ),
      );
      expect(created.percent, 40);
      expect(created.contributions, hasLength(1));
      final linked = _ok(
        await repository.create(
          const GoalDraft(
            name: 'Casa',
            target: Money(1_000),
            accountId: 'acc-pf-checking',
          ),
        ),
      );
      expect(linked.source, GoalSource.account);
      final invested = _ok(
        await repository.create(
          const GoalDraft(
            name: 'Aposentadoria',
            target: Money(1_000),
            investmentId: 'cdb-aurora',
            icon: 'savings',
            color: 'purple',
          ),
        ),
      );
      expect(invested.source, GoalSource.investment);
      expect(invested.investmentId, 'cdb-aurora');
      expect(invested.icon, 'savings');
      expect(invested.color, 'purple');

      final done = _ok(
        await repository.contribute(created.id, const Money(600), note: 'x'),
      );
      expect(done.status, GoalStatus.done);
      expect(done.remaining, const Money(0));
      expect(done.projectedOn, isNull);
      final undone = _ok(
        await repository.removeContribution(
          created.id,
          done.contributions.firstWhere((c) => c.note == 'x').id,
        ),
      );
      expect(undone.percent, 40);
      final renamed = _ok(
        await repository.update(
          created.id,
          const GoalDraft(name: 'Carro novo', target: Money(2_000)),
        ),
      );
      expect(renamed.name, 'Carro novo');
      expect(_ok(await repository.archive(created.id)).archived, isTrue);
      expect(
        _ok(await repository.list()).map((goal) => goal.id),
        isNot(contains(created.id)),
      );
      expect(await repository.delete(created.id), isA<Ok<void>>());
      expect(
        await repository.delete(created.id),
        const Err<void>(NotFoundFailure()),
      );
      expect(
        await repository.get('missing'),
        const Err<Goal>(NotFoundFailure()),
      );
    });
  });

  test('the backend picks the repository', () {
    ProviderContainer containerFor(Backend backend) {
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(
            AppConfig(backend: backend, apiBaseUrl: 'https://api.test'),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    expect(
      containerFor(Backend.fake).read(goalsRepositoryProvider),
      isA<FakeGoalsRepository>(),
    );
    expect(
      containerFor(Backend.api).read(goalsRepositoryProvider),
      isA<ApiGoalsRepository>(),
    );
  });
}
