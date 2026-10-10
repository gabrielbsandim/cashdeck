import 'dart:async';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/charts/cd_line_chart.dart';
import 'package:cashdeck/core/widgets/insights/cd_comparison_pill.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/home/presentation/home_investments_card.dart';
import 'package:cashdeck/features/investments/domain/investments.dart';
import 'package:cashdeck/features/investments/domain/investments_repository.dart';
import 'package:cashdeck/features/investments/investments_providers.dart';
import 'package:cashdeck/features/investments/presentation/investment_performance.dart';
import 'package:cashdeck/features/investments/presentation/investments_controller.dart';
import 'package:cashdeck/features/investments/presentation/investments_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/pump_app.dart';

const double _height = 4200;

final class _MockInvestmentsRepository extends Mock
    implements InvestmentsRepository;

InvestmentPerformance _performance({
  List<PositionPerformance> positions = const [
    PositionPerformance(
      id: 'cdb',
      start: Money(100_000),
      end: Money(101_000),
      yieldAmount: Money(1_000),
      yieldPercent: 1,
    ),
  ],
  double? cdi = 0.8,
}) => InvestmentPerformance(
  period: PerformancePeriod.month,
  from: const CalendarDate(2026, 9, 8),
  to: const CalendarDate(2026, 10, 8),
  start: const Money(100_000),
  end: const Money(101_000),
  contributions: const Money(0),
  withdrawals: const Money(0),
  yieldAmount: const Money(1_000),
  yieldPercent: 1,
  cdiPercent: cdi,
  series: const [
    PerformancePoint(CalendarDate(2026, 9, 8), Money(100_000)),
    PerformancePoint(CalendarDate(2026, 10, 8), Money(101_000)),
  ],
  positions: positions,
);

Finder _inCard(Finder matching) => find.descendant(
  of: find.byKey(HomeInvestmentsCard.cardKey),
  matching: matching,
);

_MockInvestmentsRepository _repository() {
  registerFallbackValue(EntityScope.personal);
  registerFallbackValue(PerformancePeriod.month);
  return _MockInvestmentsRepository();
}

void main() {
  testWidgets('shows the total, the yield against the CDI and the curve', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.home, screenHeight: _height);

    expect(find.byKey(HomeInvestmentsCard.cardKey), findsOneWidget);
    expect(
      _inCard(find.text(MoneyFormat.format(const Money(3_059_340)))),
      findsOneWidget,
    );
    expect(_inCard(find.byType(CdComparisonPill)), findsOneWidget);
    expect(_inCard(find.text(l10n.investmentsInPeriod)), findsOneWidget);
    expect(_inCard(find.textContaining(r'Rendimento +R$')), findsOneWidget);
    expect(_inCard(find.textContaining('CDI ')), findsOneWidget);
    expect(_inCard(find.byType(CdLineChart)), findsOneWidget);
  });

  testWidgets('the period toggle reloads and the card opens the screen', (
    tester,
  ) async {
    final app = await pumpRoute(tester, AppRoutes.home, screenHeight: _height);

    await tester.tap(
      _inCard(
        find.byKey(PerformancePeriodToggle.periodKey(PerformancePeriod.year)),
      ),
    );
    await settle(tester);
    expect(app.read(performancePeriodProvider), PerformancePeriod.year);
    expect(find.byKey(HomeInvestmentsCard.cardKey), findsOneWidget);

    await tester.tap(_inCard(find.text(l10n.investmentsTitle)));
    await settle(tester);
    expect(app.location, AppRoutes.investments);
    expect(find.byType(InvestmentsScreen), findsOneWidget);
  });

  testWidgets('waits, fails, retries and masks the amounts', (tester) async {
    final repository = _repository();
    final pending = Completer<Result<InvestmentPerformance>>();
    when(() => repository.performance(any(), any()))
        .thenAnswer((_) => pending.future);
    await pumpRoute(
      tester,
      AppRoutes.home,
      screenHeight: _height,
      overrides: [
        investmentsRepositoryProvider.overrideWithValue(repository),
        hideAmountsProvider.overrideWithValue(true),
      ],
    );
    expect(_inCard(find.byType(PerformancePending)), findsOneWidget);

    pending.complete(const Err(NetworkFailure()));
    await settle(tester);
    expect(_inCard(find.text(l10n.homeSectionFailed)), findsOneWidget);

    when(() => repository.performance(any(), any()))
        .thenAnswer((_) async => Ok(_performance(cdi: null)));
    await tester.tap(find.byKey(HomeInvestmentsCard.retryKey));
    await settle(tester);
    expect(
      _inCard(
        find.text(
          l10n.investmentsPeriodYield(
            MoneyFormat.format(const Money(1_000), hide: true),
          ),
        ),
      ),
      findsOneWidget,
    );
    expect(_inCard(find.textContaining('CDI')), findsNothing);
  });

  testWidgets('hides without positions', (tester) async {
    final repository = _repository();
    when(() => repository.performance(any(), any()))
        .thenAnswer((_) async => Ok(_performance(positions: const [])));
    await pumpRoute(
      tester,
      AppRoutes.home,
      screenHeight: _height,
      overrides: [investmentsRepositoryProvider.overrideWithValue(repository)],
    );

    expect(find.byKey(HomeInvestmentsCard.cardKey), findsNothing);
  });

  testWidgets('the consolidated home shows it too', (tester) async {
    await pumpRoute(tester, AppRoutes.home, screenHeight: _height);
    await pickScope(tester, EntityScope.consolidated);

    expect(find.byKey(HomeInvestmentsCard.cardKey), findsOneWidget);
    expect(
      _inCard(find.text(MoneyFormat.format(const Money(5_059_340)))),
      findsOneWidget,
    );
  });
}
