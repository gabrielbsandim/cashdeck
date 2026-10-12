import 'dart:async';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/investments/presentation/investment_performance.dart';
import 'package:cashdeck/features/outlook/data/fake_outlook_repository.dart';
import 'package:cashdeck/features/outlook/domain/safe_to_spend.dart';
import 'package:cashdeck/features/outlook/outlook_providers.dart';
import 'package:cashdeck/features/outlook/presentation/count_up_amount.dart';
import 'package:cashdeck/features/outlook/presentation/safe_to_spend_card.dart';
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

void main() {
  testWidgets('is the first card and counts up to the daily amount', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.home);

    expect(find.byKey(SafeToSpendCard.cardKey), findsOneWidget);
    expect(_inCard(find.text(l10n.safeToSpendTitle)), findsOneWidget);
    expect(_inCard(find.byType(CountUpAmount)), findsOneWidget);
    expect(_inCard(find.text(_brl(20_947))), findsOneWidget);
    expect(_inCard(find.text(l10n.safeToSpendPerDay('20/10'))), findsOneWidget);
    expect(
      _inCard(find.text(l10n.safeToSpendTotal(_brl(251_370), 12))),
      findsOneWidget,
    );
    expect(
      _inCard(find.text(l10n.safeToSpendIncome(_brl(820_000), '20/10'))),
      findsOneWidget,
    );
  });

  testWidgets('the count starts low and lands on the amount', (tester) async {
    await tester.pumpApp(const CountUpAmount(Money(10_000)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text(_brl(10_000)), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text(_brl(10_000)), findsOneWidget);
  });

  testWidgets('a tap opens the breakdown down to what is free', (tester) async {
    await pumpRoute(tester, AppRoutes.home);

    await tester.tap(_inCard(find.text(l10n.safeToSpendTitle)));
    await settle(tester);

    expect(find.text(l10n.safeToSpendBreakdownTitle), findsOneWidget);
    expect(find.text(l10n.safeToSpendCash), findsOneWidget);
    expect(find.text('Condomínio Jardim'), findsOneWidget);
    expect(
      find.text(l10n.safeToSpendLineDue(l10n.safeToSpendLineCard, '18/10')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(SafeToSpendBreakdown.lineKey(5)),
        matching: find.text(l10n.safeToSpendLineReserve),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(SafeToSpendBreakdown.totalKey),
        matching: find.text(l10n.safeToSpendFree('20/10')),
      ),
      findsOneWidget,
    );
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
    expect(_inCard(find.byType(CountUpAmount)), findsNothing);

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
      _inCard(find.text(MoneyFormat.format(const Money(20_947), hide: true))),
      findsOneWidget,
    );
    expect(_inCard(find.text(_brl(20_947))), findsNothing);
  });

  test('every line kind has its own name', () {
    final names = {
      for (final kind in SafeToSpendLineKind.values)
        safeToSpendKindLabel(l10n, kind),
    };

    expect(names, hasLength(SafeToSpendLineKind.values.length));
  });
}
