import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/charts/cd_line_chart.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/investments/domain/investments.dart';
import 'package:cashdeck/features/investments/domain/investments_repository.dart';
import 'package:cashdeck/features/investments/investments_providers.dart';
import 'package:cashdeck/features/investments/presentation/investment_detail_screen.dart';
import 'package:cashdeck/features/investments/presentation/investment_performance.dart';
import 'package:cashdeck/features/investments/presentation/investments_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/builders.dart';
import '../../../support/pump_app.dart';

final class _MockInvestmentsRepository extends Mock
    implements InvestmentsRepository;

const _bare = InvestmentDetail(
  position: InvestmentPosition(
    id: 'bare',
    owner: EntityKind.personal,
    institutionId: 'x',
    institution: 'Broker',
    name: 'Bare fund',
    kind: InvestmentKind.other,
    balance: Money(1_000),
  ),
  performance: InvestmentPerformance(
    period: PerformancePeriod.month,
    from: CalendarDate(2026, 9, 8),
    to: CalendarDate(2026, 10, 8),
    start: Money(1_000),
    end: Money(1_000),
    contributions: Money(0),
    withdrawals: Money(0),
    yieldAmount: Money(0),
    series: [],
  ),
  movements: [],
);

Finder _movement(String id, String text) => find.descendant(
  of: find.byKey(InvestmentDetailScreen.movementKey(id)),
  matching: find.textContaining(text),
);

void main() {
  testWidgets('shows the facts, the rate, the window and each movement', (
    tester,
  ) async {
    final today = CalendarDate.brazilToday(testNow);
    await pumpRoute(
      tester,
      AppRoutes.investment('tesouro-ipca'),
      screenHeight: 3200,
    );

    expect(find.byType(InvestmentDetailScreen), findsOneWidget);
    expect(find.text('Tesouro IPCA+ 2035'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(InvestmentDetailScreen.balanceKey),
        matching: find.text(MoneyFormat.format(const Money(830_000))),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(InvestmentDetailScreen.rateKey),
        matching: find.text('IPCA + 6,2% a.a.'),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.investmentsInvested), findsOneWidget);
    expect(find.text(l10n.investmentDetailProfitTotal), findsOneWidget);
    expect(find.text(today.addDays(3300).display), findsOneWidget);
    expect(find.byType(CdLineChart), findsOneWidget);
    expect(find.byKey(PerformanceStats.yieldKey), findsOneWidget);

    expect(_movement('m-2', l10n.investmentMovementBuy), findsOneWidget);
    expect(_movement('m-2', 'Qtd. 0,5'), findsOneWidget);
    expect(_movement('m-2', today.addDays(-20).display), findsOneWidget);
    expect(_movement('m-3', l10n.investmentMovementIncome), findsOneWidget);
    expect(
      _movement(
        'm-3',
        MoneyFormat.format(const Money(12_400), sign: MoneySign.plus),
      ),
      findsOneWidget,
    );
    expect(_movement('m-4', 'Qtd. 2'), findsOneWidget);
  });

  testWidgets('a sale and a tax, then another window', (tester) async {
    final app = await pumpRoute(
      tester,
      AppRoutes.investment('cdb-empresa'),
      screenHeight: 3200,
    );

    expect(_movement('m-8', l10n.investmentMovementSell), findsOneWidget);
    expect(_movement('m-9', l10n.investmentMovementTax), findsOneWidget);
    expect(
      _movement('m-9', MoneyFormat.format(const Money(-2_300))),
      findsOneWidget,
    );
    expect(find.textContaining('104% do CDI'), findsWidgets);

    await tester.tap(
      find.byKey(PerformancePeriodToggle.periodKey(PerformancePeriod.year)),
    );
    await settle(tester);
    expect(app.read(performancePeriodProvider), PerformancePeriod.year);
    expect(find.text(l10n.investmentsEstimatedHint), findsOneWidget);
    expect(find.byKey(PerformanceStats.contributionsKey), findsOneWidget);
  });

  testWidgets('a missing position fails, then a bare one loads', (
    tester,
  ) async {
    registerFallbackValue(PerformancePeriod.month);
    final repository = _MockInvestmentsRepository();
    var answer = const Err<InvestmentDetail>(
      NotFoundFailure(),
    ) as Result<InvestmentDetail>;
    when(() => repository.position(any(), any()))
        .thenAnswer((_) async => answer);
    await pumpRoute(
      tester,
      AppRoutes.investment('bare'),
      overrides: [investmentsRepositoryProvider.overrideWithValue(repository)],
    );
    expect(find.byType(CdErrorState), findsOneWidget);
    expect(find.text(l10n.investmentsTitle), findsOneWidget);

    answer = const Ok(_bare);
    await tester.tap(find.byType(CdButton));
    await settle(tester);
    expect(find.text('Bare fund'), findsWidgets);
    expect(find.text(l10n.investmentNoMovements), findsOneWidget);
    expect(find.byType(CdLineChart), findsNothing);
    expect(find.byKey(InvestmentDetailScreen.rateKey), findsNothing);
    expect(find.text(l10n.investmentsInvested), findsNothing);
  });
}
