import 'dart:async';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/plan/data/plan_dtos.dart';
import 'package:cashdeck/features/plan/domain/life_plan.dart';
import 'package:cashdeck/features/plan/plan_providers.dart';
import 'package:cashdeck/features/plan/presentation/plan_advice_sheet.dart';
import 'package:cashdeck/features/plan/presentation/plan_goal_editor.dart';
import 'package:cashdeck/features/plan/presentation/plan_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/pump_app.dart';
import '../application/plan_use_cases_test.dart' show MockPlanRepository;
import '../plan_builders.dart';

final LifePlan _plan = lifePlanFromJson(lifePlanJson());

final PlanAdvice _advice = planAdviceFromJson(
  planAdviceJson(
    goalId: 'g1',
    goals: [
      planAdviceGoalJson(
        notBefore: '2027-08',
        payment: {
          'installments': 10,
          'cash': {'cents': 1_900_000, 'currency': 'BRL'},
          'cardToday': {'cents': 1_901_312, 'currency': 'BRL'},
          'better': 'CASH',
          'gain': {'cents': 1_312, 'currency': 'BRL'},
          'breakEvenPercent': 4.9,
        },
      ),
      planAdviceGoalJson(
        id: 'g2',
        name: 'Milhão',
        kind: 'MILESTONE',
        reason: null,
        month: null,
        proposedMonth: null,
      ),
    ],
  ),
);

Future<MockPlanRepository> _open(
  WidgetTester tester, {
  required List<Result<PlanAdvice>> answers,
}) async {
  final repository = MockPlanRepository();
  when(repository.load).thenAnswer((_) async => Ok(_plan));
  when(() => repository.advise(goalId: any(named: 'goalId')))
      .thenAnswer((_) async => answers.removeAt(0));
  await pumpRoute(
    tester,
    AppRoutes.plan,
    overrides: [planRepositoryProvider.overrideWithValue(repository)],
  );
  return repository;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

void main() {
  setUpAll(() => registerFallbackValue(_advice));

  testWidgets('shows the proposal for the plan and applies it', (tester) async {
    final repository = await _open(tester, answers: [Ok(_advice)]);
    final applied = Completer<Result<LifePlan>>();
    when(() => repository.arrange(any())).thenAnswer((_) => applied.future);

    await tester.tap(find.byKey(PlanScreen.adviceKey));
    await tester.pump();
    await tester.pump();
    expect(find.text(l10n.planAdviceTitle), findsOneWidget);
    await settle(tester);

    expect(find.text('O carro espera o marco.'), findsOneWidget);
    expect(
      find.text(l10n.planAdviceMoves('Maio 2027', 'Setembro 2027')),
      findsOneWidget,
    );
    expect(find.text(l10n.planNotBefore('Agosto 2027')), findsOneWidget);
    expect(
      find.text(
        l10n.planAdviceCashWins(
          MoneyFormat.whole(const Money(1_900_000)),
          MoneyFormat.whole(const Money(1_312)),
          10,
          MoneyFormat.whole(const Money(1_901_312)),
        ),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.planAdviceBreakEven('4,9')), findsOneWidget);
    expect(find.text('Cabe melhor depois.'), findsOneWidget);
    expect(
      find.text(l10n.planAdviceStays(l10n.planStatusOutOfReach)),
      findsOneWidget,
    );
    verify(repository.advise).called(1);

    await tester.tap(find.byKey(PlanAdviceSheet.applyKey));
    await tester.pump();
    applied.complete(Ok(_plan));
    await settle(tester);
    expect(find.text(l10n.planAdviceApplied), findsOneWidget);
    expect(find.byKey(PlanAdviceSheet.applyKey), findsNothing);
    verify(() => repository.arrange(_advice)).called(1);
  });

  testWidgets('a failed advice offers a retry, and keeping changes nothing', (
    tester,
  ) async {
    final repository = await _open(
      tester,
      answers: [const Err(ServerFailure()), Ok(_advice)],
    );

    await _tap(tester, find.byKey(PlanScreen.adviceKey));
    expect(find.byKey(PlanAdviceSheet.failedKey), findsOneWidget);
    expect(find.text(l10n.errorServer), findsOneWidget);

    await _tap(tester, find.byKey(PlanAdviceSheet.retryKey));
    expect(find.byKey(PlanAdviceSheet.rowKey('g1')), findsOneWidget);

    await _tap(tester, find.byKey(PlanAdviceSheet.keepKey));
    expect(find.byKey(PlanAdviceSheet.rowKey('g1')), findsNothing);
    verifyNever(() => repository.arrange(any()));
  });

  testWidgets('a refused advice stays open and says why', (tester) async {
    final repository = await _open(tester, answers: [Ok(_advice)]);
    when(() => repository.arrange(any()))
        .thenAnswer((_) async => const Err(ServerFailure()));

    await _tap(tester, find.byKey(PlanScreen.adviceKey));
    await _tap(tester, find.byKey(PlanAdviceSheet.applyKey));

    expect(find.text(l10n.errorServer), findsOneWidget);
    expect(find.byKey(PlanAdviceSheet.applyKey), findsOneWidget);
  });

  testWidgets('a goal asks for a new look from its editor', (tester) async {
    final repository = await _open(tester, answers: [Ok(_advice)]);

    await _tap(tester, find.text('Carro').first);
    await _tap(tester, find.byKey(PlanGoalEditor.adviseKey));

    expect(find.byKey(PlanGoalEditor.saveKey), findsNothing);
    expect(find.byKey(PlanAdviceSheet.rowKey('g1')), findsOneWidget);
    verify(() => repository.advise(goalId: 'g1')).called(1);
  });
}
