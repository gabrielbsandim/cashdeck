import 'dart:async';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/result/result.dart';
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
  monthlyAverage: Money(120_000),
  months: 1,
  upcoming: Money(30_000),
  expected: Money(5_000),
  pixReserve: Money(2_000),
  topUp: Money(0),
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
  testWidgets('shows the monthly average and what to send now', (tester) async {
    await pumpRoute(tester, AppRoutes.home, screenHeight: _height);

    expect(find.byKey(HomeFundingCard.cardKey), findsOneWidget);
    expect(
      _inCard(find.text(MoneyFormat.format(const Money(218_500)))),
      findsOneWidget,
    );
    expect(_inCard(find.text(l10n.fundingAverage(3))), findsOneWidget);
    expect(
      _inCard(
        find.text(
          l10n.fundingUpcoming(
            MoneyFormat.format(const Money(96_300)),
            MoneyFormat.format(const Money(55_000)),
            MoneyFormat.format(const Money(30_000)),
          ),
        ),
      ),
      findsOneWidget,
    );
    expect(
      _inCard(
        find.text(l10n.fundingBalance(MoneyFormat.format(const Money(42_000)))),
      ),
      findsOneWidget,
    );
    expect(
      _inCard(
        find.text(l10n.fundingTopUp(MoneyFormat.format(const Money(139_300)))),
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
    expect(_inCard(find.text(l10n.fundingAverage(1))), findsOneWidget);
    expect(
      _inCard(
        find.text(
          l10n.fundingUpcoming(
            MoneyFormat.format(const Money(30_000), hide: true),
            MoneyFormat.format(const Money(5_000), hide: true),
            MoneyFormat.format(const Money(2_000), hide: true),
          ),
        ),
      ),
      findsOneWidget,
    );
    expect(_inCard(find.text(l10n.fundingCovered)), findsOneWidget);
  });

  testWidgets('hides without bills', (tester) async {
    await _pump(
      tester,
      () async => const Ok(
        FundingPlan(
          balance: Money(0),
          monthlyAverage: Money(0),
          months: 1,
          upcoming: Money(0),
          expected: Money(0),
          pixReserve: Money(0),
          topUp: Money(0),
        ),
      ),
    );

    expect(find.byKey(HomeFundingCard.cardKey), findsNothing);
  });
}
