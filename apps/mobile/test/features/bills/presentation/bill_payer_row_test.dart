import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/widgets/money/cd_confirm_sheet.dart';
import 'package:cashdeck/features/alerts/presentation/alerts_controller.dart';
import 'package:cashdeck/features/bills/bills_providers.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/bills/domain/bills_repository.dart';
import 'package:cashdeck/features/bills/presentation/bill_detail_screen.dart';
import 'package:cashdeck/features/bills/presentation/payment_ladder_view.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/pix_contacts/domain/pix_contact.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/builders.dart';
import '../../../support/mocks.dart';
import '../../../support/pump_app.dart';

void main() {
  late MockBillsRepository repository;

  setUpAll(() => registerFallbackValue(EntityKind.personal));
  setUp(() {
    repository = MockBillsRepository();
    when(() => repository.recipient(any())).thenAnswer(
      (_) async =>
          const Ok(PixRecipientCheck(name: 'Loja Exemplo', verified: true)),
    );
  });

  Future<void> open(
    WidgetTester tester,
    Bill bill, {
    bool confirmOnOpen = false,
  }) async {
    when(() => repository.get(bill.id)).thenAnswer((_) async => Ok(bill));
    when(
      () => repository.list(
        owner: any(named: 'owner'),
        cursor: any(named: 'cursor'),
      ),
    ).thenAnswer((_) async => Ok(BillPage(bills: [bill])));
    await tester.pumpApp(
      BillDetailScreen(billId: bill.id, confirmOnOpen: confirmOnOpen),
      overrides: [
        billsRepositoryProvider.overrideWithValue(repository),
        clockProvider.overrideWithValue(FixedClock(testNow)),
        unreadAlertsProvider.overrideWith((ref) async => 0),
      ],
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  Finder inSheet(String text) => find.descendant(
    of: find.byType(CdConfirmSheet),
    matching: find.text(text),
  );

  group('criterion 5: the confirm sheet names who pays', () {
    for (final (kind, label) in [
      (EntityKind.company, () => l10n.entityCompany),
      (EntityKind.personal, () => l10n.entityPersonal),
    ]) {
      testWidgets('a ${kind.name} bill pays with ${kind.name}', (tester) async {
        await open(
          tester,
          testBill(
            owner: kind,
            kind: BillKind.pixQr,
            paymentCode: '000201pix',
            status: BillStatus.needsConfirmation,
          ),
          confirmOnOpen: true,
        );

        expect(inSheet(l10n.sendPixFrom), findsOneWidget);
        expect(inSheet(label()), findsOneWidget);
      });
    }
  });

  group('criterion 5: the retry sheet names who pays', () {
    for (final (kind, label) in [
      (EntityKind.company, () => l10n.entityCompany),
      (EntityKind.personal, () => l10n.entityPersonal),
    ]) {
      testWidgets('a ${kind.name} bill retries with ${kind.name}', (
        tester,
      ) async {
        await open(
          tester,
          testBill(
            owner: kind,
            plan: const [LadderStep.automatic, LadderStep.assisted],
            attempts: [
              testAttempt(
                LadderStep.automatic,
                AttemptOutcome.failed,
                reason: 'Saldo insuficiente',
              ),
            ],
          ),
        );

        await tester.ensureVisible(find.byKey(PaymentLadderView.retryKey));
        await tester.tap(find.byKey(PaymentLadderView.retryKey));
        await tester.pumpAndSettle();

        expect(inSheet(l10n.sendPixFrom), findsOneWidget);
        expect(inSheet(label()), findsOneWidget);
      });
    }
  });
}
