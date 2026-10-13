import 'dart:async';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/features/plan/data/plan_dtos.dart';
import 'package:cashdeck/features/plan/domain/life_plan.dart';
import 'package:cashdeck/features/plan/plan_providers.dart';
import 'package:cashdeck/features/plan/presentation/plan_controller.dart';
import 'package:cashdeck/features/plan/presentation/plan_goal_editor.dart';
import 'package:cashdeck/features/plan/presentation/plan_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/pump_app.dart';
import '../application/plan_use_cases_test.dart' show MockPlanRepository;
import '../plan_builders.dart';

Map<String, Object?> _goal(String id, String name, String kind) => {
  ...planGoalJson(
    id: id,
    kind: kind,
    month: kind == 'YEARLY' ? null : '2027-05',
    metric: kind == 'MILESTONE' ? 'NET_WORTH' : null,
  ),
  'name': name,
};

final Map<String, Object?> _car = _goal('g1', 'Carro', 'PURCHASE');
final Map<String, Object?> _trips = _goal('g2', 'Viagens', 'YEARLY');
final Map<String, Object?> _million = _goal('g3', 'Um milhão', 'MILESTONE');

LifePlan _plan(List<Map<String, Object?>> goals) =>
    lifePlanFromJson(lifePlanJson(goals: goals));

List<String> _order(WidgetTester tester) {
  final tiles = find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith('plan-goal-g'),
  );
  final found = tester.widgetList(tiles).toList()
    ..sort(
      (a, b) => tester
          .getTopLeft(find.byKey(a.key!))
          .dy
          .compareTo(tester.getTopLeft(find.byKey(b.key!)).dy),
    );
  return [
    for (final widget in found)
      (widget.key! as ValueKey<String>).value.replaceFirst('plan-goal-', ''),
  ];
}

Future<MockPlanRepository> _open(
  WidgetTester tester, {
  required Future<Result<LifePlan>> Function() reorder,
}) async {
  final repository = MockPlanRepository();
  when(repository.load)
      .thenAnswer((_) async => Ok(_plan([_car, _trips, _million])));
  when(() => repository.reorder(any())).thenAnswer((_) => reorder());
  await pumpRoute(
    tester,
    AppRoutes.plan,
    overrides: [planRepositoryProvider.overrideWithValue(repository)],
  );
  return repository;
}

/// Drags [id]'s card down past the next one, from [at] inside it, after
/// holding it for [hold].
Future<void> _dragDown(
  WidgetTester tester,
  String id,
  Finder at, {
  Duration hold = Duration.zero,
}) async {
  await tester.ensureVisible(find.byKey(PlanScreen.tileKey(id)));
  await tester.pumpAndSettle();
  final distance = tester.getSize(find.byKey(PlanScreen.tileKey('g2'))).height;
  final gesture = await tester.startGesture(tester.getCenter(at));
  await tester.pump(hold);
  for (var step = 0; step < 10; step++) {
    await gesture.moveBy(Offset(0, distance / 8));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets(
    'a goal dragged by its handle stays where it fell while the plan is '
    'laid out again, and the drop can be undone',
    (tester) async {
      final answer = Completer<Result<LifePlan>>();
      final repository = await _open(tester, reorder: () => answer.future);
      expect(_order(tester), ['g1', 'g2', 'g3']);

      await _dragDown(tester, 'g1', find.byKey(PlanScreen.handleKey('g1')));

      expect(_order(tester), ['g2', 'g1', 'g3']);
      expect(find.byKey(PlanScreen.recalculatingKey), findsOneWidget);
      expect(verify(() => repository.reorder(captureAny())).captured.single, [
        'g2',
        'g1',
        'g3',
      ]);

      answer.complete(Ok(_plan([_trips, _car, _million])));
      await settle(tester);
      expect(_order(tester), ['g2', 'g1', 'g3']);
      expect(find.byKey(PlanScreen.recalculatingKey), findsNothing);
      expect(find.text(l10n.planReordered), findsOneWidget);

      when(() => repository.reorder(any()))
          .thenAnswer((_) async => Ok(_plan([_car, _trips, _million])));
      await tester.tap(find.text(l10n.undoButton));
      await settle(tester);
      expect(verify(() => repository.reorder(captureAny())).captured.single, [
        'g1',
        'g2',
        'g3',
      ]);
      expect(_order(tester), ['g1', 'g2', 'g3']);
      expect(find.text(l10n.planReordered), findsNothing);
    },
  );

  testWidgets('holding a card drags it too', (tester) async {
    final repository = await _open(
      tester,
      reorder: () async => Ok(_plan([_trips, _car, _million])),
    );

    await _dragDown(
      tester,
      'g1',
      find.text('Carro').first,
      hold: kLongPressTimeout + const Duration(milliseconds: 100),
    );
    await settle(tester);

    expect(_order(tester), ['g2', 'g1', 'g3']);
    verify(() => repository.reorder(['g2', 'g1', 'g3'])).called(1);
  });

  testWidgets('a refused order puts the goal back and says why', (
    tester,
  ) async {
    await _open(tester, reorder: () async => const Err(ServerFailure()));

    await _dragDown(tester, 'g1', find.byKey(PlanScreen.handleKey('g1')));
    await settle(tester);

    expect(_order(tester), ['g1', 'g2', 'g3']);
    expect(find.text(l10n.errorServer), findsOneWidget);
    expect(find.text(l10n.planReordered), findsNothing);
  });

  testWidgets('only the answer to the last drag is shown', (tester) async {
    final first = Completer<Result<LifePlan>>();
    final second = Completer<Result<LifePlan>>();
    final answers = [first, second];
    final repository = await _open(
      tester,
      reorder: () => answers.removeAt(0).future,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlanScreen)),
    );
    final plan = container.read(planControllerProvider.notifier);

    final moves = [plan.move(0, 1), plan.move(0, 2)];
    await tester.pump();
    expect(_order(tester), ['g1', 'g3', 'g2']);
    verify(() => repository.reorder(['g2', 'g1', 'g3'])).called(1);
    verify(() => repository.reorder(['g1', 'g3', 'g2'])).called(1);

    first.complete(Ok(_plan([_trips, _car, _million])));
    await tester.pump();
    expect(_order(tester), ['g1', 'g3', 'g2']);

    second.complete(const Err(ServerFailure()));
    expect(await Future.wait(moves), [null, const ServerFailure()]);
    await tester.pump();
    expect(_order(tester), ['g2', 'g1', 'g3']);
  });

  testWidgets('an empty plan opens the editor from its invitation', (
    tester,
  ) async {
    final repository = MockPlanRepository();
    when(repository.load).thenAnswer((_) async => Ok(_plan([])));
    await pumpRoute(
      tester,
      AppRoutes.plan,
      overrides: [planRepositoryProvider.overrideWithValue(repository)],
    );

    await tester.tap(
      find.descendant(
        of: find.byType(CdEmptyState),
        matching: find.text(l10n.planNew),
      ),
    );
    await settle(tester);
    expect(find.byType(PlanGoalEditor), findsOneWidget);
  });

  testWidgets('pulling the list down loads the plan again', (tester) async {
    final repository = await _open(
      tester,
      reorder: () async => Ok(_plan([_car, _trips, _million])),
    );
    when(repository.load)
        .thenAnswer((_) async => Ok(_plan([_million, _car, _trips])));

    await tester.fling(
      find.byType(Scrollable).first,
      const Offset(0, 1200),
      1000,
    );
    await settle(tester);
    verify(repository.load).called(2);

    expect(_order(tester), ['g3', 'g1', 'g2']);
  });
}
