import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/features/bills/application/bills_use_cases.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/bills/presentation/bill_labels.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../support/builders.dart';
import '../../../support/pump_app.dart';

void main() {
  final assisted = testBill(
    plan: const [LadderStep.automatic, LadderStep.assisted],
    attempts: [testAttempt(LadderStep.automatic, AttemptOutcome.failed)],
  );

  test('an auto debit bill never reads as overdue or as waiting', () {
    final debited = testBill(
      dueDate: testToday.addDays(-2),
      status: BillStatus.needsConfirmation,
      autoDebit: true,
    );

    expect(billStatusOf(l10n, debited, testToday).$1, l10n.billAutoDebit);
    expect(billHomeStatusOf(l10n, debited, testToday).$1, l10n.billAutoDebit);
    expect(billLadderHint(l10n, debited), l10n.billAutoDebitHint);
    expect(billsNeedingYou([debited], testToday), isEmpty);
  });

  test('a bill without a payee is called by its kind', () {
    expect(billPayeeOf(l10n, testBill(payee: ' ')), l10n.billKindBoleto);
    expect(
      billPayeeOf(l10n, testBill(payee: '', kind: BillKind.pixQr)),
      l10n.billKindPixQr,
    );
    expect(billPayeeOf(l10n, testBill()), 'Payee Example');
    expect(
      billPayeeOf(l10n, testBill(payee: 'billing@example-health.com.br')),
      'Example-health',
    );
    expect(billPayeeOf(l10n, testBill(payee: 'not @ mail')), 'not @ mail');
  });

  test('overdue wins over the stored status, step 3 reads as assisted', () {
    final overdue = testBill(dueDate: testToday.addDays(-2));

    expect(billStatusOf(l10n, overdue, testToday), (
      l10n.billStatusOverdue,
      MoneyTone.overdue,
    ));
    expect(billStatusOf(l10n, assisted, testToday), (
      l10n.billStatusAssisted,
      MoneyTone.assisted,
    ));
    expect(billHomeStatusOf(l10n, overdue, testToday).$1, l10n.billHomeOverdue);
  });

  test('Início says when an automatic payment goes out', () {
    final scheduled = testBill(
      status: BillStatus.scheduled,
      dueDate: testToday.addDays(4),
    );

    expect(billHomeStatusOf(l10n, scheduled, testToday), (
      l10n.billHomeAutomatic('12/10'),
      MoneyTone.scheduled,
    ));
    expect(
      billHomeStatusOf(l10n, testBill(), testToday).$1,
      l10n.billStatusPending,
    );
  });

  test('the hint says who paid or where the bill is on the ladder', () {
    final byUser = testBill(status: BillStatus.paid).markedPaid(testNow);
    final byRail = testBill(status: BillStatus.paid);
    final cancelled = testBill(status: BillStatus.cancelled);
    final tried = testBill(
      attempts: [
        testAttempt(
          LadderStep.automatic,
          AttemptOutcome.waiting,
          rail: 'Pix via API',
        ),
      ],
    );

    expect(billLadderHint(l10n, byUser), l10n.billPaidByYou);
    expect(billLadderHint(l10n, byRail), l10n.billPaidAutomatically);
    expect(
      billLadderHint(l10n, _paidBy(PaidBy.statement)),
      l10n.billPaidInStatement,
    );
    expect(billLadderHint(l10n, cancelled), '');
    expect(billLadderHint(l10n, assisted), l10n.billHintAssisted(3));
    expect(billLadderHint(l10n, tried), l10n.billHintStep(1, 'Pix via API'));
    expect(
      billLadderHint(l10n, testBill()),
      l10n.billHintStep(1, l10n.ladderStepAutomatic),
    );
  });

  test('the due line counts down and shows when a bill was paid', () {
    final paid = testBill(status: BillStatus.paid).markedPaid(testNow);

    expect(
      billDueLabel(l10n, paid, testToday),
      l10n.billPaidOn('08/10', '12:00'),
    );
    expect(
      billDueLabel(l10n, testBill(dueDate: testToday.addDays(-2)), testToday),
      l10n.billOverdueSince('06/10'),
    );
    expect(billDueLabel(l10n, testBill(), testToday), l10n.billDueToday);
    expect(
      billDueLabel(l10n, testBill(dueDate: testToday.addDays(1)), testToday),
      l10n.billDueTomorrow('09/10'),
    );
    expect(
      billDueLabel(l10n, testBill(dueDate: testToday.addDays(5)), testToday),
      l10n.billDueInDays('13/10', 5),
    );
  });

  test('the icon follows the payee, taxes get the bank', () {
    expect(billIconOf(testBill(payee: 'Energia Lumina')), Symbols.bolt_rounded);
    expect(
      billIconOf(testBill(payee: 'Academia')),
      Symbols.fitness_center_rounded,
    );
    expect(
      billIconOf(testBill(kind: BillKind.taxBarcode)),
      Symbols.account_balance_rounded,
    );
    expect(billIconOf(testBill()), Symbols.receipt_long_rounded);
  });

  test('every status, kind, source, step and entity has a distinct label', () {
    final statuses = {
      for (final status in BillStatus.values)
        billStatusOf(l10n, testBill(status: status), testToday).$1,
    };
    final kinds = BillKind.values.map((kind) => billKindLabel(l10n, kind));
    final sources = BillSource.values.map(
      (source) => billSourceLabel(l10n, source),
    );
    final titles = LadderStep.values.map((step) => ladderStepTitle(l10n, step));
    final hints = LadderStep.values.map((step) => ladderStepHint(l10n, step));
    final entities = EntityKind.values.map(
      (kind) => entityKindLabel(l10n, kind),
    );

    expect(statuses, hasLength(BillStatus.values.length));
    expect(kinds.toSet(), hasLength(BillKind.values.length));
    expect(sources.toSet(), hasLength(BillSource.values.length));
    expect(titles.toSet(), hasLength(LadderStep.values.length));
    expect(hints.toSet(), hasLength(LadderStep.values.length));
    expect(entities.toSet(), hasLength(EntityKind.values.length));
  });
}

Bill _paidBy(PaidBy by) {
  final bill = testBill(status: BillStatus.paid);
  return Bill(
    id: bill.id,
    owner: bill.owner,
    kind: bill.kind,
    payee: bill.payee,
    amount: bill.amount,
    dueDate: bill.dueDate,
    status: bill.status,
    source: bill.source,
    plan: bill.plan,
    paidBy: by,
  );
}
