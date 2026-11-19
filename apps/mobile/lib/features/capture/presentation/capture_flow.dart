import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/features/bills/presentation/bill_detail_screen.dart';
import 'package:cashdeck/features/capture/capture_providers.dart';
import 'package:cashdeck/features/capture/domain/bill_draft.dart';
import 'package:cashdeck/features/capture/presentation/capture_details_sheet.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Sends [draft]; when the server asks for the amount or the due date, the
/// user fills them in a sheet and it goes again. Null when the sheet closes.
/// [onSending] is true only while a request is out, not while the sheet waits.
Future<Result<CaptureOutcome>?> captureAsking(
  BuildContext context,
  WidgetRef ref,
  BillDraft draft, {
  ValueChanged<bool>? onSending,
}) async {
  onSending?.call(true);
  final result = await ref.read(captureRepositoryProvider).capture(draft);
  if (!context.mounted) return null;
  onSending?.call(false);
  final askAmount = switch (result) {
    Ok(value: CaptureDetailsNeeded(:final amount)) => amount,
    _ => null,
  };
  if (askAmount == null) return result;
  final details = await showCaptureDetailsSheet(
    context,
    askAmount: askAmount,
    today: CalendarDate.brazilToday(ref.read(clockProvider).now()),
  );
  if (details == null || !context.mounted) return null;
  return await captureAsking(
    context,
    ref,
    draft.copyWith(amount: details.amount, dueDate: details.dueDate),
    onSending: onSending,
  );
}

/// The entity a new bill goes to by default: the company only when the
/// switcher is on it.
EntityKind defaultOwner(WidgetRef ref) =>
    switch (ref.read(entityScopeProvider)) {
      EntityScope.company => EntityKind.company,
      EntityScope.personal || EntityScope.consolidated => EntityKind.personal,
    };

/// Opens the captured bill with its confirm sheet up, so a code read to pay
/// is one confirmation away; a duplicate opens the bill the server returned.
Future<void> openToPay(
  BuildContext context,
  Result<CaptureOutcome> result,
) async {
  switch (result) {
    case Ok(value: BillCaptured(:final billId)):
      context.go(
        AppRoutes.bill(billId),
        extra: BillDetailScreen.confirmOnOpenExtra,
      );
    case Ok():
      return;
    case Err(:final failure):
      await showOutcomeToast(context, failure, success: '');
  }
}
