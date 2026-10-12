import 'dart:typed_data';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/file_chooser.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/loans/loans_providers.dart';
import 'package:cashdeck/features/loans/presentation/loans_screen.dart';
import 'package:cashdeck/features/loans/presentation/prepayment_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/pump_app.dart';
import '../application/loans_use_cases_test.dart' show MockLoansRepository;
import '../loan_builders.dart';

const _seeded = 'loan-home';

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

void main() {
  setUpAll(() => registerFallbackValue(const Money(0)));

  testWidgets('shows the loan and simulates a prepayment', (tester) async {
    await pumpRoute(tester, AppRoutes.loans);

    expect(find.byKey(LoansScreen.cardKey(_seeded)), findsOneWidget);
    expect(find.text(l10n.loanProgress(12, 360, 3)), findsOneWidget);
    expect(find.text(l10n.loanPaidTotal), findsOneWidget);
    expect(find.textContaining('24.000,00'), findsOneWidget);
    expect(find.textContaining('multa e juros de atraso'), findsOneWidget);
    expect(find.text(l10n.loanRateValue('11,50', 'TR')), findsOneWidget);

    await _tap(tester, find.byKey(LoansScreen.prepayKey(_seeded)));
    expect(find.text(l10n.loanPrepayYield('11,50', 'TR')), findsOneWidget);
    await tester.enterText(find.byKey(PrepaymentSheet.amountKey), '150000');
    await tester.pump();
    await _tap(tester, find.byKey(PrepaymentSheet.runKey));

    expect(find.byKey(PrepaymentSheet.resultKey), findsOneWidget);
    expect(find.text(l10n.loanPrepayMonths(3)), findsOneWidget);
  });

  testWidgets('imports a statement and refuses another file', (tester) async {
    final chooser = FakeFileChooser(
      LocalFile(name: 'extrato.pdf', bytes: Uint8List(2)),
    );
    await pumpRoute(
      tester,
      AppRoutes.loans,
      overrides: [fileChooserProvider.overrideWithValue(chooser)],
    );

    await _tap(tester, find.byKey(LoansScreen.importKey));
    expect(chooser.requests.single, ['pdf']);
    expect(find.text(l10n.loansImported), findsOneWidget);
    expect(find.text('Banco Exemplo 2002'), findsOneWidget);

    chooser.next = LocalFile(name: 'foto.jpg', bytes: Uint8List(2));
    await _tap(tester, find.byKey(LoansScreen.importKey));
    expect(find.text('The file is not a loan statement.'), findsOneWidget);

    chooser.next = null;
    await _tap(tester, find.byKey(LoansScreen.importKey));
    expect(chooser.requests, hasLength(3));
  });

  testWidgets('deletes a loan and explains how to import one', (tester) async {
    await pumpRoute(tester, AppRoutes.loans);

    await _tap(tester, find.byKey(LoansScreen.menuKey(_seeded)));
    await _tap(tester, find.byKey(LoansScreen.deleteKey));
    await _tap(tester, find.text(l10n.cancelButton));
    expect(find.byKey(LoansScreen.cardKey(_seeded)), findsOneWidget);

    await _tap(tester, find.byKey(LoansScreen.menuKey(_seeded)));
    await _tap(tester, find.byKey(LoansScreen.deleteKey));
    await _tap(tester, find.byKey(LoansScreen.confirmDeleteKey));

    expect(find.text(l10n.loanDeleted), findsOneWidget);
    expect(find.text(l10n.loansEmptyTitle), findsOneWidget);
    expect(find.text(l10n.loansImport), findsOneWidget);
  });

  testWidgets('a failed load can be retried', (tester) async {
    final repository = MockLoansRepository();
    when(repository.list).thenAnswer((_) async => const Err(NetworkFailure()));
    await pumpRoute(
      tester,
      AppRoutes.loans,
      overrides: [loansRepositoryProvider.overrideWithValue(repository)],
    );

    expect(find.byType(CdErrorState), findsOneWidget);
    await _tap(tester, find.byKey(CdErrorState.retryKey));
    verify(repository.list).called(2);
  });

  testWidgets('says why a prepayment could not be simulated', (tester) async {
    final repository = MockLoansRepository();
    when(repository.list).thenAnswer((_) async => Ok([loanWith()]));
    when(() => repository.prepayment(any(), any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    await pumpRoute(
      tester,
      AppRoutes.loans,
      overrides: [loansRepositoryProvider.overrideWithValue(repository)],
    );

    await _tap(tester, find.byKey(LoansScreen.prepayKey('loan-1')));
    await tester.enterText(find.byKey(PrepaymentSheet.amountKey), '100000');
    await tester.pump();
    await _tap(tester, find.byKey(PrepaymentSheet.runKey));

    expect(find.byKey(PrepaymentSheet.errorKey), findsOneWidget);
    expect(find.byKey(PrepaymentSheet.resultKey), findsNothing);
  });
}
