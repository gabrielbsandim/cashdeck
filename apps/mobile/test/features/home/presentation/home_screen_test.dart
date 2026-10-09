import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/widgets/money/privacy_toggle.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/automation/automation_providers.dart';
import 'package:cashdeck/features/automation/domain/automation.dart';
import 'package:cashdeck/features/automation/presentation/automation_controller.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_switcher.dart';
import 'package:cashdeck/features/home/domain/home_summary.dart';
import 'package:cashdeck/features/home/home_providers.dart';
import 'package:cashdeck/features/home/presentation/company_home.dart';
import 'package:cashdeck/features/home/presentation/consolidated_home.dart';
import 'package:cashdeck/features/home/presentation/home_labels.dart';
import 'package:cashdeck/features/home/presentation/home_screen.dart';
import 'package:cashdeck/features/home/presentation/home_sections.dart';
import 'package:cashdeck/features/home/presentation/personal_home.dart';
import 'package:cashdeck/features/transactions/presentation/transfer_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/builders.dart';
import '../../../support/mocks.dart';
import '../../../support/pump_app.dart';

void main() {
  Future<void> pickScope(WidgetTester tester, EntityScope scope) async {
    await tester.tap(find.byKey(EntityChip.chipKey));
    await settle(tester);
    await tester.tap(find.byKey(EntityChip.optionKey(scope)));
    await settle(tester);
  }

  testWidgets('Início Pessoal shows balance, reserve, forecast and alerts', (
    tester,
  ) async {
    final app = await pumpRoute(tester, AppRoutes.home);

    expect(find.byType(PersonalHome), findsOneWidget);
    expect(find.text(l10n.reserveTitle), findsOneWidget);
    expect(find.text(l10n.forecastTitle), findsOneWidget);
    expect(find.text(l10n.alertAssistedTitle('Aluguel')), findsOneWidget);
    expect(
      find.text('Acima do limite por pagamento, sem confirmação no app'),
      findsOneWidget,
    );
    expect(
      find.text(l10n.alertBudgetTitle(l10n.categoryRestaurants)),
      findsOneWidget,
    );
    expect(find.byKey(const Key('home-bill-bill-energy')), findsOneWidget);

    await tester.tap(find.byKey(HomeScreen.alertsKey));
    await settle(tester);
    expect(app.location, AppRoutes.alerts);
    app.router.pop();
    await settle(tester);

    await tester.tap(find.byKey(PersonalHome.alertsSeeAllKey));
    await settle(tester);
    expect(find.byKey(const Key('sheet-alert-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sheet-alert-1')));
    await tester.tapAt(const Offset(200, 20));
    await settle(tester);

    await tester.tap(find.byKey(PersonalHome.alertsSeeAllKey));
    await settle(tester);
    await tester.tap(find.byKey(const Key('sheet-alert-0')));
    await settle(tester);
    expect(app.location, AppRoutes.bill('bill-rent'));
  });

  testWidgets('privacy hides the figures inside alerts and labels', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.home);
    expect(find.textContaining('600'), findsWidgets);

    await tester.tap(find.byKey(PrivacyToggle.buttonKey));
    await settle(tester);

    expect(find.textContaining(r'R$ 600'), findsNothing);
    expect(find.textContaining('••••'), findsWidgets);
    expect(find.textContaining('18.742,30'), findsNothing);
  });

  testWidgets('the due list and a due bill lead to A pagar', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.home);

    await tester.tap(find.byKey(const Key('home-bill-bill-energy')));
    await settle(tester);
    expect(app.location, AppRoutes.bill('bill-energy'));

    app.router.go(AppRoutes.home);
    await settle(tester);
    await tester.tap(find.byKey(DueSoonSection.seeAllKey));
    await settle(tester);
    expect(app.location, AppRoutes.bills);
  });

  testWidgets('Início Empresa approves a draft and invoices a Pix', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.home);
    await pickScope(tester, EntityScope.company);

    expect(find.byType(CompanyHome), findsOneWidget);
    await tester.tap(find.byKey(CompanyHome.editKey('draft-pomar')));
    await settle(tester);
    expect(find.text(l10n.draftEditSoon), findsOneWidget);

    await tester.tap(find.byKey(CompanyHome.approveKey('draft-pomar')));
    await settle(tester);
    expect(find.text(l10n.invoiceIssuedToast('Pomar Digital')), findsOneWidget);
    expect(find.byKey(CompanyHome.approveKey('draft-pomar')), findsNothing);

    await tester.tap(find.byKey(CompanyHome.issueKey('receipt-pix-lia')));
    await settle(tester);
    expect(find.text(l10n.invoiceIssuedToast('Lia Moreira')), findsOneWidget);
    expect(find.byKey(CompanyHome.issueKey('receipt-pix-lia')), findsNothing);
  });

  testWidgets('Início Consolidado splits the total and opens a transfer', (
    tester,
  ) async {
    final app = await pumpRoute(tester, AppRoutes.home);
    await pickScope(tester, EntityScope.consolidated);

    expect(find.byType(ConsolidatedHome), findsOneWidget);
    expect(find.byKey(HomeScreen.alertsKey), findsOneWidget);
    expect(find.text(l10n.transferProLabore), findsOneWidget);

    await tester.tap(
      find.byKey(ConsolidatedHome.transferKey('transfer-prolabore')),
    );
    await settle(tester);
    expect(app.location, AppRoutes.transfer('transfer-prolabore'));
    expect(find.byType(TransferDetailScreen), findsOneWidget);
  });

  testWidgets('the paused banner resumes payments', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.home);
    final pausing = app
        .read(automationControllerProvider.notifier)
        .setPaused(paused: true);
    await settle(tester);
    expect(await pausing, isNull);

    expect(find.text(l10n.automationPausedTitle), findsOneWidget);
    await tester.tap(find.byKey(PausedBanner.resumeKey));
    await settle(tester);

    expect(find.text(l10n.automationPausedTitle), findsNothing);
  });

  testWidgets('a failed resume says why and keeps the banner', (tester) async {
    final automation = MockAutomationRepository();
    when(automation.status)
        .thenAnswer((_) async => Ok(AutomationStatus(pausedSince: testNow)));
    when(automation.resume)
        .thenAnswer((_) async => const Err(NetworkFailure()));
    await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [automationRepositoryProvider.overrideWithValue(automation)],
    );

    await tester.tap(find.byKey(PausedBanner.resumeKey));
    await settle(tester);

    expect(find.text(l10n.errorNetwork), findsOneWidget);
    expect(find.text(l10n.automationPausedTitle), findsOneWidget);
  });

  testWidgets('a failed load retries, a failed action says why', (
    tester,
  ) async {
    final home = MockHomeRepository();
    when(home.personal).thenAnswer((_) async => const Err(ServerFailure()));
    await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [homeRepositoryProvider.overrideWithValue(home)],
    );
    expect(find.text(l10n.errorServer), findsOneWidget);

    final company = CompanySummary(
      cash: const Money(100_000),
      sync: SyncInfo(accountCount: 1, syncedAt: testNow),
      billed: const Money(0),
      invoiceCount: 0,
      dasEstimate: const Money(0),
      dasDue: testToday.addDays(10),
      drafts: const [
        InvoiceDraft(
          id: 'draft-pomar',
          customer: 'Cliente Exemplo',
          amount: Money(50_000),
          recurring: false,
          issueOn: testToday,
        ),
      ],
      unbilled: const [],
    );
    when(home.company).thenAnswer((_) async => Ok(company));
    when(() => home.approveDraft('draft-pomar'))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    await tester.tap(find.byKey(CdErrorState.retryKey));
    await settle(tester);
    await pickScope(tester, EntityScope.company);
    await tester.tap(find.byKey(CompanyHome.approveKey('draft-pomar')));
    await settle(tester);

    expect(find.text(l10n.errorNetwork), findsOneWidget);
  });

  testWidgets('an empty alerts sheet says so', (tester) async {
    late BuildContext context;
    await tester.pumpApp(
      Builder(
        builder: (inner) {
          context = inner;
          return const SizedBox();
        },
      ),
    );

    showAlertsSheet(context, const []).ignore();
    await tester.pumpAndSettle();

    expect(find.text(l10n.alertsEmpty), findsOneWidget);
  });

  testWidgets('relative days and month names read in Portuguese', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpApp(
      Builder(
        builder: (inner) {
          context = inner;
          return const SizedBox();
        },
      ),
    );

    expect(relativeDay(l10n, testToday, testToday), l10n.relativeToday);
    expect(
      relativeDay(l10n, testToday.addDays(-1), testToday),
      l10n.relativeYesterday,
    );
    expect(relativeDay(l10n, testToday.addDays(-3), testToday), '05/10');
    expect(capitalized(monthName(context, testToday)), 'Outubro');
    expect(monthShort(context, testToday), startsWith('out'));
    expect(capitalized(''), '');
    expect(
      BudgetCategory.values
          .map(
            (c) => budgetCategoryLabel(
              l10n,
              BudgetSummary(
                category: c,
                spent: const Money(0),
                limit: const Money(0),
                name: 'pets',
              ),
            ),
          )
          .toSet(),
      hasLength(BudgetCategory.values.length),
    );
  });
}
