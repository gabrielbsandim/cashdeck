import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/files/file_chooser.dart';
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
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_segmented.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_key_value_row.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/bills/presentation/bill_labels.dart';
import 'package:cashdeck/features/bills/presentation/bills_controller.dart';
import 'package:cashdeck/features/receipts/domain/receipt.dart';
import 'package:cashdeck/features/receipts/receipts_providers.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

final FutureProviderFamily<Receipt, String> receiptProvider = FutureProvider
    .autoDispose
    .family<Receipt, String>(
      (ref, billId) async =>
          (await ref.watch(receiptsRepositoryProvider).receipt(billId)).orThrow,
      retry: noRetry,
    );

enum _Tab { bank, attachments }

/// A bill's proof of payment: what the bank returned, and the user's files.
class ReceiptViewerScreen extends ConsumerStatefulWidget {
  const new({required this.billId, super.key});

  static const shareKey = Key('receipt-share');
  static const pdfKey = Key('receipt-pdf');
  static const attachKey = Key('receipt-attach');
  static const attachmentsTabKey = Key('receipt-tab-attachments');

  final String billId;

  @override
  ConsumerState<ReceiptViewerScreen> createState() =>
      _ReceiptViewerScreenState();
}

class _ReceiptViewerScreenState extends ConsumerState<ReceiptViewerScreen> {
  _Tab? _tab;

  static const attachable = ['pdf', 'jpg', 'jpeg', 'png'];

  Future<void> _shareText(Bill bill, BankProof? proof) async {
    final l10n = AppLocalizations.of(context);
    final text = proof == null
        ? l10n.receiptShareLine(
            billPayeeOf(l10n, bill),
            MoneyFormat.format(bill.amount),
          )
        : l10n.receiptShareProof(
            proof.receiver,
            MoneyFormat.format(proof.amount),
            proof.transactionId ?? '-',
          );
    await ref.read(fileSharerProvider).shareText(text);
  }

  Future<void> _sharePdf() async {
    final result = await ref
        .read(receiptsRepositoryProvider)
        .document(widget.billId);
    switch (result) {
      case Ok(:final value):
        await ref.read(fileSharerProvider).shareFile(value);
      case Err(:final failure):
        if (!mounted) return;
        await showOutcomeToast(context, failure, success: '');
    }
  }

  Future<void> _attach() async {
    final l10n = AppLocalizations.of(context);
    final file = await ref.read(fileChooserProvider).choose(attachable);
    if (file == null) return;
    final result = await ref
        .read(receiptsRepositoryProvider)
        .attach(widget.billId, file);
    if (!mounted) return;
    ref.invalidate(receiptProvider(widget.billId));
    await showOutcomeToast(context, switch (result) {
      Ok() => null,
      Err(:final failure) => failure,
    }, success: l10n.attachedToast(file.name));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bill = ref.watch(billDetailControllerProvider(widget.billId));
    final receipt = ref.watch(receiptProvider(widget.billId));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const Icon(Symbols.close_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(l10n.receiptTitle),
        actions: [
          IconButton(
            tooltip: l10n.shareButton,
            icon: const Icon(Symbols.share_rounded),
            onPressed: switch ((bill, receipt)) {
              (AsyncData(value: final b), AsyncData(value: final r)) =>
                () => _shareText(b, r.proof),
              _ => null,
            },
          ),
        ],
      ),
      body: switch ((bill, receipt)) {
        (AsyncData(value: final b), AsyncData(value: final r)) => _body(
          context,
          b,
          r,
        ),
        (AsyncError(:final error), _) ||
        (_, AsyncError(:final error)) => CdErrorState(
          failure: failureOf(error),
          onRetry: () {
            ref
              ..invalidate(billDetailControllerProvider(widget.billId))
              ..invalidate(receiptProvider(widget.billId));
          },
        ),
        _ => const CdSkeleton(rows: 3),
      },
    );
  }

  Widget _body(BuildContext context, Bill bill, Receipt receipt) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final today = CalendarDate.brazilToday(ref.watch(clockProvider).now());
    final proof = receipt.proof;
    final tab = _tab ?? (proof == null ? _Tab.attachments : _Tab.bank);
    final (label, tone) = bill.status == BillStatus.paid
        ? (
            bill.paidBy == PaidBy.user
                ? l10n.receiptPaidByYou
                : l10n.receiptPaidAutomatic,
            MoneyTone.paid,
          )
        : billStatusOf(l10n, bill, today);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: CdStatusBadge(tone: tone, label: label),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          billPayeeOf(AppLocalizations.of(context), bill),
          style: AppTextStyles.titleLg.copyWith(color: palette.onSurface),
        ),
        CdAmount(
          bill.amount,
          size: CdAmountSize.lg,
          textAlign: TextAlign.start,
        ),
        const SizedBox(height: AppSpacing.lg),
        CdSegmented<_Tab>(
          segments: [
            CdSegment(_Tab.bank, l10n.receiptFromBank),
            CdSegment(
              _Tab.attachments,
              l10n.receiptAttachments(receipt.attachments.length),
              key: ReceiptViewerScreen.attachmentsTabKey,
            ),
          ],
          selected: tab,
          onChanged: (next) => setState(() => _tab = next),
        ),
        const SizedBox(height: AppSpacing.md),
        if (tab == _Tab.bank && proof != null) _ProofCard(proof: proof),
        if (tab == _Tab.bank && proof == null)
          CdEmptyState(
            icon: Symbols.hourglass_empty_rounded,
            title: l10n.receiptNoProofTitle,
            message: l10n.receiptNoProofBody,
          ),
        if (tab == _Tab.attachments && receipt.attachments.isEmpty)
          CdEmptyState(
            icon: Symbols.attach_file_rounded,
            title: l10n.receiptNoAttachments,
            message: l10n.receiptNoAttachmentsBody,
          ),
        for (final attachment in receipt.attachments)
          if (tab == _Tab.attachments)
            ListTile(
              leading: const Icon(Symbols.description_rounded),
              title: Text(attachment.fileName),
            ),
        if (proof != null) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Symbols.dns_rounded,
                size: 16,
                color: palette.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.receiptStoredNote(proof.rail),
                  style: AppTextStyles.bodyMd.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: CdButton.filled(
                  key: ReceiptViewerScreen.shareKey,
                  expand: true,
                  icon: Symbols.share_rounded,
                  label: l10n.shareButton,
                  onPressed: () => _shareText(bill, proof),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: CdButton.outlined(
                  key: ReceiptViewerScreen.pdfKey,
                  expand: true,
                  icon: Symbols.download_rounded,
                  label: l10n.pdfButton,
                  onPressed: _sharePdf,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: CdButton.text(
            key: ReceiptViewerScreen.attachKey,
            icon: Symbols.attach_file_rounded,
            label: proof == null
                ? l10n.attachFileButton
                : l10n.attachAnotherButton,
            onPressed: _attach,
          ),
        ),
      ],
    );
  }
}

class _ProofCard extends ConsumerWidget {
  const new({required this.proof});

  final BankProof proof;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final hide = ref.watch(hideAmountsProvider);
    final paid = CalendarDate.brazilToday(proof.paidAt);
    final seconds = proof.paidAt.second.toString().padLeft(2, '0');
    Widget row(String label, String value, {bool mono = false}) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: CdKeyValueRow(
        label: label,
        stacked: true,
        monospace: mono,
        value: Text(value),
      ),
    );
    return CdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.receiptPixHeader,
            style: AppTextStyles.labelMd.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
          row(
            l10n.confirmRowAmount,
            MoneyFormat.format(proof.amount, hide: hide),
          ),
          row(
            l10n.receiptDateTime,
            '${paid.display} · ${brazilTime(proof.paidAt)}:$seconds',
          ),
          row(l10n.receiptPayer, proof.payer),
          row(l10n.receiptReceiver, proof.receiver),
          if (proof.transactionId case final id?)
            row(l10n.receiptTransactionId, id, mono: true),
          if (proof.authentication case final code?)
            row(l10n.receiptAuthentication, code, mono: true),
        ],
      ),
    );
  }
}
