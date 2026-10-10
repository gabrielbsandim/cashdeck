import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/home/presentation/balances_screen.dart';
import 'package:cashdeck/features/investments/data/fake_investments_repository.dart';
import 'package:cashdeck/features/investments/domain/investments.dart';
import 'package:cashdeck/features/investments/domain/investments_repository.dart';
import 'package:cashdeck/features/investments/investments_providers.dart';
import 'package:cashdeck/features/investments/presentation/investment_detail_screen.dart';
import 'package:cashdeck/features/investments/presentation/investment_performance.dart';
import 'package:cashdeck/features/investments/presentation/investments_controller.dart';
import 'package:cashdeck/features/investments/presentation/investments_labels.dart';
import 'package:cashdeck/features/investments/presentation/investments_screen.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/builders.dart';
import '../../../support/pump_app.dart';

final class _MockInvestmentsRepository extends Mock
    implements InvestmentsRepository;

const _empty = Investments(
  total: Money(0),
  invested: Money(0),
  profit: Money(0),
  institutions: [],
  kinds: [],
  positions: [],
);

const _bare = Investments(
  total: Money(0),
  invested: Money(0),
  profit: Money(0),
  institutions: [],
  kinds: [],
  positions: [
    InvestmentPosition(
      id: 'abroad',
      owner: EntityKind.personal,
      institutionId: 'x',
      institution: 'Broker',
      name: 'Global ETF',
      kind: InvestmentKind.etf,
      balance: Money(9_000, currency: 'USD'),
    ),
  ],
);

const _flat = InvestmentPerformance(
  period: PerformancePeriod.month,
  from: CalendarDate(2026, 9, 8),
  to: CalendarDate(2026, 10, 8),
  start: Money(0),
  end: Money(0),
  contributions: Money(0),
  withdrawals: Money(0),
  yieldAmount: Money(0),
  cdiPercent: 0.5,
  series: [],
);

Future<InvestmentPerformance> _fakePerformance(PerformancePeriod period) async {
  final result = await FakeInvestmentsRepository(
    FixedClock(testNow),
    latency: Duration.zero,
  ).performance(EntityScope.personal, period);
  return (result as Ok<InvestmentPerformance>).value;
}

void main() {
  group('labels', () {
    final en = lookupAppLocalizations(const Locale('en'));

    test('names every kind and the known subtypes', () {
      expect({
        for (final kind in InvestmentKind.values) investmentKindLabel(en, kind),
      }, hasLength(InvestmentKind.values.length));
      expect(investmentSubtypeLabel(l10n, 'TREASURY'), 'Tesouro Direto');
      expect(investmentSubtypeLabel(l10n, 'CDB'), 'CDB');
      expect(investmentSubtypeLabel(l10n, 'EXCHANGE_FUND'), 'EXCHANGE FUND');
      expect(investmentSubtypeLabel(l10n, null), isNull);
      for (final subtype in [
        'DEBENTURES',
        'STOCK',
        'REAL_ESTATE_FUND',
        'MULTIMARKET_FUND',
        'FIXED_INCOME_FUND',
        'STOCK_FUND',
        'INVESTMENT_FUND',
        'RETIREMENT',
      ]) {
        expect(investmentSubtypeLabel(en, subtype), isNot(contains('_')));
      }
    });

    test('names every period and movement kind', () {
      expect(
        PerformancePeriod.values.map(
          (period) => performancePeriodLabel(l10n, period),
        ),
        ['1s', '1m', '1a'],
      );
      expect({
        for (final kind in InvestmentMovementKind.values)
          movementKindLabel(en, kind),
      }, hasLength(InvestmentMovementKind.values.length));
      expect(movementKindLabel(l10n, InvestmentMovementKind.buy), 'Aplicação');
    });

    test('reads a rate as the issuer quotes it', () {
      expect(
        investmentRateLabel(
          l10n,
          const InvestmentRate(percent: 102.5, index: 'CDI'),
        ),
        '102,5% do CDI',
      );
      expect(
        investmentRateLabel(
          l10n,
          const InvestmentRate(percent: 100, index: 'IPCA', fixedAnnual: 6.2),
        ),
        'IPCA + 6,2% a.a.',
      );
      expect(
        investmentRateLabel(en, const InvestmentRate(fixedAnnual: 12)),
        '12% a year',
      );
      expect(
        investmentRateLabel(l10n, const InvestmentRate(index: 'CDI')),
        isNull,
      );
      expect(investmentRateLabel(l10n, null), isNull);
      expect(unsignedPercent(l10n, -1.25), '1,25%');
      expect(signedPercent(l10n, 5.23), '+5,23%');
      expect(signedPercent(l10n, -1.9), '-1,9%');
      expect(plainNumber(en, 1234.5), '1,234.5');
    });
  });

  testWidgets('shows the total, both splits and each position', (tester) async {
    await pumpRoute(tester, AppRoutes.investments, screenHeight: 3200);

    expect(find.byType(InvestmentsScreen), findsOneWidget);
    expect(find.byKey(InvestmentsScreen.totalKey), findsOneWidget);
    expect(
      find.text(MoneyFormat.format(const Money(3_059_340))),
      findsOneWidget,
    );
    expect(find.byKey(InvestmentsScreen.institutionKey('aurora')), findsOne);
    expect(
      find.byKey(InvestmentsScreen.kindKey(InvestmentKind.fixedIncome)),
      findsOneWidget,
    );
    expect(
      find.textContaining('${l10n.investmentsPositionCount(3)} · 78%'),
      findsOneWidget,
    );
    expect(find.textContaining('102% do CDI'), findsOneWidget);
    expect(find.textContaining('IPCA + 6,2% a.a.'), findsOneWidget);
    expect(find.textContaining(l10n.investmentsPending), findsOneWidget);
  });

  testWidgets('shows the window stats, the estimate and each position yield', (
    tester,
  ) async {
    final expected = (await tester.runAsync(
      () => _fakePerformance(PerformancePeriod.month),
    ))!;
    final app = await pumpRoute(
      tester,
      AppRoutes.investments,
      screenHeight: 3200,
    );

    Finder inStat(Key key, String text) =>
        find.descendant(of: find.byKey(key), matching: find.text(text));
    expect(
      inStat(
        PerformanceStats.yieldKey,
        MoneyFormat.format(expected.yieldAmount, sign: MoneySign.plus),
      ),
      findsOneWidget,
    );
    expect(
      inStat(
        PerformanceStats.percentKey,
        signedPercent(l10n, expected.yieldPercent!),
      ),
      findsOneWidget,
    );
    expect(
      inStat(PerformanceStats.cdiKey, '${expected.ofCdi}% do CDI'),
      findsOneWidget,
    );
    expect(
      inStat(
        PerformanceStats.contributionsKey,
        MoneyFormat.format(const Money(450_000)),
      ),
      findsOneWidget,
    );
    expect(
      inStat(
        PerformanceStats.withdrawalsKey,
        MoneyFormat.format(const Money(0)),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.investmentsEstimatedHint), findsOneWidget);
    final own = expected.positionOf('cdb-aurora')!;
    expect(
      find.descendant(
        of: find.byKey(InvestmentsScreen.positionYieldKey('cdb-aurora')),
        matching: find.text(
          MoneyFormat.format(own.yieldAmount, sign: MoneySign.plus),
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(PerformancePeriodToggle.periodKey(PerformancePeriod.week)),
    );
    await settle(tester);
    expect(app.read(performancePeriodProvider), PerformancePeriod.week);
    expect(find.text(l10n.investmentsEstimatedHint), findsNothing);

    await tester.tap(find.byKey(InvestmentsScreen.positionKey('multimercado')));
    await settle(tester);
    expect(app.location, AppRoutes.investment('multimercado'));
    expect(find.byType(InvestmentDetailScreen), findsOneWidget);
  });

  testWidgets('the balances screen opens the investments', (tester) async {
    await pumpRoute(tester, AppRoutes.balances);

    await tester.scrollUntilVisible(
      find.byKey(BalancesScreen.investmentsKey),
      300,
    );
    await tester.tap(find.byKey(BalancesScreen.investmentsKey));
    await settle(tester);
    expect(find.byType(InvestmentsScreen), findsOneWidget);
  });

  testWidgets('shows the empty, the error and a bare state', (tester) async {
    registerFallbackValue(EntityScope.personal);
    registerFallbackValue(PerformancePeriod.month);
    final repository = _MockInvestmentsRepository();
    var answer = const Ok<Investments>(_empty) as Result<Investments>;
    when(() => repository.investments(any())).thenAnswer((_) async => answer);
    when(() => repository.performance(any(), any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    final app = await pumpRoute(
      tester,
      AppRoutes.investments,
      overrides: [investmentsRepositoryProvider.overrideWithValue(repository)],
    );
    expect(find.byType(CdEmptyState), findsOneWidget);
    expect(find.text(l10n.investmentsEmpty), findsOneWidget);

    answer = const Err(NetworkFailure());
    app.router.go(AppRoutes.home);
    await settle(tester);
    app.router.go(AppRoutes.investments);
    await settle(tester);
    expect(find.byType(CdErrorState), findsOneWidget);

    answer = const Ok(_bare);
    await tester.tap(find.byType(CdButton));
    await settle(tester);
    expect(find.byKey(InvestmentsScreen.positionKey('abroad')), findsOneWidget);
    expect(find.text(l10n.investmentsByInstitution), findsNothing);
    expect(find.text(l10n.homeSectionFailed), findsOneWidget);

    when(() => repository.performance(any(), any()))
        .thenAnswer((_) async => const Ok(_flat));
    await tester.tap(find.byKey(InvestmentPerformanceCard.retryKey));
    await settle(tester);
    expect(find.byKey(PerformanceStats.percentKey), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(PerformanceStats.cdiKey),
        matching: find.text(l10n.investmentsCdi('0,5%')),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(InvestmentsScreen.positionYieldKey('abroad')),
      findsNothing,
    );

    await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
    await settle(tester);
    verify(() => repository.investments(any())).called(greaterThan(2));
  });
}
