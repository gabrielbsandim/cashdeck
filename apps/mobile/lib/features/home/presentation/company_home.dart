import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_icon_tile.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/features/bills/presentation/bills_controller.dart';
import 'package:cashdeck/features/home/domain/home_summary.dart';
import 'package:cashdeck/features/home/presentation/home_controller.dart';
import 'package:cashdeck/features/home/presentation/home_labels.dart';
import 'package:cashdeck/features/home/presentation/home_sections.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Início for the company: cash, what was billed, the DAS estimate, taxes
/// due, drafts to approve and money received without an invoice.
class CompanyHome extends ConsumerWidget {
  const new({required this.summary, super.key});

  static Key approveKey(String id) => Key('draft-approve-$id');
  static Key editKey(String id) => Key('draft-edit-$id');
  static Key issueKey(String id) => Key('receipt-issue-$id');

  final CompanySummary summary;

  Future<void> _run(
    BuildContext context,
    Future<AppFailure?> Function() action,
    String success,
  ) async {
    final l10n = AppLocalizations.of(context);
    final failure = await action();
    if (!context.mounted) return;
    await showCdToast(
      context,
      icon: failure == null ? Symbols.task_alt_rounded : Symbols.error_rounded,
      message: failure?.userMessage(l10n) ?? success,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final today = homeToday(ref);
    final bills = ref.watch(billsControllerProvider).value?.bills ?? const [];
    final taxes = [
      for (final bill in bills)
        if (bill.isTax && !bill.isSettled) bill,
    ];
    final controller = ref.read(homeControllerProvider.notifier);
    return HomeScroll(
      children: [
        const PausedBanner(),
        BalanceHeader(
          label: l10n.companyCash,
          balance: summary.cash,
          syncLine: syncLineOf(l10n, ref, summary.sync, company: true),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _StatTile(
                label: l10n.billedInMonth(monthName(context, today)),
                amount: summary.billed,
                caption: l10n.invoiceCount(summary.invoiceCount),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _StatTile(
                label: l10n.dasEstimated,
                amount: summary.dasEstimate,
                caption: l10n.dasDueOn(summary.dasDue.dayMonth),
              ),
            ),
          ],
        ),
        if (summary.inss case final inss?)
          _StatTile(
            label: l10n.inssEstimated,
            amount: inss.amount,
            caption: l10n.dasDueOn(inss.due.dayMonth),
          ),
        DueSoonSection(
          bills: taxes,
          today: today,
          title: l10n.taxesDue,
          actionLabel: l10n.calendarButton,
        ),
        if (summary.drafts.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CdSectionHeader(title: l10n.draftsToApprove),
              const SizedBox(height: AppSpacing.md),
              for (final draft in summary.drafts)
                _DraftCard(
                  draft: draft,
                  onApprove: () => _run(
                    context,
                    () => controller.approveDraft(draft.id),
                    l10n.invoiceIssuedToast(draft.customer),
                  ),
                  onEdit: () => showCdToast(
                    context,
                    icon: Symbols.edit_rounded,
                    message: l10n.draftEditSoon,
                  ),
                ),
            ],
          ),
        if (summary.unbilled.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CdSectionHeader(title: l10n.receivedWithoutInvoice),
              const SizedBox(height: AppSpacing.md),
              for (final receipt in summary.unbilled)
                _UnbilledCard(
                  receipt: receipt,
                  onIssue: () => _run(
                    context,
                    () => controller.issueInvoiceFor(receipt.id),
                    l10n.invoiceIssuedToast(receipt.payer),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const new({required this.label, required this.amount, required this.caption});

  final String label;
  final Money amount;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final secondary = AppTextStyles.bodyMd.copyWith(
      fontSize: 13,
      color: palette.onSurfaceVariant,
    );
    return CdCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: secondary),
          const SizedBox(height: AppSpacing.xxs),
          CdAmount(amount, size: CdAmountSize.sm, textAlign: TextAlign.start),
          Text(caption, style: secondary),
        ],
      ),
    );
  }
}

class _DraftCard extends StatelessWidget {
  const new({
    required this.draft,
    required this.onApprove,
    required this.onEdit,
  });

  final InvoiceDraft draft;
  final VoidCallback onApprove;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final date = draft.issueOn.dayMonth;
    return CdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.draftTitle(draft.customer),
                      style: AppTextStyles.titleSm.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                    Text(
                      draft.recurring
                          ? l10n.draftRecurring(date)
                          : l10n.draftSingle(date),
                      style: AppTextStyles.bodyMd.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              CdAmount(draft.amount, size: CdAmountSize.row),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              CdButton.filled(
                key: CompanyHome.approveKey(draft.id),
                dense: true,
                label: l10n.approveAndIssueButton,
                onPressed: onApprove,
              ),
              CdButton.text(
                key: CompanyHome.editKey(draft.id),
                dense: true,
                label: l10n.editButton,
                onPressed: onEdit,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UnbilledCard extends StatelessWidget {
  const new({required this.receipt, required this.onIssue});

  final UnbilledReceipt receipt;
  final VoidCallback onIssue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return CdCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          CdIconTile(
            Symbols.south_west_rounded,
            tone: context.tone(MoneyTone.income),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.pixFrom(receipt.payer),
                  style: AppTextStyles.titleSm.copyWith(
                    color: palette.onSurface,
                  ),
                ),
                CdPrivateText(
                  (hide) => l10n.receivedLine(
                    receipt.receivedOn.dayMonth,
                    MoneyFormat.format(
                      receipt.amount,
                      hide: hide,
                      sign: MoneySign.plus,
                    ),
                  ),
                  style: AppTextStyles.bodyMd.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          CdButton.tonal(
            key: CompanyHome.issueKey(receipt.id),
            dense: true,
            label: l10n.issueInvoiceButton,
            onPressed: onIssue,
          ),
        ],
      ),
    );
  }
}
