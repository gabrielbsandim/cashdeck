import 'dart:async';
import 'dart:ui';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/charts/cd_bar_chart.dart';
import 'package:cashdeck/core/widgets/charts/cd_donut.dart';
import 'package:cashdeck/core/widgets/charts/cd_line_chart.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/investments/presentation/investment_performance.dart';
import 'package:cashdeck/features/outlook/data/fake_outlook_repository.dart';
import 'package:cashdeck/features/outlook/domain/net_worth.dart';
import 'package:cashdeck/features/outlook/outlook_providers.dart';
import 'package:cashdeck/features/outlook/presentation/net_worth_card.dart';
import 'package:cashdeck/features/outlook/presentation/net_worth_screen.dart';
import 'package:cashdeck/features/outlook/presentation/outlook_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/pump_app.dart';
import '../outlook_support.dart';

const double _height = 5200;

Finder _inCard(Finder matching) =>
    find.descendant(of: find.byKey(NetWorthCard.cardKey), matching: matching);

String _brl(int cents) => MoneyFormat.format(Money(cents));

NetWorthPoint _point(CalendarDate on, int total) => NetWorthPoint(
  on: on,
  assets: Money(total + 10_000),
  liabilities: const Money(10_000),
  total: Money(total),
);

MockOutlookRepository _repository(Future<Result<NetWorth>> Function() answer) {
  final repository = outlookRepository();
  when(repository.safeToSpend).thenAnswer((_) async => Ok(shortSafeToSpend));
  when(() => repository.netWorth(any(), any())).thenAnswer((_) => answer());
  return repository;
}

void main() {
  testWidgets('the home card shows the total, the change and the curve', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.home, screenHeight: _height);

    expect(find.byKey(NetWorthCard.cardKey), findsOneWidget);
    expect(_inCard(find.text(_brl(8_777_700))), findsOneWidget);
    expect(_inCard(find.text(l10n.netWorthFromLastMonth)), findsOneWidget);
    expect(_inCard(find.byType(NetWorthSparkline)), findsOneWidget);
  });

  testWidgets('opens the screen, switches the window and refreshes', (
    tester,
  ) async {
    final app = await pumpRoute(tester, AppRoutes.home, screenHeight: _height);

    await tester.tap(_inCard(find.text(l10n.netWorthTitle)));
    await settle(tester);
    expect(app.location, AppRoutes.netWorth);
    expect(find.byType(NetWorthScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(NetWorthScreen.totalKey),
        matching: find.text(_brl(8_777_700)),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.netWorthFromYearAgo), findsOneWidget);
    expect(find.byType(CdLineChart), findsOneWidget);
    expect(
      tester.widget<CdBarChart>(find.byType(CdBarChart)).groups,
      hasLength(13),
    );
    expect(
      find.byKey(NetWorthScreen.entityKey(EntityKind.personal)),
      findsOneWidget,
    );
    expect(find.byType(CdDonut), findsOneWidget);
    expect(find.text(l10n.netWorthCardDebt), findsWidgets);

    await tester.tap(find.text(l10n.netWorthPeriodSix));
    await settle(tester);
    expect(
      app.read(netWorthPeriodProvider.notifier).period,
      NetWorthPeriod.sixMonths,
    );
    expect(
      tester.widget<CdBarChart>(find.byType(CdBarChart)).groups,
      hasLength(7),
    );

    await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
    await settle(tester);
    expect(find.byKey(NetWorthScreen.totalKey), findsOneWidget);
  });

  testWidgets('the consolidated home adds both entities', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.home, screenHeight: _height);
    await pickScope(tester, EntityScope.consolidated);

    final total =
        FakeOutlookRepository.personal.total +
        FakeOutlookRepository.company.total;
    expect(_inCard(find.text(MoneyFormat.format(total))), findsOneWidget);

    app.router.go(AppRoutes.netWorth);
    await settle(tester);
    expect(
      find.byKey(NetWorthScreen.entityKey(EntityKind.personal)),
      findsOneWidget,
    );
    expect(
      find.byKey(NetWorthScreen.entityKey(EntityKind.company)),
      findsOneWidget,
    );
    expect(find.text(l10n.entityCompany), findsOneWidget);
  });

  testWidgets('the card waits, fails and retries, and hides when empty', (
    tester,
  ) async {
    final pending = Completer<Result<NetWorth>>();
    var answer = () => pending.future;
    final repository = _repository(() => answer());
    await pumpRoute(
      tester,
      AppRoutes.home,
      screenHeight: _height,
      overrides: [outlookRepositoryProvider.overrideWithValue(repository)],
    );
    expect(_inCard(find.byType(PerformancePending)), findsOneWidget);

    pending.complete(const Err(NetworkFailure()));
    await settle(tester);
    expect(_inCard(find.text(l10n.homeSectionFailed)), findsOneWidget);

    answer = () async => Ok(netWorthOf());
    await tester.tap(find.byKey(NetWorthCard.retryKey));
    await settle(tester);
    expect(find.byKey(NetWorthCard.cardKey), findsNothing);
  });

  testWidgets('the screen fails, retries and shows a change without percent', (
    tester,
  ) async {
    const owing = NetWorthComposition(
      cash: Money(5_000),
      investments: Money(0),
      cardDebt: Money(25_000),
      assets: Money(5_000),
      liabilities: Money(25_000),
      total: Money(-20_000),
    );
    Future<Result<NetWorth>> Function() answer = () async =>
        const Err(NetworkFailure());
    final repository = _repository(() => answer());
    await pumpRoute(
      tester,
      AppRoutes.netWorth,
      screenHeight: _height,
      overrides: [outlookRepositoryProvider.overrideWithValue(repository)],
    );
    expect(find.byType(CdErrorState), findsOneWidget);

    answer = () async => Ok<NetWorth>(
      netWorthOf(
        current: owing,
        fromLastMonth: const NetWorthChange(amount: Money(-20_000)),
        entities: const [
          EntityNetWorth(kind: EntityKind.personal, current: owing),
          EntityNetWorth(kind: EntityKind.company, current: emptyComposition),
        ],
        series: [
          _point(const CalendarDate(2026, 9, 30), 0),
          _point(const CalendarDate(2026, 10, 8), -20_000),
        ],
      ),
    );
    await tester.tap(find.text(l10n.retryButton));
    await settle(tester);

    expect(find.text(_brl(20_000)), findsWidgets);
    expect(find.byType(CdDonut), findsOneWidget);
    expect(
      find.byKey(NetWorthScreen.entityKey(EntityKind.company)),
      findsOneWidget,
    );
  });

  testWidgets('the screen says when there is nothing to show', (tester) async {
    final repository = _repository(() async => Ok(netWorthOf()));
    await pumpRoute(
      tester,
      AppRoutes.netWorth,
      overrides: [outlookRepositoryProvider.overrideWithValue(repository)],
    );

    expect(find.byType(CdEmptyState), findsOneWidget);
    expect(find.text(l10n.netWorthEmpty), findsOneWidget);
  });

  test('the sparkline draws a flat or a single point history', () {
    const flat = SparklinePainter(
      values: [5, 5, 5],
      line: Color(0xFF000000),
      area: Color(0x33000000),
    );
    const single = SparklinePainter(
      values: [5],
      line: Color(0xFF000000),
      area: Color(0x33000000),
    );
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    flat.paint(canvas, const Size(100, 40));
    single.paint(canvas, const Size(100, 40));
    recorder.endRecording().dispose();

    expect(flat.shouldRepaint(single), isTrue);
    expect(flat.shouldRepaint(flat), isFalse);
  });

  testWidgets('shows goods and loans and opens the goods', (tester) async {
    const owner = NetWorthComposition(
      cash: Money(100_000),
      investments: Money(0),
      realEstate: Money(50_000_000),
      vehicles: Money(9_000_000),
      cardDebt: Money(0),
      loanDebt: Money(19_000_000),
      assets: Money(59_100_000),
      liabilities: Money(19_000_000),
      total: Money(40_100_000),
    );
    final repository = _repository(
      () async => Ok<NetWorth>(
        netWorthOf(
          current: owner,
          entities: const [
            EntityNetWorth(kind: EntityKind.personal, current: owner),
          ],
          series: [
            _point(const CalendarDate(2026, 9, 30), 40_000_000),
            _point(const CalendarDate(2026, 10, 8), 40_100_000),
          ],
        ),
      ),
    );
    final app = await pumpRoute(
      tester,
      AppRoutes.netWorth,
      screenHeight: _height,
      overrides: [outlookRepositoryProvider.overrideWithValue(repository)],
    );

    expect(find.text(l10n.netWorthRealEstate), findsWidgets);
    expect(find.text(l10n.netWorthVehicles), findsWidgets);
    expect(find.text(l10n.netWorthOtherAssets), findsNothing);
    expect(find.text(l10n.netWorthLoanDebt), findsWidgets);
    expect(find.textContaining('190.000,00'), findsWidgets);

    await tester.ensureVisible(find.byKey(NetWorthScreen.assetsKey));
    await tester.tap(find.byKey(NetWorthScreen.assetsKey));
    await settle(tester);
    expect(app.location, AppRoutes.assets);
  });
}
