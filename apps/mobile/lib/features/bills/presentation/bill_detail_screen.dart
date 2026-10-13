import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/links/link_opener.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/share/file_sharer.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_haptics.dart';
import 'package:cashdeck/core/widgets/feedback/cd_inline_banner.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
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
  static const menuKey = Key('bill-menu');
  static const markPaidKey = Key('bill-menu-mark-paid');
  static const markUnpaidKey = Key('bill-menu-mark-unpaid');
  static const rescheduleKey = Key('bill-menu-reschedule');
  static const confirmKey = Key('bill-menu-confirm');
  static const cancelKey = Key('bill-menu-cancel');
  static const unverifiedBadgeKey = Key('bill-unverified-sender-badge');
  static const unverifiedBannerKey = Key('bill-unverified-sender-banner');

  final String billId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final bill = ref.watch(billDetailControllerProvider(billId));
    final today = CalendarDate.brazilToday(ref.watch(clockProvider).now());
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.billDetailTitle),
        actions: [
          if (bill case AsyncData(:final value)) _BillMenu(bill: value),
          const PrivacyToggle(),
        ],
      ),
      body: switch (bill) {
        AsyncValue(:final value?) => _BillDetail(bill: value, today: today),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(billDetailControllerProvider(billId)),
        ),
        _ => const CdSkeleton(rows: 3),
      },
    );
  }
}

Future<void> _markPaid(BuildContext context, WidgetRef ref, Bill bill) async {
  final l10n = AppLocalizations.of(context);
  final notifier = ref.read(billDetailControllerProvider(bill.id).notifier);
  CdHaptics.confirm();
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

enum _BillAction { markPaid, markUnpaid, reschedule }

/// Paid outside the app or that hand payment undone, both asked first, or a
/// due date read wrong.
class _BillMenu extends ConsumerWidget {
  const new({required this.bill});

  final Bill bill;

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    _BillAction action,
  ) async {
    if (action == _BillAction.reschedule) {
      await _reschedule(context, ref);
      return;
    }
    final l10n = AppLocalizations.of(context);
    final payee = billPayeeOf(l10n, bill);
    final (title, body, label) = action == _BillAction.markPaid
        ? (
            l10n.billMarkPaidConfirmTitle,
            l10n.billMarkPaidConfirmBody(payee),
            l10n.billMarkPaidAction,
          )
        : (
            l10n.billMarkUnpaidConfirmTitle,
            l10n.billMarkUnpaidConfirmBody(payee),
            l10n.billMarkUnpaidAction,
          );
    final confirmed = await showCdBottomSheet<bool>(
      context,
      title: title,
      builder: (sheet) => _ConfirmBody(body: body, confirmLabel: label),
    );
    if (confirmed != true || !context.mounted) return;
    if (action == _BillAction.markPaid) {
      await _markPaid(context, ref, bill);
      return;
    }
    final failure = await ref
        .read(billDetailControllerProvider(bill.id).notifier)
        .markUnpaid();
    if (!context.mounted) return;
    await showOutcomeToast(
      context,
      failure,
      success: l10n.billMarkedUnpaidToast(payee),
    );
  }

  Future<void> _reschedule(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    DateTime local(CalendarDate day) => DateTime(day.year, day.month, day.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: local(bill.dueDate),
      firstDate: local(bill.dueDate.addDays(-365)),
      lastDate: local(bill.dueDate.addDays(365)),
    );
    if (picked == null || !context.mounted) return;
    final failure = await ref
        .read(billDetailControllerProvider(bill.id).notifier)
        .reschedule(CalendarDate.fromDateTime(picked));
    if (!context.mounted) return;
    await showOutcomeToast(
      context,
      failure,
      success: l10n.billRescheduledToast(billPayeeOf(l10n, bill)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final acts = bill.canMarkPaid || bill.canMarkUnpaid || bill.canReschedule;
    if (!acts) return const SizedBox();
    return PopupMenuButton<_BillAction>(
      key: BillDetailScreen.menuKey,
      icon: const Icon(Symbols.more_vert_rounded),
      tooltip: l10n.billMenuTooltip,
      onSelected: (action) => _run(context, ref, action),
      itemBuilder: (_) => [
        if (bill.canReschedule)
          PopupMenuItem(
            key: BillDetailScreen.rescheduleKey,
            value: _BillAction.reschedule,
            child: Text(l10n.billRescheduleAction),
          ),
        if (bill.canMarkPaid)
          PopupMenuItem(
            key: BillDetailScreen.markPaidKey,
            value: _BillAction.markPaid,
            child: Text(l10n.billMarkPaidAction),
          ),
        if (bill.canMarkUnpaid)
          PopupMenuItem(
            key: BillDetailScreen.markUnpaidKey,
            value: _BillAction.markUnpaid,
            child: Text(l10n.billMarkUnpaidAction),
          ),
      ],
    );
  }
}

class _ConfirmBody extends StatelessWidget {
  const new({required this.body, required this.confirmLabel});

  final String body;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          body,
          style: AppTextStyles.bodyMd.copyWith(
            color: context.palette.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        CdButton.filled(
          key: BillDetailScreen.confirmKey,
          expand: true,
          label: confirmLabel,
          onPressed: () => navigator.pop(true),
        ),
        const SizedBox(height: AppSpacing.sm),
        CdButton.text(
          key: BillDetailScreen.cancelKey,
          expand: true,
          label: l10n.cancelButton,
          onPressed: () => navigator.pop(false),
        ),
      ],
    );
  }
}

class _BillDetail extends ConsumerWidget {
  const new({required this.bill, required this.today});

  final Bill bill;
  final CalendarDate today;

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final hide = ref.read(hideAmountsProvider);
    final notifier = ref.read(billDetailControllerProvider(bill.id).notifier);
    final reason = bill.confirmationReason;
    final confirmed = await showCdConfirmSheet(
      context,
      title: l10n.confirmBillTitle(billPayeeOf(l10n, bill)),
      reason: confirmationReasonLabel(l10n, reason),
      reasonTone: confirmationReasonTone(reason),
      reasonIcon: confirmationReasonIcon(reason),
      warning: warnsAboutSender(bill) ? l10n.billUnverifiedSenderBody : null,
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
    CdHaptics.outcome(failure);
    await showCdToast(
      context,
      icon: failure == null
          ? Symbols.check_circle_rounded
          : Symbols.error_rounded,
      message: failure?.userMessage(l10n) ?? l10n.billConfirmedToast,
    );
  }

  /// The bank app the server linked to the approval; the hint toast when it
  /// sent none or the phone cannot open it.
  Future<void> _openBank(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final link = bill.attempts
        .where((attempt) => attempt.step == LadderStep.bankApproval)
        .lastOrNull
        ?.appLink;
    final uri = link == null ? null : Uri.tryParse(link);
    final opened = uri != null && await ref.read(linkOpenerProvider).open(uri);
    if (opened || !context.mounted) return;
    await showCdToast(
      context,
      icon: Symbols.open_in_new_rounded,
      message: l10n.openBankToast,
    );
  }

  /// Has the server ask the bank about the approval now, then says whether
  /// it was paid, still waits or moved on.
  Future<void> _checkApproval(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    CdHaptics.confirm();
    final result = await ref
        .read(billDetailControllerProvider(bill.id).notifier)
        .reconcile();
    if (!context.mounted) return;
    await showOutcomeToast(
      context,
      switch (result) {
        Err(:final failure) => failure,
        Ok() => null,
      },
      success: switch (result) {
        Ok(:final value) when value.isSettled => l10n.approvalPaidToast,
        Ok(:final value) when currentStepOf(value) == LadderStep.bankApproval =>
          l10n.approvalPendingToast,
        Ok() => l10n.approvalUpdatedToast,
        Err() => '',
      },
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
            if (warnsAboutSender(bill))
              CdStatusBadge(
                key: BillDetailScreen.unverifiedBadgeKey,
                tone: MoneyTone.overdue,
                label: l10n.billUnverifiedSenderBadge,
                icon: Symbols.gpp_maybe_rounded,
              ),
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
        if (warnsAboutSender(bill)) ...[
          const SizedBox(height: AppSpacing.md),
          CdInlineBanner(
            key: BillDetailScreen.unverifiedBannerKey,
            icon: Symbols.gpp_maybe_rounded,
            tone: MoneyTone.overdue,
            title: l10n.billUnverifiedSenderTitle,
            message: l10n.billUnverifiedSenderBody,
          ),
        ],
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
              onMarkPaid: () => _markPaid(context, ref, bill),
              onReceipt: () => context.push(AppRoutes.billReceipt(bill.id)),
              onOpenBank: () => _openBank(context, ref),
              onApproved: () => _checkApproval(context, ref),
              onConfirm: () => _confirm(context, ref),
            ),
          ),
        ],
      ],
    );
  }
}
