import 'dart:async';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/money/cd_count_up.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/home/presentation/company_home.dart';
import 'package:cashdeck/features/investments/presentation/investment_performance.dart';
import 'package:cashdeck/features/outlook/data/fake_outlook_repository.dart';
import 'package:cashdeck/features/outlook/domain/safe_to_spend.dart';
import 'package:cashdeck/features/outlook/outlook_providers.dart';
import 'package:cashdeck/features/outlook/presentation/income_sources_sheet.dart';
import 'package:cashdeck/features/outlook/presentation/net_worth_card.dart';
import 'package:cashdeck/features/outlook/presentation/safe_to_spend_card.dart';
import 'package:cashdeck/features/outlook/presentation/savings_target_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/builders.dart';
import '../../../support/pump_app.dart';
import '../outlook_support.dart';

Finder _inCard(Finder matching) => find.descendant(
  of: find.byKey(SafeToSpendCard.cardKey),
  matching: matching,
);

String _brl(int cents) => MoneyFormat.format(Money(cents));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

Future<void> _openBreakdown(WidgetTester tester) =>
    _tap(tester, _inCard(find.text(l10n.safeToSpendTitle)));

Finder _savingsLine() => find.byKey(SafeToSpendBreakdown.lineKey(1));

/// Over the month's plan and short in checking for the next 30 days.
const SafeToSpend _overspent = SafeToSpend(
  asOf: testToday,
  basis: SafeToSpendBasis.month,
  cash: Money(10_000),
  total: Money(-30_000),
  daily: Money(0),
  days: 24,
  until: CalendarDate(2026, 10, 31),
  shortBy: Money(30_000),
  cashShortBy: Money(70_000),
  plan: SpendingPlan(
    income: Money(500_000),
    typical: Money(400_000),
    received: Money(500_000),
    savings: Money(100_000),
    savingsSet: true,
    months: 1,
  ),
  lines: [
    SafeToSpendLine(
      kind: SafeToSpendLineKind.income,
      label: '',
      amount: Money(500_000),
    ),
    SafeToSpendLine(
      kind: SafeToSpendLineKind.savings,
      label: '',
      amount: Money(-100_000),
    ),
    SafeToSpendLine(
      kind: SafeToSpendLineKind.spentCard,
      label: '',
      amount: Money(-430_000),
    ),
  ],
);

void main() {
  testWidgets('is the first card and counts up to the daily amount', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.home);

    expect(find.byKey(SafeToSpendCard.cardKey), findsOneWidget);
    expect(_inCard(find.text(l10n.safeToSpendTitle)), findsOneWidget);
    expect(_inCard(find.byType(CdCountUp)), findsOneWidget);
    expect(_inCard(find.text(_brl(33_671))), findsOneWidget);
    expect(_inCard(find.text(l10n.safeToSpendPerDay('31/10'))), findsOneWidget);
    expect(
      _inCard(find.text(l10n.safeToSpendTotal(_brl(808_110), 24))),
      findsOneWidget,
    );
    expect(
      _inCard(find.text(l10n.safeToSpendPlan(_brl(2_400_000), _brl(650_000)))),
      findsOneWidget,
    );
  });

  testWidgets('the company home shows its own figure and net worth', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.home, screenHeight: 5200);
    await pickScope(tester, EntityScope.company);

    expect(find.byType(CompanyHome), findsOneWidget);
    expect(find.byKey(NetWorthCard.cardKey), findsOneWidget);
    expect(_inCard(find.text(_brl(41_775))), findsOneWidget);
    expect(_inCard(find.text(l10n.safeToSpendNoIncome)), findsOneWidget);

    await tester.tap(_inCard(find.text(l10n.safeToSpendTitle)));
    await settle(tester);
    expect(find.text('Software'), findsOneWidget);
    expect(find.text(l10n.safeToSpendLineBudgetReserved), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byKey(SafeToSpendBreakdown.totalKey),
        matching: find.text(l10n.safeToSpendFree('31/10')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the count starts low and lands on the amount', (tester) async {
    await tester.pumpApp(const CdAmount(Money(10_000), countUp: true));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text(_brl(10_000)), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text(_brl(10_000)), findsOneWidget);
  });

  testWidgets('a tap opens the plan down to what is free', (tester) async {
    await pumpRoute(tester, AppRoutes.home);

    await _openBreakdown(tester);

    expect(find.text(l10n.safeToSpendBreakdownTitle), findsOneWidget);
    expect(find.text(l10n.safeToSpendCash), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(SafeToSpendBreakdown.lineKey(0)),
        matching: find.text(l10n.safeToSpendLineIncomeMedian(3)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _savingsLine(),
        matching: find.text(l10n.safeToSpendLineSavingsTypical),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.safeToSpendLineSpentCard), findsOneWidget);
    expect(find.text('Condomínio Jardim'), findsOneWidget);
    expect(
      find.text(l10n.safeToSpendLineDue(l10n.safeToSpendLineFixed, '31/10')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(SafeToSpendBreakdown.totalKey),
        matching: find.text(l10n.safeToSpendFree('31/10')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the savings line sets the target and goes back to typical', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.home);

    await _openBreakdown(tester);
    await _tap(tester, _savingsLine());
    expect(find.text(l10n.safeToSpendBreakdownTitle), findsNothing);
    expect(find.byKey(SavingsTargetSheet.typicalKey), findsNothing);
    await tester.enterText(find.byKey(SavingsTargetSheet.amountKey), '300000');
    await tester.pump();
    await _tap(tester, find.byKey(SavingsTargetSheet.saveKey));
    expect(find.text(l10n.savingsTargetSaved), findsOneWidget);
    expect(
      _inCard(find.text(l10n.safeToSpendPlan(_brl(2_400_000), _brl(300_000)))),
      findsOneWidget,
    );

    // The first sheet scrolled the title under the app bar.
    await _tap(tester, _inCard(find.text(l10n.safeToSpendPerDay('31/10'))));
    expect(find.text(l10n.safeToSpendLineSavingsSet), findsOneWidget);
    await _tap(tester, _savingsLine());
    await _tap(tester, find.byKey(SavingsTargetSheet.typicalKey));
    expect(
      _inCard(find.text(l10n.safeToSpendPlan(_brl(2_400_000), _brl(650_000)))),
      findsOneWidget,
    );
  });

  testWidgets('the income line picks the payers counted as income', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.home);

    await _openBreakdown(tester);
    await _tap(tester, find.byKey(SafeToSpendBreakdown.lineKey(0)));
    expect(find.text(l10n.incomeSourcesHelp), findsOneWidget);
    expect(find.text('Cliente Exemplo LTDA'), findsOneWidget);
    await _tap(tester, find.byKey(incomeSourceKey('11222333000181')));
    await _tap(tester, find.byKey(incomeSourceKey('52998224725')));
    await _tap(tester, find.byKey(incomeSourceKey('52998224725')));
    await _tap(tester, find.byKey(incomeSourcesSaveKey));
    expect(find.text(l10n.incomeSourcesSaved), findsOneWidget);
  });

  testWidgets('the payers wait, fail, retry and may be none', (tester) async {
    final repository = outlookRepository();
    when(repository.safeToSpend).thenAnswer((_) async => const Ok(_overspent));
    when(() => repository.netWorth(any(), any()))
        .thenAnswer((_) async => Ok(netWorthOf()));
    when(repository.incomeSources)
        .thenAnswer((_) async => const Err(NetworkFailure()));
    when(() => repository.setIncomeSources(any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [outlookRepositoryProvider.overrideWithValue(repository)],
    );

    await _openBreakdown(tester);
    expect(find.text(l10n.safeToSpendLineIncomeReceived), findsOneWidget);
    await _tap(tester, find.byKey(SafeToSpendBreakdown.lineKey(0)));
    expect(find.byKey(IncomeSourcesSheet.retryKey), findsOneWidget);

    when(repository.incomeSources).thenAnswer((_) async => const Ok([]));
    await _tap(tester, find.byKey(IncomeSourcesSheet.retryKey));
    expect(find.text(l10n.incomeSourcesEmpty), findsOneWidget);
    await _tap(tester, find.byKey(incomeSourcesSaveKey));
    expect(find.byKey(incomeSourcesErrorKey), findsOneWidget);
    verify(() => repository.setIncomeSources(const [])).called(1);
  });

  testWidgets('says why the target was not saved', (tester) async {
    final repository = outlookRepository();
    when(repository.safeToSpend).thenAnswer((_) async => const Ok(_overspent));
    when(() => repository.netWorth(any(), any()))
        .thenAnswer((_) async => Ok(netWorthOf()));
    when(() => repository.setSavingsTarget(any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [outlookRepositoryProvider.overrideWithValue(repository)],
    );

    expect(
      _inCard(find.text(l10n.safeToSpendOverBy(_brl(30_000)))),
      findsOneWidget,
    );
    expect(
      _inCard(find.text(l10n.safeToSpendCashShort(_brl(70_000)))),
      findsOneWidget,
    );

    await _openBreakdown(tester);
    await _tap(tester, _savingsLine());
    await _tap(tester, find.byKey(SavingsTargetSheet.saveKey));
    expect(find.byKey(SavingsTargetSheet.errorKey), findsOneWidget);
    verify(() => repository.setSavingsTarget(const Money(100_000))).called(1);
  });

  testWidgets('says how short it is when the bills outrun the cash', (
    tester,
  ) async {
    final repository = outlookRepository();
    when(repository.safeToSpend).thenAnswer((_) async => Ok(shortSafeToSpend));
    when(() => repository.netWorth(any(), any()))
        .thenAnswer((_) async => Ok(netWorthOf()));
    await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [outlookRepositoryProvider.overrideWithValue(repository)],
    );

    expect(_inCard(find.text(l10n.safeToSpendShort('31/10'))), findsOneWidget);
    expect(
      _inCard(find.text(l10n.safeToSpendShortBy(_brl(12_000)))),
      findsOneWidget,
    );
    expect(_inCard(find.text(l10n.safeToSpendNoIncome)), findsOneWidget);
    expect(_inCard(find.byType(CdCountUp)), findsNothing);

    await tester.tap(_inCard(find.text(l10n.safeToSpendNoIncome)));
    await settle(tester);
    expect(
      find.descendant(
        of: find.byKey(SafeToSpendBreakdown.lineKey(0)),
        matching: find.text(l10n.safeToSpendLineBill),
      ),
      findsOneWidget,
    );
    expect(
      find.text(l10n.safeToSpendLineDue(l10n.safeToSpendLineBill, '10/10')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(SafeToSpendBreakdown.totalKey),
        matching: find.text(_brl(-12_000)),
      ),
      findsOneWidget,
    );
  });

  testWidgets('waits, fails, retries and masks the amounts', (tester) async {
    final repository = outlookRepository();
    final pending = Completer<Result<SafeToSpend>>();
    when(repository.safeToSpend).thenAnswer((_) => pending.future);
    when(() => repository.netWorth(any(), any()))
        .thenAnswer((_) async => Ok(netWorthOf()));
    await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [
        outlookRepositoryProvider.overrideWithValue(repository),
        hideAmountsProvider.overrideWithValue(true),
      ],
    );
    expect(_inCard(find.byType(PerformancePending)), findsOneWidget);

    pending.complete(const Err(NetworkFailure()));
    await settle(tester);
    expect(_inCard(find.text(l10n.homeSectionFailed)), findsOneWidget);

    final fake = FakeOutlookRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    );
    when(repository.safeToSpend).thenAnswer((_) => fake.safeToSpend());
    await tester.tap(find.byKey(SafeToSpendCard.retryKey));
    await settle(tester);
    expect(
      _inCard(find.text(MoneyFormat.format(const Money(33_671), hide: true))),
      findsOneWidget,
    );
    expect(_inCard(find.text(_brl(33_671))), findsNothing);
  });

  test('every line kind has its own name', () {
    final names = {
      for (final kind in SafeToSpendLineKind.values)
        safeToSpendKindLabel(l10n, kind),
    };

    expect(names, hasLength(SafeToSpendLineKind.values.length));
  });
}
