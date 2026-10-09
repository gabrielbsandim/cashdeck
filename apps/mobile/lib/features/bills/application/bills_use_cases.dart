import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/bills/domain/bills_repository.dart';
import 'package:cashdeck/features/bills/domain/payment_ladder.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';

/// A page of the bills of [EntityScope], open ones first, each group by due
/// date.
final class ListBills {
  const new(this._repository);

  final BillsRepository _repository;

  Future<Result<BillPage>> call(EntityScope scope, {String? cursor}) async {
    final owner = switch (scope) {
      EntityScope.personal => EntityKind.personal,
      EntityScope.company => EntityKind.company,
      EntityScope.consolidated => null,
    };
    final result = await _repository.list(owner: owner, cursor: cursor);
    return switch (result) {
      Ok(:final value) => Ok(
        BillPage(
          bills: sortByUrgency([
            for (final bill in value.bills)
              if (scope.includes(bill.owner)) bill,
          ]),
          nextCursor: value.nextCursor,
        ),
      ),
      Err(:final failure) => Err(failure),
    };
  }
}

/// [loaded] plus [more], once each, open ones first by due date.
List<Bill> mergeBills(List<Bill> loaded, List<Bill> more) {
  final ids = {for (final bill in loaded) bill.id};
  return sortByUrgency([
    ...loaded,
    for (final bill in more)
      if (!ids.contains(bill.id)) bill,
  ]);
}

List<Bill> sortByUrgency(List<Bill> bills) => bills..sort(byUrgency);

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

final class MarkBillUnpaid {
  const new(this._repository);

  final BillsRepository _repository;

  Future<Result<Bill>> call(String id) => _repository.markUnpaid(id);
}

/// Runs the payment ladder for one bill.
final class PayBill {
  const new(this._repository);

  final BillsRepository _repository;

  /// Sends the confirmation flag only when [confirmed] came from the sheet.
  Future<Result<Bill>> call(String id, {required bool confirmed}) =>
      _repository.pay(id, confirmed: confirmed);
}

final class SetAutoDebit {
  const new(this._repository);

  final BillsRepository _repository;

  Future<Result<Bill>> call(String id, {required bool enabled}) =>
      _repository.setAutoDebit(id, enabled: enabled);
}

/// The open bills that wait on the user: overdue, waiting for a confirmation
/// or a bank approval, or ready on step 3. The Contas a pagar badge counts
/// these.
List<Bill> billsNeedingYou(List<Bill> bills, CalendarDate today) => [
  for (final bill in bills)
    if (!bill.isSettled &&
        !bill.autoDebit &&
        (bill.isOverdue(today) ||
            bill.status == BillStatus.needsConfirmation ||
            bill.status == BillStatus.awaitingApproval ||
            currentStepOf(bill) == LadderStep.assisted))
      bill,
];

/// What is due from today through [days] ahead, plus anything overdue that
/// is not already left to the bank's auto debit.
List<Bill> billsDueWithin(List<Bill> bills, CalendarDate today, int days) => [
  for (final bill in bills)
    if (!bill.isSettled &&
        !bill.awaitsBankDebit(today) &&
        today.daysUntil(bill.dueDate) <= days)
      bill,
];
