import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/loans/domain/loan.dart';
import 'package:cashdeck/features/loans/loans_providers.dart';
import 'package:cashdeck/features/outlook/presentation/outlook_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The person's loans; importing or deleting one also changes what the
/// month still owes, so the free-to-spend number reloads.
class LoansController extends AsyncNotifier<List<Loan>> {
  @override
  Future<List<Loan>> build() async =>
      (await ref.watch(listLoansProvider).call()).orThrow;

  Future<AppFailure?> _after(Result<Object?> result) async {
    if (result case Err(:final failure)) return failure;
    ref
      ..invalidateSelf()
      ..invalidate(safeToSpendProvider);
    return null;
  }

  Future<AppFailure?> importStatement(LocalFile file) async =>
      await _after(await ref.read(importLoanStatementProvider).call(file));

  Future<AppFailure?> delete(String id) async =>
      await _after(await ref.read(deleteLoanProvider).call(id));
}

final AsyncNotifierProvider<LoansController, List<Loan>>
loansControllerProvider =
    AsyncNotifierProvider.autoDispose<LoansController, List<Loan>>(
      LoansController.new,
      retry: noRetry,
    );
