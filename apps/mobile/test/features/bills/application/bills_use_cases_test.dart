import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/bills/application/bills_use_cases.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/bills/domain/bills_repository.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/builders.dart';
import '../../../support/mocks.dart';

void main() {
  late MockBillsRepository repository;

  final paid = testBill(id: 'paid', status: BillStatus.paid);
  final later = testBill(id: 'later', dueDate: testToday.addDays(5));
  final sooner = testBill(id: 'sooner', dueDate: testToday.addDays(1));
  final company = testBill(id: 'company', owner: EntityKind.company);

  setUpAll(() => registerFallbackValue(EntityKind.personal));

  setUp(() {
    repository = MockBillsRepository();
    when(
      () => repository.list(
        owner: any(named: 'owner'),
        cursor: any(named: 'cursor'),
      ),
    ).thenAnswer(
      (_) async => Ok(
        BillPage(bills: [paid, later, company, sooner], nextCursor: 'next'),
      ),
    );
  });

  test('lists the scope, open bills first by due date', () async {
    final result = await ListBills(repository).call(EntityScope.personal);

    expect(
      result,
      Ok(BillPage(bills: [sooner, later, paid], nextCursor: 'next')),
    );
    verify(
      () => repository.list(
        owner: EntityKind.personal,
        cursor: any(named: 'cursor'),
      ),
    ).called(1);
  });

  test('the consolidated scope keeps both entities and pages on', () async {
    final result = await ListBills(repository)
        .call(EntityScope.consolidated, cursor: 'next');

    expect((result as Ok<BillPage>).value.bills, hasLength(4));
    final owners = verify(
      () => repository.list(
        owner: captureAny(named: 'owner'),
        cursor: 'next',
      ),
    ).captured;
    expect(owners, [null]);
  });

  test('passes a failure through', () async {
    when(
      () => repository.list(
        owner: EntityKind.company,
        cursor: any(named: 'cursor'),
      ),
    ).thenAnswer((_) async => const Err(NetworkFailure()));

    final result = await ListBills(repository).call(EntityScope.company);

    expect(result, const Err<BillPage>(NetworkFailure()));
  });

  test('a next page merges in once, still open first', () {
    final again = testBill(id: 'later', dueDate: testToday.addDays(5));

    expect(mergeBills([later, paid], [sooner, again]), [sooner, later, paid]);
  });

  test('gets, marks paid and pays one bill', () async {
    when(() => repository.get('later')).thenAnswer((_) async => Ok(later));
    when(() => repository.markPaid('later'))
        .thenAnswer((_) async => Ok(later.markedPaid(testNow)));
    when(() => repository.pay('later', confirmed: true))
        .thenAnswer((_) async => Ok(later));

    expect(await GetBill(repository).call('later'), Ok(later));
    expect(
      await MarkBillPaid(repository).call('later'),
      Ok(later.markedPaid(testNow)),
    );
    expect(await PayBill(repository).call('later', confirmed: true), Ok(later));
  });

  test('the bills needing the user are the ones it has to act on', () {
    final overdue = testBill(id: 'overdue', dueDate: testToday.addDays(-1));
    final confirm = testBill(
      id: 'confirm',
      status: BillStatus.needsConfirmation,
    );
    final approval = testBill(
      id: 'approval',
      status: BillStatus.awaitingApproval,
    );
    final assisted = testBill(
      id: 'assisted',
      plan: const [LadderStep.automatic, LadderStep.assisted],
      attempts: [testAttempt(LadderStep.automatic, AttemptOutcome.failed)],
    );
    final settledLate = testBill(
      id: 'settled',
      status: BillStatus.paid,
      dueDate: testToday.addDays(-3),
    );

    expect(
      billsNeedingYou([
        overdue,
        confirm,
        approval,
        assisted,
        later,
        settledLate,
      ], testToday),
      [overdue, confirm, approval, assisted],
    );
  });

  test('the bills due within a window include the overdue ones', () {
    final overdue = testBill(id: 'overdue', dueDate: testToday.addDays(-1));

    expect(billsDueWithin([overdue, sooner, later, paid], testToday, 3), [
      overdue,
      sooner,
    ]);
  });

  test('a past due bill on auto debit waits for the bank, not the user', () {
    final debiting = testBill(
      id: 'debiting',
      dueDate: testToday.addDays(-1),
      autoDebit: true,
    );
    final dueToday = testBill(id: 'due-today', autoDebit: true);

    expect(debiting.awaitsBankDebit(testToday), isTrue);
    expect(dueToday.awaitsBankDebit(testToday), isFalse);
    expect(billsDueWithin([debiting, dueToday], testToday, 7), [dueToday]);
  });
}
