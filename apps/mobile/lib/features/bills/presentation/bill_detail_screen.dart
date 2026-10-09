import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/share/file_sharer.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/layout/cd_icon_tile.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/money/cd_bill_card.dart';
import 'package:cashdeck/core/widgets/money/cd_confirm_sheet.dart';
import 'package:cashdeck/core/widgets/money/cd_copy_field.dart';
import 'package:cashdeck/core/widgets/money/privacy_toggle.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/bills/domain/payment_ladder.dart';
import 'package:cashdeck/features/bills/presentation/bill_labels.dart';
import 'package:cashdeck/features/bills/presentation/bills_controller.dart';
import 'package:cashdeck/features/bills/presentation/payment_ladder_view.dart';
import 'package:cashdeck/features/receipts/receipts_providers.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class BillDetailScreen extends ConsumerWidget {
  const new({required this.billId, super.key});

  static const copyCodeKey = Key('bill-copy-code');
  static const copyPixKey = Key('bill-copy-pix');
  static const viewReceiptKey = Key('bill-view-receipt');
  static const shareReceiptKey = Key('bill-share-receipt');
  static const autoDebitKey = Key('bill-auto-debit');

  final String billId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final bill = ref.watch(billDetailControllerProvider(billId));
    final today = CalendarDate.brazilToday(ref.watch(clockProvider).now());
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.billDetailTitle),
        actions: const [PrivacyToggle()],
      ),
      body: switch (bill) {
        AsyncData(:final value) => _BillDetail(bill: value, today: today),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(billDetailControllerProvider(billId)),
        ),
        _ => const CdSkeleton(rows: 3),
      },
    );
  }
}

class _BillDetail extends ConsumerWidget {
  const new({required this.bill, required this.today});

  final Bill bill;
  final CalendarDate today;

  Future<void> _markPaid(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(billDetailControllerProvider(bill.id).notifier);
    final undone = showCdToast(
      context,
      icon: Symbols.task_alt_rounded,
      message: l10n.billMarkedPaidToast(billPayeeOf(l10n, bill)),
      actionLabel: l10n.undoButton,
    ).then((reason) => reason == SnackBarClosedReason.action);
    final failure = await notifier.markPaid(undone: undone);
    if (failure == null || !context.mounted) return;
    await showCdToast(
      context,
      icon: Symbols.error_rounded,
      message: failure.userMessage(l10n),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final hide = ref.read(hideAmountsProvider);
    final notifier = ref.read(billDetailControllerProvider(bill.id).notifier);
    final confirmed = await showCdConfirmSheet(
      context,
      title: l10n.confirmBillTitle(billPayeeOf(l10n, bill)),
      reason: confirmationReasonLabel(l10n, bill.confirmationReason),
      rows: [
        CdConfirmRow(
          l10n.confirmRowAmount,
          MoneyFormat.format(bill.amount, hide: hide),
        ),
        CdConfirmRow(l10n.confirmRowDue, bill.dueDate.dayMonth),
      ],
      confirmLabel: l10n.confirmAndPayButton,
    );
    if (confirmed == null || !confirmed || !context.mounted) return;
    final failure = await notifier.pay(confirmed: confirmed);
    if (!context.mounted) return;
    await showCdToast(
      context,
      icon: failure == null
          ? Symbols.check_circle_rounded
          : Symbols.error_rounded,
      message: failure?.userMessage(l10n) ?? l10n.billConfirmedToast,
    );
  }

  Future<void> _setAutoDebit(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    final failure = await ref
        .read(billDetailControllerProvider(bill.id).notifier)
        .setAutoDebit(enabled: enabled);
    if (failure == null || !context.mounted) return;
    await showOutcomeToast(context, failure, success: '');
  }

  /// The server renders the receipt PDF from the rail proof, or from the
  /// bill when it was marked paid by hand.
  Future<void> _shareReceipt(BuildContext context, WidgetRef ref) async {
    final result = await ref.read(receiptsRepositoryProvider).document(bill.id);
    switch (result) {
      case Ok(:final value):
        await ref.read(fileSharerProvider).shareFile(value);
      case Err(:final failure):
        if (!context.mounted) return;
        await showOutcomeToast(context, failure, success: '');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final (label, tone) = billStatusOf(l10n, bill, today);
    final code = bill.paymentCode;
    final pix = bill.pixCode;
    final showsCode =
        code != null &&
        !bill.isSettled &&
        !bill.autoDebit &&
        currentStepOf(bill) != LadderStep.assisted;
    final secondary = AppTextStyles.bodyMd.copyWith(
      color: palette.onSurfaceVariant,
    );
    final badge = CdStatusBadge(tone: tone, label: label);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sm,
        AppSpacing.screenGutter,
        AppSpacing.xxl,
      ),
      children: [
        Row(
          children: [
            CdIconTile(billIconOf(bill), circle: false, size: 48),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                billPayeeOf(l10n, bill),
                style: AppTextStyles.titleLg.copyWith(color: palette.onSurface),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        CdAmount(bill.amount, size: CdAmountSize.lg),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (bill.status == BillStatus.paid) CdPaidPop(child: badge),
            if (bill.status != BillStatus.paid) badge,
            Text(billDueLabel(l10n, bill, today), style: secondary),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.billKindAndSource(
            billKindLabelOf(l10n, bill),
            billSourceLabel(l10n, bill.source),
          ),
          style: secondary,
        ),
        if (!bill.isSettled) ...[
          const SizedBox(height: AppSpacing.md),
          CdListRow(
            key: BillDetailScreen.autoDebitKey,
            icon: Symbols.autorenew_rounded,
            title: l10n.billAutoDebit,
            subtitle: l10n.billAutoDebitExplain,
            padding: EdgeInsets.zero,
            trailing: Switch(
              value: bill.autoDebit,
              onChanged: (enabled) => _setAutoDebit(context, ref, enabled),
            ),
          ),
        ],
        if (showsCode && pix != null) ...[
          const SizedBox(height: AppSpacing.xl),
          CdCopyField(
            code: pix,
            label: l10n.pixCopyPasteLabel,
            valid: true,
            buttonKey: BillDetailScreen.copyPixKey,
          ),
        ],
        if (showsCode) ...[
          SizedBox(height: pix == null ? AppSpacing.xl : AppSpacing.md),
          CdCopyField(
            code: code,
            label: bill.kind == BillKind.pixQr
                ? l10n.pixCopyPasteLabel
                : l10n.paymentCodeLabel,
            valid: true,
            buttonKey: BillDetailScreen.copyCodeKey,
          ),
        ],
        if (bill.status == BillStatus.paid) ...[
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: CdButton.tonal(
                  key: BillDetailScreen.viewReceiptKey,
                  expand: true,
                  icon: Symbols.receipt_long_rounded,
                  label: l10n.billReceiptView,
                  onPressed: () =>
                      context.push(AppRoutes.billReceipt(bill.id)).ignore(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: CdButton.outlined(
                  key: BillDetailScreen.shareReceiptKey,
                  expand: true,
                  icon: Symbols.share_rounded,
                  label: l10n.billReceiptShare,
                  onPressed: () => _shareReceipt(context, ref),
                ),
              ),
            ],
          ),
        ],
        if (!bill.debitsItself) ...[
          const SizedBox(height: AppSpacing.xl),
          PaymentLadderView(
            bill: bill,
            today: today,
            actions: LadderActions(
              onMarkPaid: () => _markPaid(context, ref),
              onReceipt: () => context.push(AppRoutes.billReceipt(bill.id)),
              onOpenBank: () => showCdToast(
                context,
                icon: Symbols.open_in_new_rounded,
                message: l10n.openBankToast,
              ),
              onApproved: () => showCdToast(
                context,
                icon: Symbols.sync_rounded,
                message: l10n.approvalCheckToast,
              ),
              onConfirm: () => _confirm(context, ref),
            ),
          ),
        ],
      ],
    );
  }
}
