import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/bills/application/bills_use_cases.dart';
import 'package:cashdeck/features/bills/bills_providers.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

class BillsController extends AsyncNotifier<List<Bill>> {
  @override
  Future<List<Bill>> build() async {
    final scope = ref.watch(entityScopeProvider);
    final result = await ref.watch(listBillsProvider).call(scope);
    return switch (result) {
      Ok(:final value) => value,
      Err(:final failure) => throw LoadFailure(failure),
    };
  }
}

final AsyncNotifierProvider<BillsController, List<Bill>>
billsControllerProvider =
    AsyncNotifierProvider.autoDispose<BillsController, List<Bill>>(
      BillsController.new,
      retry: noRetry,
    );

/// How many bills of the current scope wait on the user, for the tab badge.
final Provider<int> billsNeedingYouCountProvider = Provider.autoDispose<int>((
  ref,
) {
  final bills = ref.watch(billsControllerProvider).value ?? const [];
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
  /// false; the API has no undo, so the request waits for the toast.
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

  Future<AppFailure?> confirm() async {
    final result = await ref.read(confirmBillPaymentProvider).call(billId);
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
