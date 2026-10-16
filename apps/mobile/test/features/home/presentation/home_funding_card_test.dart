import 'dart:async';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/home/application/home_use_cases.dart';
import 'package:cashdeck/features/home/domain/home_summary.dart';
import 'package:cashdeck/features/home/home_providers.dart';
import 'package:cashdeck/features/home/presentation/home_funding_card.dart';
import 'package:cashdeck/features/investments/presentation/investment_performance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/mocks.dart';
import '../../../support/pump_app.dart';

const double _height = 4200;

const _covered = FundingPlan(
  balance: null,
  needed: Money(30_000),
  topUp: Money(0),
  lines: [
    FundingLine(
      name: 'Escola',
      amount: Money(30_000),
      on: CalendarDate(2026, 10, 20),
      kind: FundingLineKind.bill,
    ),
  ],
  debit: FundingDebit(
    name: 'Banco Azul',
    balance: Money(90_000),
    total: Money(80_000),
    topUp: Money(0),
  ),
);

Finder _inCard(Finder matching) => find.descendant(
  of: find.byKey(HomeFundingCard.cardKey),
  matching: matching,
);

Future<MockHomeRepository> _pump(
  WidgetTester tester,
  Future<Result<FundingPlan>> Function() answer, {
  bool hide = false,
}) async {
  final repository = MockHomeRepository();
  when(repository.funding).thenAnswer((_) => answer());
  await pumpRoute(
    tester,
    AppRoutes.home,
    screenHeight: _height,
    overrides: [
      loadFundingPlanProvider.overrideWithValue(LoadFundingPlan(repository)),
      hideAmountsProvider.overrideWithValue(hide),
    ],
  );
  return repository;
}

void main() {
  testWidgets('lists the next 30 days and what to send now', (tester) async {
    await pumpRoute(tester, AppRoutes.home, screenHeight: _height);

    expect(find.byKey(HomeFundingCard.cardKey), findsOneWidget);
    expect(
      _inCard(
        find.text(l10n.fundingTopUp(MoneyFormat.format(const Money(139_300)))),
      ),
      findsOneWidget,
    );
    expect(
      _inCard(
        find.text(
          l10n.fundingNeeds(
            MoneyFormat.format(const Money(181_300)),
            MoneyFormat.format(const Money(42_000)),
          ),
        ),
      ),
      findsOneWidget,
    );
    expect(_inCard(find.text(l10n.fundingLinePix)), findsOneWidget);
    expect(_inCard(find.text('Internet Rede')), findsOneWidget);
    expect(_inCard(find.text('Condominio')), findsOneWidget);
    expect(
      _inCard(find.text(l10n.fundingLineExpected('Plano de Saude'))),
      findsOneWidget,
    );
    expect(_inCard(find.text('02/11')), findsOneWidget);
    expect(
      _inCard(
        find.text(
          l10n.fundingMonthly(MoneyFormat.format(const Money(181_300))),
        ),
      ),
      findsOneWidget,
    );
    expect(
      _inCard(
        find.text(
          l10n.fundingDebit(
            'Banco Azul',
            MoneyFormat.format(const Money(210_000)),
            MoneyFormat.format(const Money(150_000)),
          ),
        ),
      ),
      findsOneWidget,
    );
    expect(
      _inCard(
        find.text(
          l10n.fundingDebitTopUp(
            MoneyFormat.format(const Money(60_000)),
            'Banco Azul',
          ),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('waits, fails, retries and says when the balance covers', (
    tester,
  ) async {
    final pending = Completer<Result<FundingPlan>>();
    final repository = await _pump(tester, () => pending.future, hide: true);
    expect(_inCard(find.byType(PerformancePending)), findsOneWidget);

    pending.complete(const Err(NetworkFailure()));
    await settle(tester);
    expect(_inCard(find.text(l10n.homeSectionFailed)), findsOneWidget);

    when(repository.funding).thenAnswer((_) async => const Ok(_covered));
    await tester.tap(find.byKey(HomeFundingCard.retryKey));
    await settle(tester);
    expect(
      _inCard(
        find.text(
          l10n.fundingNeedsUnknown(
            MoneyFormat.format(const Money(30_000), hide: true),
          ),
        ),
      ),
      findsOneWidget,
    );
    expect(_inCard(find.text('Escola')), findsOneWidget);
    expect(_inCard(find.text(l10n.fundingCovered)), findsOneWidget);
    expect(
      _inCard(find.text(l10n.fundingDebitCovered('Banco Azul'))),
      findsOneWidget,
    );
  });

  testWidgets('hides when nothing is coming', (tester) async {
    await _pump(
      tester,
      () async => const Ok(
        FundingPlan(
          balance: Money(0),
          needed: Money(0),
          topUp: Money(0),
          lines: [],
        ),
      ),
    );

    expect(find.byKey(HomeFundingCard.cardKey), findsNothing);
  });
}
