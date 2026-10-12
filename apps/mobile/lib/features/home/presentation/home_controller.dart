import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/home/domain/home_summary.dart';
import 'package:cashdeck/features/home/domain/invoice_draft_edit.dart';
import 'package:cashdeck/features/home/home_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

class HomeController extends AsyncNotifier<HomeSummary> {
  @override
  Future<HomeSummary> build() async {
    final scope = ref.watch(entityScopeProvider);
    final result = await ref.watch(loadHomeProvider).call(scope);
    return switch (result) {
      Ok(:final value) => value,
      Err(:final failure) => throw LoadFailure(failure),
    };
  }

  Future<AppFailure?> approveDraft(String id) async =>
      _apply(await ref.read(approveInvoiceDraftProvider).call(id));

  Future<AppFailure?> issueInvoiceFor(String receiptId) async =>
      _apply(await ref.read(issueInvoiceForReceiptProvider).call(receiptId));

  Future<AppFailure?> updateDraft(String id, InvoiceDraftEdit edit) async =>
      _apply(await ref.read(updateInvoiceDraftProvider).call(id, edit));

  AppFailure? _apply(Result<CompanySummary> result) {
    switch (result) {
      case Ok(:final value):
        state = AsyncData(value);
        return null;
      case Err(:final failure):
        return failure;
    }
  }
}

/// The draft the editor opens, read fresh each time it opens.
final FutureProviderFamily<InvoiceDraftDetail, String> invoiceDraftProvider =
    FutureProvider.autoDispose.family<InvoiceDraftDetail, String>(
      (ref, id) async =>
          (await ref.watch(loadInvoiceDraftProvider).call(id)).orThrow,
      retry: noRetry,
    );

final AsyncNotifierProvider<HomeController, HomeSummary>
homeControllerProvider =
    AsyncNotifierProvider.autoDispose<HomeController, HomeSummary>(
      HomeController.new,
      retry: noRetry,
    );
