import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/bills/application/bills_use_cases.dart';
import 'package:cashdeck/features/bills/bills_providers.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

/// The bills loaded so far and where the next page starts.
final class BillsListing extends Equatable {
  const new({
    required this.bills,
    this.nextCursor,
    this.loadingMore = false,
    this.moreFailure,
  });

  final List<Bill> bills;
  final String? nextCursor;
  final bool loadingMore;

  /// The last load-more failed; the loaded bills stay and it can be retried.
  final AppFailure? moreFailure;

  bool get hasMore => nextCursor != null;

  @override
  List<Object?> get props => [bills, nextCursor, loadingMore, moreFailure];
}

class BillsController extends AsyncNotifier<BillsListing> {
  @override
  Future<BillsListing> build() async {
    final scope = ref.watch(entityScopeProvider);
    final result = await ref.watch(listBillsProvider).call(scope);
    return switch (result) {
      Ok(:final value) => BillsListing(
        bills: value.bills,
        nextCursor: value.nextCursor,
      ),
      Err(:final failure) => throw LoadFailure(failure),
    };
  }

  /// Appends the next page; a second call while one runs is ignored.
  Future<void> loadMore() async {
    final current = state.value;
    final cursor = current?.nextCursor;
    if (current == null || cursor == null || current.loadingMore) return;
    state = AsyncData(
      BillsListing(bills: current.bills, nextCursor: cursor, loadingMore: true),
    );
    final result = await ref
        .read(listBillsProvider)
        .call(ref.read(entityScopeProvider), cursor: cursor);
    if (!ref.mounted) return;
    state = AsyncData(switch (result) {
      Ok(:final value) => BillsListing(
        bills: mergeBills(current.bills, value.bills),
        nextCursor: value.nextCursor,
      ),
      Err(:final failure) => BillsListing(
        bills: current.bills,
        nextCursor: cursor,
        moreFailure: failure,
      ),
    });
  }
}

final AsyncNotifierProvider<BillsController, BillsListing>
billsControllerProvider =
    AsyncNotifierProvider.autoDispose<BillsController, BillsListing>(
      BillsController.new,
      retry: noRetry,
    );

/// How many bills of the current scope wait on the user, for the tab badge.
final Provider<int> billsNeedingYouCountProvider = Provider.autoDispose<int>((
  ref,
) {
  final bills = ref.watch(billsControllerProvider).value?.bills ?? const [];
  final today = CalendarDate.brazilToday(ref.watch(clockProvider).now());
  return billsNeedingYou(bills, today).length;
});

class BillDetailController extends AsyncNotifier<Bill> {
  new(this.billId);

  final String billId;

  @override
  Future<Bill> build() async {
    final result = await ref.watch(getBillProvider).call(billId);
    return switch (result) {
      Ok(:final value) => value,
      Err(:final failure) => throw LoadFailure(failure),
    };
  }

  /// Shows the bill as paid right away and sends it once [undone] resolves
  /// false; the request waits for the toast, so an undo there sends nothing.
  Future<AppFailure?> markPaid({required Future<bool> undone}) async {
    final bill = state.value;
    if (bill == null) return null;
    final link = ref.keepAlive();
    state = AsyncData(bill.markedPaid(ref.read(clockProvider).now()));
    try {
      if (await undone) {
        state = AsyncData(bill);
        return null;
      }
      final result = await ref.read(markBillPaidProvider).call(billId);
      ref.invalidate(billsControllerProvider);
      final failure = _apply(result);
      if (failure != null) state = AsyncData(bill);
      return failure;
    } finally {
      link.close();
    }
  }

  Future<AppFailure?> markUnpaid() async {
    final result = await ref.read(markBillUnpaidProvider).call(billId);
    ref.invalidate(billsControllerProvider);
    return _apply(result);
  }

  /// Runs the ladder; [confirmed] is the answer the user gave in the sheet.
  Future<AppFailure?> pay({required bool confirmed}) async {
    final result = await ref
        .read(payBillProvider)
        .call(billId, confirmed: confirmed);
    ref.invalidate(billsControllerProvider);
    return _apply(result);
  }

  Future<AppFailure?> setAutoDebit({required bool enabled}) async {
    final result = await ref
        .read(setAutoDebitProvider)
        .call(billId, enabled: enabled);
    ref.invalidate(billsControllerProvider);
    return _apply(result);
  }

  AppFailure? _apply(Result<Bill> result) {
    switch (result) {
      case Ok(:final value):
        state = AsyncData(value);
        return null;
      case Err(:final failure):
        return failure;
    }
  }
}

final AsyncNotifierProviderFamily<BillDetailController, Bill, String>
billDetailControllerProvider = AsyncNotifierProvider.autoDispose
    .family<BillDetailController, Bill, String>(
      BillDetailController.new,
      retry: noRetry,
    );
