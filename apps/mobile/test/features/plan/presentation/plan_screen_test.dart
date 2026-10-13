import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/goals/presentation/goals_screen.dart';
import 'package:cashdeck/features/plan/data/plan_dtos.dart';
import 'package:cashdeck/features/plan/domain/life_plan.dart';
import 'package:cashdeck/features/plan/plan_providers.dart';
import 'package:cashdeck/features/plan/presentation/home_plan_card.dart';
import 'package:cashdeck/features/plan/presentation/plan_goal_editor.dart';
import 'package:cashdeck/features/plan/presentation/plan_labels.dart';
import 'package:cashdeck/features/plan/presentation/plan_screen.dart';
import 'package:cashdeck/features/plan/presentation/plan_settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/pump_app.dart';
import '../application/plan_use_cases_test.dart' show MockPlanRepository;
import '../plan_builders.dart';

String _brl(int reais) => MoneyFormat.whole(Money(reais * 100));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

Finder _input(Key key) =>
    find.descendant(of: find.byKey(key), matching: find.byType(EditableText));

Future<void> _type(WidgetTester tester, Key key, String text) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.enterText(_input(key), text);
  await tester.pump();
}

Future<void> _pickMonth(WidgetTester tester, Key row) async {
  await _tap(tester, find.byKey(row));
  final labels = MaterialLocalizations.of(
    tester.element(find.byType(DatePickerDialog)),
  );
  await tester.tap(find.text(labels.okButtonLabel));
  await settle(tester);
}

Finder _tile(String name) => find.ancestor(
  of: find.text(name),
  matching: find.byWidgetPredicate(
    (widget) => widget.key.toString().contains('plan-goal-'),
  ),
);

void main() {
  setUpAll(() {
    registerFallbackValue(
      const PlanGoalDraft(kind: PlanGoalKind.yearly, name: 'x'),
    );
    registerFallbackValue(const PlanSettings(reserveMonths: 1, yearlyYield: 1));
  });

  testWidgets('shows when each goal fits and adds a purchase', (tester) async {
    await pumpRoute(tester, AppRoutes.plan);

    expect(find.byKey(PlanScreen.summaryKey), findsOneWidget);
    expect(find.text(l10n.planSavings(_brl(15_000))), findsOneWidget);
    expect(find.text(l10n.planSavingsFromBudget), findsOneWidget);
    expect(find.text(l10n.planPurchaseOn('Outubro 2027')), findsOneWidget);
    expect(find.text(l10n.planMilestoneOn('Abril 2028')), findsOneWidget);
    expect(find.text(l10n.planYearlyLine(_brl(1_250))), findsOneWidget);
    expect(find.text(l10n.planAssumptions('6')), findsOneWidget);

    await _tap(tester, find.byKey(PlanScreen.addKey));
    await _tap(tester, find.byKey(PlanGoalEditor.saveKey));
    expect(find.text(l10n.planNameMissing), findsOneWidget);
    await _type(tester, PlanGoalEditor.nameKey, 'Celular');
    await _tap(tester, find.byKey(PlanGoalEditor.saveKey));
    expect(find.text(l10n.planAmountMissing), findsOneWidget);

    await _type(tester, PlanGoalEditor.priceKey, '600000');
    await _type(tester, PlanGoalEditor.tradeInKey, '50000');
    await _type(tester, PlanGoalEditor.financedKey, '0');
    await _type(tester, PlanGoalEditor.monthlyCostKey, '0');
    await _tap(tester, find.byKey(PlanGoalEditor.keepsValueKey));
    await _pickMonth(tester, PlanGoalEditor.notBeforeKey);
    expect(find.text(l10n.planNotBefore('Outubro 2026')), findsOneWidget);
    await _tap(tester, find.byKey(PlanGoalEditor.clearKey('not-before')));
    expect(find.text(l10n.planNotBeforeNone), findsOneWidget);
    await _pickMonth(tester, PlanGoalEditor.byKey);
    await _pickMonth(tester, PlanGoalEditor.byKey);
    await _tap(tester, find.byKey(PlanGoalEditor.clearKey('by')));

    await _tap(tester, find.byKey(PlanGoalEditor.assetKey));
    await _tap(tester, find.text('Apartamento').last);
    expect(find.byKey(PlanGoalEditor.tradeInKey), findsNothing);

    await _tap(tester, find.byKey(PlanGoalEditor.saveKey));
    expect(find.text(l10n.planSaved), findsOneWidget);
    expect(find.text('Celular'), findsOneWidget);
  });

  testWidgets('edits, adds a milestone, deletes and reorders', (tester) async {
    await pumpRoute(tester, AppRoutes.plan);

    await _tap(tester, _tile('Viagens do ano'));
    expect(find.byKey(PlanGoalEditor.kindKey), findsNothing);
    await _type(tester, PlanGoalEditor.yearlyKey, '2400000');
    await _tap(tester, find.byKey(PlanGoalEditor.saveKey));
    expect(find.text(l10n.planYearlyLine(_brl(2_000))), findsOneWidget);

    await _tap(tester, find.byKey(PlanScreen.addKey));
    await _tap(tester, find.text(l10n.planKindMilestone));
    await _type(tester, PlanGoalEditor.nameKey, 'Reserva grande');
    await _tap(tester, find.text(l10n.planMetricInvested));
    await _type(tester, PlanGoalEditor.targetKey, '100000000');
    await _pickMonth(tester, PlanGoalEditor.byKey);
    await _tap(tester, find.byKey(PlanGoalEditor.saveKey));
    expect(find.text('Reserva grande'), findsOneWidget);

    await _tap(tester, find.byKey(PlanScreen.addKey));
    await _tap(tester, find.text(l10n.planKindYearly));
    await _type(tester, PlanGoalEditor.nameKey, 'Presentes');
    await _type(tester, PlanGoalEditor.yearlyKey, '120000');
    await _tap(tester, find.byKey(PlanGoalEditor.saveKey));
    expect(find.text('Presentes'), findsOneWidget);

    await _tap(tester, _tile('Trocar de carro'));
    await _tap(tester, find.byKey(PlanGoalEditor.deleteKey));
    expect(find.text(l10n.planDeleted), findsOneWidget);
    expect(find.text('Trocar de carro'), findsNothing);

    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    list.onReorderItem!(0, 0);
    list.onReorderItem!(0, 2);
    await settle(tester);
    final names = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .where(
          (name) => ['Viagens do ano', 'Patrimônio de 1 milhão'].contains(name),
        )
        .toList();
    expect(names, ['Patrimônio de 1 milhão', 'Viagens do ano']);
  });

  testWidgets('changes the assumptions', (tester) async {
    await pumpRoute(tester, AppRoutes.plan);

    await _tap(tester, find.byKey(PlanScreen.settingsKey));
    await _type(tester, PlanSettingsSheet.reserveKey, '30');
    await _tap(tester, find.byKey(PlanSettingsSheet.saveKey));
    expect(find.text(l10n.planSettingsInvalid), findsOneWidget);

    await _type(tester, PlanSettingsSheet.reserveKey, '3');
    await _type(tester, PlanSettingsSheet.yieldKey, '5,5');
    await _type(tester, PlanSettingsSheet.keepKey, '50');
    await _tap(tester, find.byKey(PlanSettingsSheet.fromBudgetKey));
    await _type(tester, PlanSettingsSheet.savingsKey, '1000000');
    await _tap(tester, find.byKey(PlanSettingsSheet.saveKey));

    expect(find.text(l10n.planSaved), findsOneWidget);
    expect(find.text(l10n.planSavingsCustom), findsOneWidget);
    expect(find.text(l10n.planAssumptions('5,5')), findsOneWidget);
    expect(find.text(l10n.planKeep(50)), findsOneWidget);
    expect(find.text(l10n.planSavings(_brl(10_000))), findsOneWidget);

    await _tap(tester, find.byKey(PlanScreen.settingsKey));
    expect(
      find.descendant(
        of: find.byKey(PlanSettingsSheet.yieldKey),
        matching: find.text('5,5'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows the failures of every change', (tester) async {
    final repository = MockPlanRepository();
    final plan = lifePlanFromJson(
      lifePlanJson(
        goals: [
          planGoalJson(),
          planGoalJson(id: 'g2', kind: 'YEARLY', month: null),
        ],
      ),
    );
    const failure = Err<LifePlan>(ServerFailure());
    when(repository.load).thenAnswer((_) async => Ok(plan));
    when(() => repository.update(any(), any()))
        .thenAnswer((_) async => failure);
    when(() => repository.remove(any())).thenAnswer((_) async => failure);
    when(() => repository.reorder(any())).thenAnswer((_) async => failure);
    when(() => repository.saveSettings(any())).thenAnswer((_) async => failure);
    await pumpRoute(
      tester,
      AppRoutes.plan,
      overrides: [planRepositoryProvider.overrideWithValue(repository)],
    );

    await _tap(tester, find.text('Carro').first);
    await _tap(tester, find.byKey(PlanGoalEditor.saveKey));
    expect(find.text(l10n.errorServer), findsOneWidget);
    await _tap(tester, find.byKey(PlanGoalEditor.deleteKey));
    expect(find.text(l10n.errorServer), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);

    await _tap(tester, find.byKey(PlanScreen.settingsKey));
    await _tap(tester, find.byKey(PlanSettingsSheet.saveKey));
    expect(find.byKey(PlanSettingsSheet.errorKey), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);

    tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .onReorderItem!(0, 1);
    await settle(tester);
    expect(find.text(l10n.errorServer), findsOneWidget);
  });

  testWidgets('an empty plan invites a goal', (tester) async {
    final repository = MockPlanRepository();
    when(repository.load)
        .thenAnswer((_) async => Ok(lifePlanFromJson(lifePlanJson(goals: []))));
    await pumpRoute(
      tester,
      AppRoutes.plan,
      overrides: [planRepositoryProvider.overrideWithValue(repository)],
    );
    expect(find.text(l10n.planEmptyTitle), findsOneWidget);
  });

  testWidgets('a failed load offers a retry', (tester) async {
    final repository = MockPlanRepository();
    when(repository.load).thenAnswer((_) async => const Err(ServerFailure()));
    await pumpRoute(
      tester,
      AppRoutes.plan,
      overrides: [planRepositoryProvider.overrideWithValue(repository)],
    );
    expect(find.byType(CdErrorState), findsOneWidget);
  });

  testWidgets('Início shows the next purchase and opens the plan', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.home);
    await tester.scrollUntilVisible(
      find.byKey(HomePlanCard.cardKey),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text(l10n.planHomeNext('Trocar de carro', 'Outubro 2027')),
      findsOneWidget,
    );
    await _tap(tester, find.byKey(HomePlanCard.cardKey));
    expect(find.byType(PlanScreen), findsOneWidget);
  });

  testWidgets('the goals screen opens the plan', (tester) async {
    await pumpRoute(tester, AppRoutes.goals);
    await _tap(tester, find.byKey(GoalsScreen.planKey));
    expect(find.byType(PlanScreen), findsOneWidget);
  });

  test('labels cover every status and kind', () {
    PlanGoal goal(
      PlanGoalKind kind,
      PlanStatus status, {
      YearMonth? month = const YearMonth(2027, 1),
      Money cash = const Money(100),
      List<MilestoneDelay> delays = const [],
    }) => PlanGoal(
      id: 'g',
      kind: kind,
      name: 'Meta',
      status: status,
      month: month,
      cash: cash,
      delays: delays,
    );
    const purchase = PlanGoalKind.purchase;
    const milestone = PlanGoalKind.milestone;
    expect(
      planWhenLine(l10n, goal(purchase, PlanStatus.now)),
      l10n.planPurchaseNow,
    );
    expect(
      planWhenLine(l10n, goal(milestone, PlanStatus.now)),
      l10n.planMilestoneNow,
    );
    expect(
      planWhenLine(l10n, goal(purchase, PlanStatus.late)),
      l10n.planPurchaseLate('Janeiro 2027'),
    );
    expect(
      planWhenLine(l10n, goal(milestone, PlanStatus.late)),
      l10n.planMilestoneLate('Janeiro 2027'),
    );
    expect(
      planWhenLine(l10n, goal(purchase, PlanStatus.outOfReach, month: null)),
      l10n.planOutOfReach,
    );
    expect(
      planAmountLine(
        l10n,
        goal(purchase, PlanStatus.now, cash: const Money(-500_00)),
      ),
      l10n.planCashIn(_brl(500)),
    );
    expect(planAmountLine(l10n, goal(milestone, PlanStatus.now)), isNull);
    expect(
      planDelayLine(
        l10n,
        const MilestoneDelay(milestoneId: 'm', name: 'Milhão', months: null),
      ),
      l10n.planBlocks('Milhão'),
    );
    expect(
      [for (final status in PlanStatus.values) planStatusLabel(l10n, status)],
      [
        l10n.planStatusNow,
        l10n.planStatusPlanned,
        l10n.planStatusLate,
        l10n.planStatusOutOfReach,
      ],
    );
    expect(
      planProblemMessage(l10n, PlanGoalProblem.window),
      l10n.planWindowInvalid,
    );
    expect(planRate(5.5), '5,5');

    LifePlan planOf(List<PlanGoal> goals) {
      final base = lifePlanFromJson(lifePlanJson(goals: []));
      return LifePlan(
        asOf: base.asOf,
        monthlySavings: base.monthlySavings,
        savingsFromBudget: base.savingsFromBudget,
        monthlySpending: base.monthlySpending,
        reserveMonths: base.reserveMonths,
        reserve: base.reserve,
        yearlyYield: base.yearlyYield,
        keepInvested: base.keepInvested,
        netWorth: base.netWorth,
        invested: base.invested,
        yearlyProvision: base.yearlyProvision,
        free: base.free,
        goals: goals,
        timeline: base.timeline,
      );
    }

    expect(
      HomePlanCard.linesOf(l10n, planOf([goal(purchase, PlanStatus.now)])),
      [l10n.planHomeNextNow('Meta')],
    );
    expect(HomePlanCard.linesOf(l10n, planOf([])), isEmpty);
  });
}
