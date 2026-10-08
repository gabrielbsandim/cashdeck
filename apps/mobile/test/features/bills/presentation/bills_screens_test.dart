import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/security/biometric_authenticator.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/widgets/money/cd_confirm_sheet.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/bills/bills_providers.dart';
import 'package:cashdeck/features/bills/data/fake_bills_repository.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/bills/domain/bills_repository.dart';
import 'package:cashdeck/features/bills/presentation/bill_detail_screen.dart';
import 'package:cashdeck/features/bills/presentation/bills_screen.dart';
import 'package:cashdeck/features/bills/presentation/payment_ladder_view.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_switcher.dart';
import 'package:cashdeck/features/receipts/presentation/receipt_viewer_screen.dart';
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
    testWidgets('groups the bills and tags the entity when consolidated', (
      tester,
    ) async {
      final app = await pumpRoute(tester, AppRoutes.bills);

      expect(find.text(l10n.billsGroupNeedsYou), findsOneWidget);
      expect(find.text(l10n.billsGroupUpcoming), findsOneWidget);
      expect(find.text(l10n.billsGroupSettled), findsOneWidget);
      expect(find.text('Coworking Ponte'), findsNothing);

      await tester.tap(
        find.byKey(EntitySwitcher.segmentKey(EntityScope.consolidated)),
      );
      await settle(tester);
      expect(
        find.text(l10n.billTitleWithEntity('Coworking Ponte', 'PJ')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(EntitySwitcher.segmentKey(EntityScope.personal)),
      );
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
    ];

    setUp(() => repository = MockBillsRepository());

    testWidgets('shows the empty state', (tester) async {
      when(repository.list).thenAnswer((_) async => const Ok([]));

      await tester.pumpApp(const BillsScreen(), overrides: overrides());
      await tester.pump();

      expect(find.text(l10n.billsEmptyTitle), findsOneWidget);
    });

    testWidgets('a failed list offers a retry', (tester) async {
      when(repository.list)
          .thenAnswer((_) async => const Err(NetworkFailure()));

      await tester.pumpApp(const BillsScreen(), overrides: overrides());
      await tester.pump();
      expect(find.text(l10n.errorNetwork), findsOneWidget);

      when(repository.list).thenAnswer((_) async => Ok([testBill()]));
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
      when(repository.list).thenAnswer((_) async => Ok([bill]));

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

    testWidgets('a failed confirmation says why', (tester) async {
      final bill = testBill(status: BillStatus.needsConfirmation);
      when(() => repository.get('bill-1')).thenAnswer((_) async => Ok(bill));
      when(() => repository.confirmPayment('bill-1'))
          .thenAnswer((_) async => const Err(NetworkFailure()));
      when(repository.list).thenAnswer((_) async => Ok([bill]));

      await tester.pumpApp(
        const BillDetailScreen(billId: 'bill-1'),
        overrides: overrides(),
      );
      await tester.pump();
      await tester.tap(find.byKey(PaymentLadderView.confirmKey));
      await tester.pumpAndSettle();
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
  Future<Result<List<Bill>>> list() async => Ok([bill]);

  @override
  Future<Result<Bill>> get(String id) async => Ok(bill);

  @override
  Future<Result<Bill>> markPaid(String id) => inner.markPaid(id);

  @override
  Future<Result<Bill>> confirmPayment(String id) => inner.confirmPayment(id);
}
