import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/bills/domain/bills_repository.dart';
import 'package:cashdeck/features/bills/domain/payment_ladder.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';

/// The bills of [EntityScope], open ones first, each group by due date.
final class ListBills {
  const new(this._repository);

  final BillsRepository _repository;

  Future<Result<List<Bill>>> call(EntityScope scope) async {
    final result = await _repository.list();
    return switch (result) {
      Ok(:final value) => Ok(
        value.where((bill) => scope.includes(bill.owner)).toList()
          ..sort(_byUrgency),
      ),
      Err(:final failure) => Err(failure),
    };
  }

  static int _byUrgency(Bill a, Bill b) {
    if (a.isSettled != b.isSettled) return a.isSettled ? 1 : -1;
    return a.dueDate.compareTo(b.dueDate);
  }
}

final class GetBill {
  const new(this._repository);

  final BillsRepository _repository;

  Future<Result<Bill>> call(String id) => _repository.get(id);
}

final class MarkBillPaid {
  const new(this._repository);

  final BillsRepository _repository;

  Future<Result<Bill>> call(String id) => _repository.markPaid(id);
}

final class ConfirmBillPayment {
  const new(this._repository);

  final BillsRepository _repository;

  Future<Result<Bill>> call(String id) => _repository.confirmPayment(id);
}

/// The open bills that wait on the user: overdue, waiting for a confirmation
/// or a bank approval, or ready on step 3. The Contas a pagar badge counts
/// these.
List<Bill> billsNeedingYou(List<Bill> bills, CalendarDate today) => [
  for (final bill in bills)
    if (!bill.isSettled &&
        (bill.isOverdue(today) ||
            bill.status == BillStatus.needsConfirmation ||
            bill.status == BillStatus.awaitingApproval ||
            currentStepOf(bill) == LadderStep.assisted))
      bill,
];

/// What is due from today through [days] ahead, plus anything overdue.
List<Bill> billsDueWithin(List<Bill> bills, CalendarDate today, int days) => [
  for (final bill in bills)
    if (!bill.isSettled && today.daysUntil(bill.dueDate) <= days) bill,
];
