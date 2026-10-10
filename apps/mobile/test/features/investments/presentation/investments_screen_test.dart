import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/home/presentation/balances_screen.dart';
import 'package:cashdeck/features/investments/domain/investments.dart';
import 'package:cashdeck/features/investments/domain/investments_repository.dart';
import 'package:cashdeck/features/investments/investments_providers.dart';
import 'package:cashdeck/features/investments/presentation/investments_labels.dart';
import 'package:cashdeck/features/investments/presentation/investments_screen.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
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
      expect(signedPercent(l10n, 5.23), '+5,23%');
      expect(signedPercent(l10n, -1.9), '-1,9%');
      expect(plainNumber(en, 1234.5), '1,234.5');
    });
  });

  testWidgets('shows the total, both splits and a position in detail', (
    tester,
  ) async {
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

    await tester.tap(find.byKey(InvestmentsScreen.positionKey('multimercado')));
    await settle(tester);
    expect(find.text(l10n.investmentDetailTwelveMonths), findsOneWidget);
    expect(find.text('+7,8%'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);

    await tester.tap(find.byKey(InvestmentsScreen.positionKey('fii')));
    await settle(tester);
    expect(find.text(l10n.investmentDetailQuantity), findsOneWidget);
    expect(find.text(l10n.investmentsPending), findsWidgets);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);

    await tester.tap(find.byKey(InvestmentsScreen.positionKey('cdb-aurora')));
    await settle(tester);
    expect(find.text(l10n.investmentDetailIssuer), findsOneWidget);
    expect(find.text(l10n.investmentDetailRate), findsOneWidget);
    expect(find.text(l10n.investmentDetailValuedOn), findsOneWidget);
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
    final repository = _MockInvestmentsRepository();
    var answer = const Ok<Investments>(_empty) as Result<Investments>;
    when(() => repository.investments(any())).thenAnswer((_) async => answer);
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

    await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
    await settle(tester);
    verify(() => repository.investments(any())).called(greaterThan(2));
  });
}
