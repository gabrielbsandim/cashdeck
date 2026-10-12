import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/goals/domain/goal.dart';
import 'package:cashdeck/features/goals/goals_providers.dart';
import 'package:cashdeck/features/goals/presentation/goal_celebration.dart';
import 'package:cashdeck/features/goals/presentation/goal_detail_screen.dart';
import 'package:cashdeck/features/goals/presentation/goal_editor.dart';
import 'package:cashdeck/features/goals/presentation/goals_screen.dart';
import 'package:cashdeck/features/goals/presentation/home_goals_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/pump_app.dart';
import '../application/goals_use_cases_test.dart' show MockGoalsRepository;
import '../goal_builders.dart';

Future<void> _type(WidgetTester tester, Key key, String text) async {
  await tester.enterText(find.byKey(key), text);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

Future<void> _menu(WidgetTester tester, String action) async {
  await _tap(tester, find.byKey(GoalDetailScreen.menuKey));
  await _tap(tester, find.byKey(GoalDetailScreen.actionKey(action)));
}

void main() {
  setUpAll(() {
    registerFallbackValue(const GoalDraft(name: 'x', target: Money(1)));
    registerFallbackValue(const Money(0));
  });

  testWidgets('lists the goals with their status and creates one', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.goals);

    expect(find.byKey(GoalsScreen.tileKey('goal-reserve')), findsOneWidget);
    expect(find.text(l10n.goalStatusBehind), findsOneWidget);

    await _tap(tester, find.byKey(GoalsScreen.addKey));
    await _tap(tester, find.byKey(GoalEditor.saveKey));
    expect(find.text(l10n.goalNameMissing), findsWidgets);

    await _type(tester, GoalEditor.nameKey, 'Carro');
    await _tap(tester, find.byKey(GoalEditor.saveKey));
    expect(find.text(l10n.goalTargetMissing), findsOneWidget);

    await _type(tester, GoalEditor.targetKey, '1000000');
    await _type(tester, GoalEditor.initialKey, '250000');
    await _tap(tester, find.byKey(GoalEditor.deadlineKey));
    await _tap(tester, find.text('OK'));
    expect(find.byKey(GoalEditor.clearDeadlineKey), findsOneWidget);
    await _tap(tester, find.byKey(GoalEditor.clearDeadlineKey));
    expect(find.text(l10n.goalDeadlineNone), findsOneWidget);

    await _tap(tester, find.byKey(GoalEditor.saveKey));

    expect(find.byKey(GoalEditor.saveKey), findsNothing);
    expect(find.text('Carro'), findsOneWidget);
    expect(find.textContaining('2.500'), findsOneWidget);
  });

  testWidgets('a goal can follow an account', (tester) async {
    await pumpRoute(tester, AppRoutes.goals);
    await _tap(tester, find.byKey(GoalsScreen.addKey));
    expect(find.text(l10n.goalAccountManualHelp), findsOneWidget);

    await _type(tester, GoalEditor.nameKey, 'Casa');
    await _type(tester, GoalEditor.targetKey, '5000000');
    await _tap(tester, find.byKey(GoalEditor.accountKey));
    await _tap(tester, find.text('Corrente Aurora ••4410').last);
    expect(find.text(l10n.goalAccountHelp), findsOneWidget);
    expect(find.byKey(GoalEditor.initialKey), findsNothing);
    await _tap(tester, find.byKey(GoalEditor.saveKey));

    expect(find.text('Casa'), findsOneWidget);
  });

  testWidgets('reaching the target celebrates, then money moves both ways', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.goal('goal-laptop'));

    expect(find.text(l10n.goalContributionsTitle), findsOneWidget);
    await _tap(tester, find.byKey(GoalDetailScreen.addKey));
    await _tap(tester, find.byKey(ContributionSheet.saveKey));
    expect(find.text(l10n.goalContributionMissing), findsOneWidget);

    await _type(tester, ContributionSheet.amountKey, '60000');
    await _type(tester, ContributionSheet.noteKey, 'Bônus');
    await _tap(tester, find.byKey(ContributionSheet.saveKey));

    expect(find.byType(GoalCelebration), findsOneWidget);
    expect(find.text(l10n.goalReachedMessage('Notebook novo')), findsOneWidget);
    await _tap(tester, find.byKey(GoalCelebration.closeKey));
    expect(find.text(l10n.goalProjectionDone), findsOneWidget);

    await _tap(tester, find.byKey(GoalDetailScreen.withdrawKey));
    await _type(tester, ContributionSheet.amountKey, '10000');
    await _tap(tester, find.byKey(ContributionSheet.saveKey));
    expect(find.byType(GoalCelebration), findsNothing);
    expect(find.text(l10n.goalContributionSaved), findsOneWidget);

    await _tap(
      tester,
      find
          .descendant(
            of: find.byKey(GoalDetailScreen.contributionKey('goal-laptop-1')),
            matching: find.byTooltip(l10n.goalContributionRemove),
          )
          .first,
    );
    expect(find.text(l10n.goalContributionRemoved), findsOneWidget);
    expect(
      find.byKey(GoalDetailScreen.contributionKey('goal-laptop-1')),
      findsNothing,
    );
  });

  testWidgets('edits, archives and deletes from the menu', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.goals);
    await _tap(tester, find.byKey(GoalsScreen.tileKey('goal-reserve')));
    expect(app.location, AppRoutes.goal('goal-reserve'));
    expect(find.textContaining('Décimo terceiro'), findsOneWidget);

    await _menu(tester, 'edit');
    await _type(tester, GoalEditor.nameKey, 'Reserva maior');
    await _tap(tester, find.byKey(GoalEditor.saveKey));
    expect(find.text('Reserva maior'), findsWidgets);

    await _menu(tester, 'archive');
    expect(app.location, AppRoutes.goals);
    expect(find.text(l10n.goalArchived), findsOneWidget);
    expect(find.byKey(GoalsScreen.tileKey('goal-reserve')), findsNothing);

    await _tap(tester, find.byKey(GoalsScreen.tileKey('goal-trip')));
    expect(find.text(l10n.goalLinked('Corrente Aurora ••4410')), findsOne);
    expect(find.byKey(GoalDetailScreen.addKey), findsNothing);
    await _menu(tester, 'delete');
    await _tap(tester, find.text(l10n.cancelButton));
    expect(app.location, AppRoutes.goal('goal-trip'));
    await _menu(tester, 'delete');
    await _tap(
      tester,
      find.byKey(GoalDetailScreen.actionKey('confirm-delete')),
    );
    expect(app.location, AppRoutes.goals);
    expect(find.text(l10n.goalDeleted), findsOneWidget);
  });

  testWidgets('failures show where they happened', (tester) async {
    final repository = MockGoalsRepository();
    var listed = 0;
    when(repository.list).thenAnswer(
      (_) async =>
          listed++ == 0 ? const Err(ServerFailure()) : Ok([goalAt(40)]),
    );
    when(() => repository.get('goal-1'))
        .thenAnswer((_) async => Ok(goalAt(40)));
    when(
      () => repository.create(any()),
    ).thenAnswer((_) async => const Err(ValidationFailure('Nome repetido.')));
    when(() => repository.archive('goal-1'))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    when(() => repository.delete('goal-1'))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    when(() => repository.contribute('goal-1', any(), note: any(named: 'note')))
        .thenAnswer((_) async => const Err(ValidationFailure('Recusado.')));
    when(() => repository.removeContribution('goal-1', any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    final app = await pumpRoute(
      tester,
      AppRoutes.goals,
      overrides: [goalsRepositoryProvider.overrideWithValue(repository)],
    );

    expect(find.text(l10n.errorServer), findsOneWidget);
    await _tap(tester, find.text(l10n.retryButton));
    expect(find.byKey(GoalsScreen.tileKey('goal-1')), findsOneWidget);

    await _tap(tester, find.byKey(GoalsScreen.addKey));
    await _type(tester, GoalEditor.nameKey, 'Carro');
    await _type(tester, GoalEditor.targetKey, '100');
    await _tap(tester, find.byKey(GoalEditor.saveKey));
    expect(find.text('Nome repetido.'), findsOneWidget);
    await tester.tapAt(const Offset(200, 20));
    await settle(tester);

    await _tap(tester, find.byKey(GoalsScreen.tileKey('goal-1')));
    expect(find.text(l10n.goalProjectionUnknown), findsOneWidget);
    expect(find.text(l10n.goalContributionsEmpty), findsOneWidget);
    await _tap(tester, find.byKey(GoalDetailScreen.addKey));
    await _type(tester, ContributionSheet.amountKey, '100');
    await _tap(tester, find.byKey(ContributionSheet.saveKey));
    expect(find.text('Recusado.'), findsOneWidget);
    await tester.tapAt(const Offset(200, 20));
    await settle(tester);

    await _menu(tester, 'archive');
    expect(app.location, AppRoutes.goal('goal-1'));
    expect(find.text(l10n.errorNetwork), findsOneWidget);
    await _menu(tester, 'delete');
    await _tap(
      tester,
      find.byKey(GoalDetailScreen.actionKey('confirm-delete')),
    );
    expect(app.location, AppRoutes.goal('goal-1'));
  });

  testWidgets('a goal that cannot load offers a retry', (tester) async {
    final repository = MockGoalsRepository();
    when(repository.list).thenAnswer((_) async => const Ok([]));
    when(() => repository.get('gone'))
        .thenAnswer((_) async => const Err(NotFoundFailure()));
    await pumpRoute(
      tester,
      AppRoutes.goal('gone'),
      overrides: [goalsRepositoryProvider.overrideWithValue(repository)],
    );

    expect(find.text(l10n.errorNotFound), findsOneWidget);
    await _tap(tester, find.text(l10n.retryButton));
    verify(() => repository.get('gone')).called(2);
  });

  group('home strip', () {
    testWidgets('shows each goal and opens it', (tester) async {
      final app = await pumpRoute(tester, AppRoutes.home, screenHeight: 5200);

      expect(find.byKey(HomeGoalsStrip.cardKey('goal-reserve')), findsOne);
      await _tap(tester, find.byKey(HomeGoalsStrip.cardKey('goal-reserve')));
      expect(app.location, AppRoutes.goal('goal-reserve'));
      app.router.pop();
      await settle(tester);

      await _tap(tester, find.byKey(HomeGoalsStrip.seeAllKey));
      expect(app.location, AppRoutes.goals);
    });

    testWidgets('without goals invites to set one', (tester) async {
      final repository = MockGoalsRepository();
      when(repository.list).thenAnswer((_) async => const Ok([]));
      final app = await pumpRoute(
        tester,
        AppRoutes.home,
        screenHeight: 5200,
        overrides: [goalsRepositoryProvider.overrideWithValue(repository)],
      );

      await _tap(tester, find.byKey(HomeGoalsStrip.startKey));
      expect(app.location, AppRoutes.goals);
      expect(find.text(l10n.goalsEmptyTitle), findsOneWidget);
    });
  });
}
