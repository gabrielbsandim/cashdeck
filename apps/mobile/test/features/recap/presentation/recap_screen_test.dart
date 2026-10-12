import 'dart:async';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/alerts/domain/app_alert.dart';
import 'package:cashdeck/features/alerts/presentation/alert_destination.dart';
import 'package:cashdeck/features/alerts/presentation/alert_labels.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/insights/presentation/insights_labels.dart';
import 'package:cashdeck/features/recap/data/recap_dtos.dart';
import 'package:cashdeck/features/recap/domain/monthly_recap.dart';
import 'package:cashdeck/features/recap/presentation/recap_entry_card.dart';
import 'package:cashdeck/features/recap/presentation/recap_labels.dart';
import 'package:cashdeck/features/recap/presentation/recap_screen.dart';
import 'package:cashdeck/features/recap/recap_providers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/builders.dart';
import '../../../support/pump_app.dart';
import '../application/recap_use_cases_test.dart' show MockRecapRepository;
import '../recap_builders.dart';

final Finder _story = find.byKey(RecapScreen.storyKey);

Future<void> _forward(WidgetTester tester, [int times = 1]) async {
  for (var tap = 0; tap < times; tap++) {
    await tester.tapAt(tester.getCenter(_story) + const Offset(120, 0));
    await settle(tester);
  }
}

Future<void> _back(WidgetTester tester) async {
  await tester.tapAt(tester.getTopLeft(_story) + const Offset(20, 300));
  await settle(tester);
}

void _expectPage(RecapPage page) =>
    expect(find.byKey(RecapScreen.pageKey(page)), findsOneWidget);

/// The device asks for reduced motion, so no page moves on by itself.
void _stillMotion(WidgetTester tester) {
  final dispatcher = tester.platformDispatcher;
  dispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);
}

double _fillOf(WidgetTester tester, int index) => tester
    .widget<FractionallySizedBox>(
      find.descendant(
        of: find.byKey(RecapScreen.barKey(index)),
        matching: find.byType(FractionallySizedBox),
      ),
    )
    .widthFactor!;

/// The recap screen over a repository that answers [json].
Future<ProviderContainer> _pumpJson(
  WidgetTester tester,
  Map<String, dynamic> json, {
  List<Override> overrides = const [],
  EntityKind entity = EntityKind.personal,
}) {
  _stillMotion(tester);
  final repository = MockRecapRepository();
  when(
    () =>
        repository.get(const YearMonth(2026, 9), locale: 'pt', entity: entity),
  ).thenAnswer((_) async => Ok(monthlyRecapFromJson(json)));
  return pumpRoute(
    tester,
    AppRoutes.recap(
      '2026-09',
      entity: entity == EntityKind.company ? 'PJ' : null,
    ),
    overrides: [
      recapRepositoryProvider.overrideWithValue(repository),
      ...overrides,
    ],
  );
}

/// The recap pushed over Análises, pumped frame by frame so its timer runs.
Future<void> _openPlaying(WidgetTester tester) async {
  final container = await pumpRoute(tester, AppRoutes.insights);
  unawaited(container.router.push(AppRoutes.recap('2026-09')));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _playPage(WidgetTester tester) async {
  await tester.pump(RecapScreen.pageDuration);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() {
    registerFallbackValue(const YearMonth(2026, 1));
    registerFallbackValue(EntityKind.personal);
  });

  testWidgets('plays the month page by page and closes after the last', (
    tester,
  ) async {
    _stillMotion(tester);
    final container = await pumpRoute(tester, AppRoutes.recap('2026-09'));

    _expectPage(RecapPage.flow);
    expect(find.text(l10n.recapFlowTitle('Setembro')), findsOneWidget);
    expect(find.text(l10n.recapNetKept), findsOneWidget);
    expect(find.text(recapTitleOf(l10n, const YearMonth(2026, 9))), findsOne);

    await _back(tester);
    _expectPage(RecapPage.flow);

    await _forward(tester);
    _expectPage(RecapPage.topCategory);
    expect(find.text(l10n.recapTopShare(30)), findsOneWidget);

    await _forward(tester);
    _expectPage(RecapPage.changes);
    expect(find.text('7%'), findsOneWidget);
    expect(find.text(l10n.recapStarted), findsOneWidget);
    expect(find.text('Cine Nuvem'), findsOneWidget);
    expect(find.text(l10n.recapStopped), findsNothing);

    await _forward(tester);
    _expectPage(RecapPage.savings);
    expect(find.text('28%'), findsOneWidget);
    expect(find.text(l10n.recapSavingsKept), findsOneWidget);
    expect(find.text(l10n.recapSavingsPrevious('agosto', 23)), findsOne);

    await _forward(tester);
    _expectPage(RecapPage.netWorth);

    await _forward(tester);
    _expectPage(RecapPage.story);
    expect(find.text(l10n.recapStoryAi), findsOneWidget);

    await _back(tester);
    _expectPage(RecapPage.netWorth);

    await _forward(tester, 2);
    expect(container.location, AppRoutes.insights);
  });

  testWidgets('a swipe down or the close button leaves the recap', (
    tester,
  ) async {
    _stillMotion(tester);
    final container = await pumpRoute(tester, AppRoutes.recap('2026-09'));

    await tester.drag(_story, const Offset(0, 300));
    await settle(tester);
    expect(container.location, AppRoutes.insights);

    container.router.go(AppRoutes.recap('2026-09'));
    await settle(tester);
    await tester.drag(_story, const Offset(0, -300));
    await settle(tester);
    _expectPage(RecapPage.flow);

    await tester.tap(find.byKey(RecapScreen.closeKey));
    await settle(tester);
    expect(container.location, AppRoutes.insights);
  });

  testWidgets('Análises opens the last closed month and gets it back', (
    tester,
  ) async {
    _stillMotion(tester);
    final container = await pumpRoute(tester, AppRoutes.insights);

    final entry = find.byKey(RecapEntryCard.tileKey);
    expect(entry, findsOneWidget);
    await tester.tap(entry);
    await settle(tester);
    expect(container.location, AppRoutes.recap('2026-09'));

    await tester.tap(find.byKey(RecapScreen.closeKey));
    await settle(tester);
    expect(container.location, AppRoutes.insights);
  });

  testWidgets('a month still open fails with a retry and a way out', (
    tester,
  ) async {
    _stillMotion(tester);
    final container = await pumpRoute(tester, AppRoutes.recap('2026-10'));

    expect(find.byKey(CdErrorState.retryKey), findsOneWidget);
    await tester.tap(find.byKey(CdErrorState.retryKey));
    await settle(tester);
    expect(find.byKey(CdErrorState.retryKey), findsOneWidget);

    await tester.tap(find.byKey(RecapScreen.closeKey));
    await settle(tester);
    expect(container.location, AppRoutes.insights);
  });

  testWidgets('hidden amounts stay hidden in the closing words', (
    tester,
  ) async {
    await _pumpJson(
      tester,
      recapJson(),
      overrides: [hideAmountsProvider.overrideWithValue(true)],
    );

    await _forward(tester, 2);
    _expectPage(RecapPage.changes);
    expect(find.text('Shows'), findsOneWidget);
    expect(find.text(l10n.recapStopped), findsOneWidget);
    expect(find.textContaining(MoneyFormat.hidden), findsWidgets);

    await _forward(tester, 3);
    _expectPage(RecapPage.story);
    expect(
      find.text('Setembro fechou com R\$ ${MoneyFormat.hidden} de sobra.'),
      findsOneWidget,
    );
  });

  testWidgets('a month that ran short says so', (tester) async {
    final json = recapJson(source: 'TEMPLATE');
    await _pumpJson(tester, {
      ...json,
      'flow': {
        'income': {'cents': 100_000, 'currency': 'BRL'},
        'expenses': {'cents': 120_000, 'currency': 'BRL'},
        'net': {'cents': -20_000, 'currency': 'BRL'},
      },
      'expensesChange': {
        'amount': {'cents': 20_000, 'currency': 'BRL'},
        'percent': null,
      },
      'savings': {'percent': -20, 'previousPercent': null},
      'topCategory': {
        ...json['topCategory'] as Map<String, dynamic>,
        'sharePercent': null,
      },
    });

    expect(find.text(l10n.recapNetShort), findsOneWidget);
    await _forward(tester);
    expect(find.textContaining('%'), findsNothing);
    await _forward(tester);
    expect(find.textContaining('200,00'), findsOneWidget);
    await _forward(tester);
    expect(find.text('-20%'), findsOneWidget);
    expect(find.text(l10n.recapSavingsShort), findsOneWidget);
    await _forward(tester, 2);
    expect(find.text(l10n.recapStoryTemplate), findsOneWidget);
  });

  test('labels mask amounts and pick the language', () {
    expect(
      maskAmounts(r'Sobrou R$ 1.234,56 e R$ 7'),
      'Sobrou R\$ ${MoneyFormat.hidden} e R\$ 7',
    );
    expect(recapLocaleOf(l10n), 'pt');
  });

  testWidgets('each page moves on by itself and holds while pressed', (
    tester,
  ) async {
    await _openPlaying(tester);
    _expectPage(RecapPage.flow);
    expect(_fillOf(tester, 0), inExclusiveRange(0, 1));
    expect(_fillOf(tester, 1), 0);

    await _playPage(tester);
    _expectPage(RecapPage.topCategory);
    expect(_fillOf(tester, 0), 1);

    final finger = await tester.startGesture(tester.getCenter(_story));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    final held = _fillOf(tester, 1);
    await tester.pump(const Duration(seconds: 20));
    _expectPage(RecapPage.topCategory);
    expect(_fillOf(tester, 1), held);
    await finger.up();
    await tester.pump();

    await _playPage(tester);
    _expectPage(RecapPage.changes);
    for (var page = 0; page < 6; page++) {
      await _playPage(tester);
    }
    _expectPage(RecapPage.story);
    expect(find.byKey(RecapScreen.storyKey), findsOneWidget);
  });

  testWidgets('with reduced motion no page moves on by itself', (tester) async {
    _stillMotion(tester);
    await pumpRoute(tester, AppRoutes.recap('2026-09'));

    await tester.pump(const Duration(seconds: 30));
    _expectPage(RecapPage.flow);
    expect(_fillOf(tester, 0), 1);
    expect(_fillOf(tester, 1), 0);
  });

  testWidgets('a company recap asks for the company and says so', (
    tester,
  ) async {
    await _pumpJson(tester, recapJson(), entity: EntityKind.company);

    expect(
      find.text(
        l10n.recapTitleCompany(monthName(l10n, const YearMonth(2026, 9))),
      ),
      findsOneWidget,
    );
    expect(recapEntityOf('PJ'), EntityKind.company);
    expect(recapEntityOf('PF'), EntityKind.personal);
    expect(recapEntityOf(null), EntityKind.personal);
  });

  test('a recap alert opens its month in the app language', () {
    expect(
      alertDestination(AlertKind.monthlyRecap, {'month': '2026-09'}),
      AppRoutes.recap('2026-09'),
    );
    expect(
      alertDestination(AlertKind.monthlyRecap, {
        'month': '2026-09',
        'entity': 'PJ',
      }),
      '/recap/2026-09?entity=PJ',
    );
    expect(
      AppRoutes.recap('2026-09', entity: 'PF'),
      AppRoutes.recap('2026-09'),
    );
    expect(alertDestination(AlertKind.monthlyRecap, const {}), isNull);
    AppAlert alert(Map<String, String> data) => AppAlert(
      id: 'a1',
      kind: AlertKind.monthlyRecap,
      title: 'Stored title',
      body: 'Stored body',
      createdAt: testNow,
      data: data,
    );
    final text = alertText(
      l10n,
      alert({'month': '2026-09', 'income': r'R$ 1,00', 'expenses': r'R$ 2,00'}),
    );
    expect(text.title, l10n.alertTextRecapTitle('setembro'));
    expect(
      alertText(
        l10n,
        alert({
          'month': '2026-09',
          'entity': 'PJ',
          'income': r'R$ 1,00',
          'expenses': r'R$ 2,00',
        }),
      ).title,
      l10n.alertTextRecapCompanyTitle('setembro'),
    );
    expect(text.body, l10n.alertTextRecapBody(r'R$ 1,00', r'R$ 2,00'));
    expect(alertText(l10n, alert({'month': 'setembro'})).title, 'Stored title');
    expect(alertKindLabel(l10n, AlertKind.monthlyRecap), isNotEmpty);
    expect(alertKindIcon(AlertKind.monthlyRecap), isNotNull);
  });
}
