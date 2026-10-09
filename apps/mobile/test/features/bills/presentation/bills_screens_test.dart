import 'dart:async';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/security/biometric_authenticator.dart';
import 'package:cashdeck/core/share/file_sharer.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/widgets/insights/cd_calendar_month.dart';
import 'package:cashdeck/core/widgets/money/cd_confirm_sheet.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/alerts/presentation/alerts_controller.dart';
import 'package:cashdeck/features/bills/bills_providers.dart';
import 'package:cashdeck/features/bills/data/fake_bills_repository.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/bills/domain/bills_repository.dart';
import 'package:cashdeck/features/bills/presentation/bill_detail_screen.dart';
import 'package:cashdeck/features/bills/presentation/bills_screen.dart';
import 'package:cashdeck/features/bills/presentation/payment_ladder_view.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/receipts/presentation/receipt_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/builders.dart';
import '../../../support/mocks.dart';
import '../../../support/pump_app.dart';

void main() {
  group('on the fake backend', () {
    testWidgets('the calendar narrows the list to one day and back', (
      tester,
    ) async {
      await pumpRoute(tester, AppRoutes.bills);
      expect(find.byType(CdCalendarMonth), findsOneWidget);

      await tester.tap(find.byKey(CdCalendarMonth.dayKey(12)));
      await settle(tester);
      expect(find.byKey(BillsScreen.tileKey('bill-energy')), findsOneWidget);
      expect(find.text(l10n.billsGroupSettled), findsNothing);

      await tester.tap(find.byKey(CdCalendarMonth.dayKey(1)));
      await settle(tester);
      expect(find.text(l10n.billsNoneOnDay), findsOneWidget);

      await tester.tap(find.text(l10n.billsCalendarClear));
      await settle(tester);
      expect(find.text(l10n.billsGroupSettled), findsOneWidget);

      await tester.tap(find.byKey(CdCalendarMonth.dayKey(12)));
      await settle(tester);
      await tester.tap(find.byKey(CdCalendarMonth.dayKey(12)));
      await settle(tester);
      expect(find.text(l10n.billsGroupSettled), findsOneWidget);
    });

    testWidgets('groups the bills and tags the entity when consolidated', (
      tester,
    ) async {
      final app = await pumpRoute(tester, AppRoutes.bills);

      expect(find.text(l10n.billsGroupNeedsYou), findsOneWidget);
      expect(find.text(l10n.billsGroupUpcoming), findsOneWidget);
      expect(find.text(l10n.billsGroupSettled), findsOneWidget);
      expect(find.text('Coworking Ponte'), findsNothing);

      await pickScope(tester, EntityScope.consolidated);
      await settle(tester);
      expect(
        find.text(l10n.billTitleWithEntity('Coworking Ponte', 'PJ')),
        findsOneWidget,
      );
      await pickScope(tester, EntityScope.personal);
      await settle(tester);

      await tester.tap(find.byKey(BillsScreen.tileKey('bill-energy')));
      await settle(tester);
      expect(app.location, AppRoutes.bill('bill-energy'));
      expect(find.byType(BillDetailScreen), findsOneWidget);
    });

    testWidgets('marks a step 3 bill paid, undoes it and keeps it', (
      tester,
    ) async {
      await pumpRoute(tester, AppRoutes.bill('bill-rent'));
      expect(find.text('3 · ${l10n.ladderReadyTitle}'), findsOneWidget);
      expect(find.byKey(BillDetailScreen.copyCodeKey), findsNothing);
      expect(find.byKey(PaymentLadderView.copyKey), findsOneWidget);

      await tester.tap(find.byKey(PaymentLadderView.markPaidKey));
      await settle(tester);
      expect(find.text(l10n.billMarkedPaidToast('Aluguel')), findsOneWidget);
      expect(find.text(l10n.billStatusPaid), findsOneWidget);

      await tester.tap(find.text(l10n.undoButton));
      await settle(tester);
      expect(find.text(l10n.billStatusPaid), findsNothing);

      await tester.tap(find.byKey(PaymentLadderView.markPaidKey));
      await settle(tester);
      await waitForToast(tester);
      expect(find.text(l10n.billStatusPaid), findsOneWidget);
      expect(find.text(l10n.ladderSettled, findRichText: true), findsNothing);
    });

    testWidgets('the receipt button opens the receipt of the bill', (
      tester,
    ) async {
      final app = await pumpRoute(tester, AppRoutes.bill('bill-rent'));

      await tester.tap(find.byKey(PaymentLadderView.receiptKey));
      await settle(tester);

      expect(app.location, AppRoutes.billReceipt('bill-rent'));
      expect(find.byType(ReceiptViewerScreen), findsOneWidget);
    });

    testWidgets('a paid bill views and shares its receipt', (tester) async {
      final sharer = FakeFileSharer();
      final app = await pumpRoute(
        tester,
        AppRoutes.bill('bill-condo'),
        overrides: [fileSharerProvider.overrideWithValue(sharer)],
      );

      await tester.tap(find.byKey(BillDetailScreen.shareReceiptKey));
      await settle(tester);
      expect(sharer.files.single.name, endsWith('.pdf'));

      await tester.tap(find.byKey(BillDetailScreen.viewReceiptKey));
      await settle(tester);
      expect(app.location, AppRoutes.billReceipt('bill-condo'));
    });

    testWidgets('pages the list with the button until it ends', (tester) async {
      await pumpRoute(
        tester,
        AppRoutes.bills,
        overrides: [
          billsRepositoryProvider.overrideWithValue(
            FakeBillsRepository(
              FixedClock(testNow),
              latency: Duration.zero,
              pageSize: 3,
            ),
          ),
        ],
      );
      final tiles = find.byWidgetPredicate((widget) => widget is BillTile);
      expect(tiles, findsNWidgets(3));

      while (find.byKey(BillsScreen.loadMoreKey).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(BillsScreen.loadMoreKey));
        await settle(tester);
      }

      expect(tiles.evaluate().length, greaterThan(3));
      expect(find.text(l10n.billsGroupSettled), findsOneWidget);
    });

    testWidgets('a bank approval step offers the bank and a recheck', (
      tester,
    ) async {
      await pumpRoute(tester, AppRoutes.bill('bill-coworking'));

      expect(find.text(l10n.ladderNextApprove), findsOneWidget);
      expect(find.text(l10n.ladderWaitingForYou), findsOneWidget);
      await tester.tap(find.byKey(PaymentLadderView.openBankKey));
      await settle(tester);
      expect(find.text(l10n.openBankToast), findsOneWidget);

      await tester.tap(find.byKey(PaymentLadderView.approvedKey));
      await settle(tester);
      expect(find.text(l10n.approvalCheckToast), findsOneWidget);
    });

    testWidgets('a bill above the cap is confirmed with the device check', (
      tester,
    ) async {
      final biometrics = FakeBiometricAuthenticator();
      await pumpRoute(
        tester,
        AppRoutes.bill('bill-gym'),
        overrides: [
          biometricAuthenticatorProvider.overrideWithValue(biometrics),
        ],
      );
      expect(find.text(l10n.billStatusNeedsConfirmation), findsWidgets);

      await tester.tap(find.byKey(PaymentLadderView.confirmKey));
      await settle(tester);
      expect(find.text(l10n.confirmReasonNewPayee), findsOneWidget);
      await tester.tap(find.byKey(CdConfirmSheet.confirmKey));
      await settle(tester);

      expect(find.text(l10n.billConfirmedToast), findsOneWidget);
      expect(find.text(l10n.billStatusScheduled), findsWidgets);
      expect(biometrics.reasons, [l10n.confirmBillTitle('Academia Ritmo')]);
    });

    testWidgets('declining the confirmation changes nothing', (tester) async {
      await pumpRoute(tester, AppRoutes.bill('bill-gym'));

      await tester.tap(find.byKey(PaymentLadderView.confirmKey));
      await settle(tester);
      await tester.tap(find.byKey(CdConfirmSheet.secondaryKey));
      await settle(tester);

      expect(find.text(l10n.billConfirmedToast), findsNothing);
    });

    testWidgets('a step 1 failure on a personal bill jumps to step 3', (
      tester,
    ) async {
      await pumpRoute(tester, AppRoutes.bill('bill-internet'));

      expect(find.text(l10n.ladderJumped(3, '07:00')), findsOneWidget);
      expect(find.text(l10n.ladderStateUnavailable), findsOneWidget);
    });

    testWidgets('a bolepix offers the Pix first, then the barcode', (
      tester,
    ) async {
      await pumpRoute(tester, AppRoutes.bill('bill-internet'));

      expect(find.textContaining(l10n.billKindBolepix), findsOneWidget);
      final pix = tester.getTopLeft(find.byKey(PaymentLadderView.copyPixKey));
      final barcode = tester.getTopLeft(find.byKey(PaymentLadderView.copyKey));
      expect(pix.dy, lessThan(barcode.dy));
      expect(
        find.textContaining(
          l10n.attemptVia(l10n.paymentMethodPix, 'Pagador PF'),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          l10n.attemptVia(l10n.paymentMethodBoleto, 'Pagador PF'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a bolepix before step 3 shows both codes on top', (
      tester,
    ) async {
      final bills = FakeBillsRepository(
        FixedClock(testNow),
        latency: Duration.zero,
      );
      await pumpRoute(
        tester,
        AppRoutes.bill('bill-1'),
        overrides: [
          billsRepositoryProvider.overrideWithValue(
            _Single(
              testBill(
                plan: const [LadderStep.automatic, LadderStep.assisted],
                pixCode: '000201pix',
              ),
              bills,
            ),
          ),
        ],
      );

      expect(find.byKey(BillDetailScreen.copyPixKey), findsOneWidget);
      expect(find.byKey(BillDetailScreen.copyCodeKey), findsOneWidget);
    });
  });

  group('on a mocked repository', () {
    late MockBillsRepository repository;

    List<Override> overrides() => [
      billsRepositoryProvider.overrideWithValue(repository),
      clockProvider.overrideWithValue(FixedClock(testNow)),
      unreadAlertsProvider.overrideWith((ref) async => 0),
    ];

    setUpAll(() => registerFallbackValue(EntityKind.personal));
    setUp(() => repository = MockBillsRepository());

    Future<Result<BillPage>> Function() listCall() =>
        () => repository.list(
          owner: any(named: 'owner'),
          cursor: any(named: 'cursor'),
        );

    testWidgets('shows the empty state', (tester) async {
      when(listCall()).thenAnswer((_) async => const Ok(BillPage(bills: [])));

      await tester.pumpApp(const BillsScreen(), overrides: overrides());
      await tester.pump();

      expect(find.text(l10n.billsEmptyTitle), findsOneWidget);
    });

    testWidgets('a failed list offers a retry', (tester) async {
      when(listCall()).thenAnswer((_) async => const Err(NetworkFailure()));

      await tester.pumpApp(const BillsScreen(), overrides: overrides());
      await tester.pump();
      expect(find.text(l10n.errorNetwork), findsOneWidget);

      when(listCall())
          .thenAnswer((_) async => Ok(BillPage(bills: [testBill()])));
      await tester.tap(find.byKey(CdErrorState.retryKey));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(BillsScreen.tileKey('bill-1')), findsOneWidget);
      expect(find.text(MoneyFormat.format(testBill().amount)), findsOneWidget);
    });

    testWidgets('shows the bill, copies its code and walks the ladder', (
      tester,
    ) async {
      final bill = testBill(
        status: BillStatus.awaitingApproval,
        attempts: [
          testAttempt(
            LadderStep.automatic,
            AttemptOutcome.failed,
            rail: 'RailA',
            reason: 'Sem saldo',
          ),
          testAttempt(
            LadderStep.bankApproval,
            AttemptOutcome.waiting,
            rail: 'RailB',
          ),
        ],
      );
      when(() => repository.get('bill-1')).thenAnswer((_) async => Ok(bill));
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          }
          return null;
        },
      );

      await tester.pumpApp(
        const BillDetailScreen(billId: 'bill-1'),
        overrides: overrides(),
      );
      await tester.pump();

      expect(find.text(bill.payee), findsOneWidget);
      expect(find.text(l10n.ladderStateFailed), findsOneWidget);
      expect(find.text('RailA, Sem saldo'), findsOneWidget);
      expect(find.text(l10n.ladderSteppedDown(2, '12:00')), findsOneWidget);
      for (final step in LadderStep.values) {
        expect(find.byKey(PaymentLadderView.stepKey(step)), findsOneWidget);
      }

      await tester.tap(find.byKey(BillDetailScreen.copyCodeKey));
      await tester.pump();

      expect(copied, ['12345.67890']);
      expect(find.text(l10n.copied), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a step 3 bill after two failures collapses the past', (
      tester,
    ) async {
      when(() => repository.get('bill-1')).thenAnswer(
        (_) async => Ok(
          testBill(
            kind: BillKind.pixKey,
            paymentCode: null,
            attempts: [
              testAttempt(LadderStep.automatic, AttemptOutcome.failed),
              testAttempt(
                LadderStep.bankApproval,
                AttemptOutcome.failed,
                reason: 'Prazo expirou',
              ),
            ],
          ),
        ),
      );

      await tester.pumpApp(
        const BillDetailScreen(billId: 'bill-1'),
        overrides: overrides(),
      );
      await tester.pump();

      expect(
        find.text(l10n.ladderCollapsed('12:00', 'Prazo expirou', 1)),
        findsOneWidget,
      );
      expect(find.text(l10n.ladderReadyPixKey('08/10')), findsOneWidget);
      expect(find.byKey(PaymentLadderView.copyKey), findsNothing);
    });

    testWidgets('a paid bill pops its badge and hides the code', (
      tester,
    ) async {
      when(() => repository.get('bill-1')).thenAnswer(
        (_) async => Ok(
          testBill(
            status: BillStatus.paid,
            kind: BillKind.pixQr,
            plan: const [LadderStep.automatic, LadderStep.assisted],
            attempts: [
              testAttempt(LadderStep.automatic, AttemptOutcome.succeeded),
            ],
          ),
        ),
      );

      await tester.pumpApp(
        const BillDetailScreen(billId: 'bill-1'),
        overrides: overrides(),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(BillDetailScreen.copyCodeKey), findsNothing);
      expect(find.text(l10n.ladderStateDone), findsOneWidget);
      expect(find.text(l10n.ladderStateUnavailable), findsOneWidget);
      expect(find.text(l10n.ladderStateSkipped), findsOneWidget);
    });

    testWidgets('a failed mark puts the bill back and says why', (
      tester,
    ) async {
      final bill = testBill(
        plan: const [LadderStep.automatic, LadderStep.assisted],
        attempts: [testAttempt(LadderStep.automatic, AttemptOutcome.failed)],
      );
      when(() => repository.get('bill-1')).thenAnswer((_) async => Ok(bill));
      when(() => repository.markPaid('bill-1'))
          .thenAnswer((_) async => const Err(ServerFailure()));
      when(listCall()).thenAnswer((_) async => Ok(BillPage(bills: [bill])));

      await tester.pumpApp(
        const BillDetailScreen(billId: 'bill-1'),
        overrides: overrides(),
      );
      await tester.pump();
      await tester.tap(find.byKey(PaymentLadderView.markPaidKey));
      await tester.pumpAndSettle();
      await waitForToast(tester);

      expect(find.text(l10n.errorServer), findsOneWidget);
      expect(find.text(l10n.billStatusPaid), findsNothing);
      verify(() => repository.markPaid('bill-1')).called(1);
    });

    Answer<Future<Result<BillPage>>> pages(
      Map<String?, Future<Result<BillPage>> Function()> byCursor,
    ) =>
        (invocation) => byCursor[invocation.namedArguments[#cursor]]!();

    List<Bill> many(int count, {int from = 0}) => [
      for (var index = from; index < from + count; index++)
        testBill(id: 'bill-$index', dueDate: testToday.addDays(index + 5)),
    ];

    testWidgets('a failed page keeps what loaded and tries again', (
      tester,
    ) async {
      var failNext = true;
      when(listCall()).thenAnswer(
        pages({
          null: () async => Ok(BillPage(bills: many(1), nextCursor: 'c1')),
          'c1': () async {
            if (!failNext) return Ok(BillPage(bills: many(1, from: 1)));
            failNext = false;
            return const Err(NetworkFailure());
          },
        }),
      );

      await tester.pumpApp(const BillsScreen(), overrides: overrides());
      await tester.pump();
      await tester.tap(find.byKey(BillsScreen.loadMoreKey));
      await tester.pump();

      expect(find.text(l10n.errorNetwork), findsOneWidget);
      expect(find.byKey(BillsScreen.tileKey('bill-0')), findsOneWidget);

      await tester.tap(find.byKey(BillsScreen.loadMoreKey));
      await tester.pump();

      expect(find.byKey(BillsScreen.tileKey('bill-1')), findsOneWidget);
      expect(find.byKey(BillsScreen.loadMoreKey), findsNothing);
      expect(find.text(l10n.errorNetwork), findsNothing);
    });

    testWidgets('a page in flight shows progress and is asked once', (
      tester,
    ) async {
      final next = Completer<Result<BillPage>>();
      when(listCall()).thenAnswer(
        pages({
          null: () async => Ok(BillPage(bills: many(1), nextCursor: 'c1')),
          'c1': () => next.future,
        }),
      );

      await tester.pumpApp(const BillsScreen(), overrides: overrides());
      await tester.pump();
      await tester.tap(find.byKey(BillsScreen.loadMoreKey));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      next.complete(Ok(BillPage(bills: many(1, from: 1))));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      verify(
        () => repository.list(
          owner: any(named: 'owner'),
          cursor: 'c1',
        ),
      ).called(1);
    });

    testWidgets('scrolling near the end loads the next page', (tester) async {
      when(listCall()).thenAnswer(
        pages({
          null: () async => Ok(BillPage(bills: many(40), nextCursor: 'c1')),
          'c1': () async => Ok(BillPage(bills: many(1, from: 40))),
        }),
      );

      await tester.pumpApp(const BillsScreen(), overrides: overrides());
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -6000));
      await tester.pumpAndSettle();

      verify(
        () => repository.list(
          owner: any(named: 'owner'),
          cursor: 'c1',
        ),
      ).called(1);
    });

    testWidgets('sharing a receipt the bank has not sent says why', (
      tester,
    ) async {
      when(() => repository.get('bill-1'))
          .thenAnswer((_) async => Ok(testBill(status: BillStatus.paid)));

      await tester.pumpApp(
        const BillDetailScreen(billId: 'bill-1'),
        overrides: overrides(),
      );
      await tester.pump();
      await tester.tap(find.byKey(BillDetailScreen.shareReceiptKey));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text(l10n.errorNotFound), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('auto debit hides the ladder and shows its chip', (
      tester,
    ) async {
      final bill = testBill(status: BillStatus.needsConfirmation);
      final debited = testBill(
        status: BillStatus.needsConfirmation,
        autoDebit: true,
      );
      when(() => repository.get('bill-1')).thenAnswer((_) async => Ok(bill));
      when(() => repository.setAutoDebit('bill-1', enabled: true))
          .thenAnswer((_) async => Ok(debited));
      when(() => repository.setAutoDebit('bill-1', enabled: false))
          .thenAnswer((_) async => const Err(NetworkFailure()));
      when(listCall()).thenAnswer((_) async => Ok(BillPage(bills: [bill])));

      await tester.pumpApp(
        const BillDetailScreen(billId: 'bill-1'),
        overrides: overrides(),
      );
      await tester.pump();
      expect(find.byKey(PaymentLadderView.confirmKey), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byKey(BillDetailScreen.autoDebitKey),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(PaymentLadderView.confirmKey), findsNothing);
      expect(find.byKey(BillDetailScreen.copyCodeKey), findsNothing);
      expect(find.text(l10n.billAutoDebit), findsNWidgets(2));

      await tester.tap(
        find.descendant(
          of: find.byKey(BillDetailScreen.autoDebitKey),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.errorNetwork), findsOneWidget);
    });

    testWidgets('a failed confirmation says why', (tester) async {
      final bill = testBill(status: BillStatus.needsConfirmation);
      when(() => repository.get('bill-1')).thenAnswer((_) async => Ok(bill));
      when(() => repository.pay('bill-1', confirmed: true))
          .thenAnswer((_) async => const Err(NetworkFailure()));
      when(listCall()).thenAnswer((_) async => Ok(BillPage(bills: [bill])));

      await tester.pumpApp(
        const BillDetailScreen(billId: 'bill-1'),
        overrides: overrides(),
      );
      await tester.pump();
      expect(
        find.text(l10n.ladderConfirmBody(l10n.confirmReasonGeneric)),
        findsOneWidget,
      );
      await tester.tap(find.byKey(PaymentLadderView.confirmKey));
      await tester.pumpAndSettle();
      expect(find.text(l10n.confirmReasonGeneric), findsOneWidget);
      await tester.tap(find.byKey(CdConfirmSheet.confirmKey));
      await tester.pumpAndSettle();

      expect(find.text(l10n.errorNetwork), findsOneWidget);
    });

    testWidgets('a failed load offers a retry', (tester) async {
      when(() => repository.get('bill-1'))
          .thenAnswer((_) async => const Err(NotFoundFailure()));

      await tester.pumpApp(
        const BillDetailScreen(billId: 'bill-1'),
        overrides: overrides(),
      );
      await tester.pump();
      expect(find.text(l10n.errorNotFound), findsOneWidget);

      when(() => repository.get('bill-1'))
          .thenAnswer((_) async => Ok(testBill()));
      await tester.tap(find.byKey(CdErrorState.retryKey));
      await tester.pump();
      await tester.pump();

      expect(find.text(testBill().payee), findsOneWidget);
    });
  });
}

final class _Single implements BillsRepository {
  const new(this.bill, this.inner);

  final Bill bill;
  final BillsRepository inner;

  @override
  Future<Result<BillPage>> list({EntityKind? owner, String? cursor}) async =>
      Ok(BillPage(bills: [bill]));

  @override
  Future<Result<Bill>> get(String id) async => Ok(bill);

  @override
  Future<Result<Bill>> markPaid(String id) => inner.markPaid(id);

  @override
  Future<Result<Bill>> pay(String id, {required bool confirmed}) =>
      inner.pay(id, confirmed: confirmed);

  @override
  Future<Result<Bill>> setAutoDebit(String id, {required bool enabled}) =>
      inner.setAutoDebit(id, enabled: enabled);
}
