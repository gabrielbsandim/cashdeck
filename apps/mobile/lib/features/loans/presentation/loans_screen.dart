import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/files/file_chooser.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_haptics.dart';
import 'package:cashdeck/core/widgets/feedback/cd_inline_banner.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_key_value_row.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_refresh.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/loans/domain/loan.dart';
import 'package:cashdeck/features/loans/presentation/loans_controller.dart';
import 'package:cashdeck/features/loans/presentation/prepayment_sheet.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Every loan read from a bank statement: what is still owed, the next
/// installment, the interest ahead and what an extra payment would save.
class LoansScreen extends ConsumerStatefulWidget {
  const new({super.key});

  static const importKey = Key('loans-import');

  static Key cardKey(String id) => Key('loan-$id');

  static Key prepayKey(String id) => Key('loan-prepay-$id');

  static Key menuKey(String id) => Key('loan-menu-$id');

  static const deleteKey = Key('loan-delete');
  static const confirmDeleteKey = Key('loan-confirm-delete');

  @override
  ConsumerState<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends ConsumerState<LoansScreen> {
  var _importing = false;

  Future<void> _import() async {
    final l10n = AppLocalizations.of(context);
    final file = await ref.read(fileChooserProvider).choose(const ['pdf']);
    if (file == null || !mounted) return;
    setState(() => _importing = true);
    final failure = await ref
        .read(loansControllerProvider.notifier)
        .importStatement(file);
    if (!mounted) return;
    setState(() => _importing = false);
    await showOutcomeToast(context, failure, success: l10n.loansImported);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loans = ref.watch(loansControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.loansTitle),
        actions: [
          IconButton(
            key: LoansScreen.importKey,
            tooltip: l10n.loansImport,
            icon: const Icon(Symbols.upload_file_rounded),
            onPressed: _importing ? null : _import,
          ),
        ],
      ),
      body: switch (loans) {
        _ when _importing => CdEmptyState(
          icon: Symbols.hourglass_top_rounded,
          title: l10n.loansReadingTitle,
          message: l10n.loansReadingMessage,
        ),
        AsyncValue(:final value?, hasError: false) when value.isEmpty =>
          CdEmptyState(
            icon: Symbols.home_work_rounded,
            title: l10n.loansEmptyTitle,
            message: l10n.loansEmptyMessage,
            actionLabel: l10n.loansImport,
            actionIcon: Symbols.upload_file_rounded,
            onAction: _import,
          ),
        AsyncValue(:final value?, hasError: false) => CdRefresh(
          providers: [loansControllerProvider],
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.sm,
              AppSpacing.screenGutter,
              AppSpacing.xxl,
            ),
            children: [
              for (final loan in value) ...[
                _LoanCard(key: LoansScreen.cardKey(loan.id), loan: loan),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          ),
        ),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(loansControllerProvider),
        ),
        _ => const CdSkeleton(parts: [CdSkeletonCards(height: 220)]),
      },
    );
  }
}

enum _LoanAction { delete }

class _LoanCard extends ConsumerWidget {
  const new({required this.loan, super.key});

  final Loan loan;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showCdBottomSheet<bool>(
      context,
      title: l10n.loanDeleteTitle(loan.name),
      builder: (_) => const _ConfirmDelete(),
    );
    if (confirmed != true || !context.mounted) return;
    CdHaptics.warning();
    final failure = await ref
        .read(loansControllerProvider.notifier)
        .delete(loan.id);
    if (!context.mounted) return;
    await showOutcomeToast(context, failure, success: l10n.loanDeleted);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final muted = AppTextStyles.bodyMd.copyWith(
      color: palette.onSurfaceVariant,
    );
    final next = loan.next;
    return CdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  loan.name,
                  style: AppTextStyles.titleSm.copyWith(
                    color: palette.onSurface,
                  ),
                ),
              ),
              PopupMenuButton<_LoanAction>(
                key: LoansScreen.menuKey(loan.id),
                onSelected: (_) => _delete(context, ref),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    key: LoansScreen.deleteKey,
                    value: _LoanAction.delete,
                    child: Text(l10n.loanDelete),
                  ),
                ],
              ),
            ],
          ),
          Text(l10n.loanBalance, style: muted),
          CdAmount(
            loan.balance,
            size: CdAmountSize.lg,
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(
            value: loan.progress,
            color: palette.primary,
            backgroundColor: palette.surfaceContainerHigh,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.loanProgress(loan.paidCount, loan.termMonths),
            style: muted,
          ),
          const SizedBox(height: AppSpacing.md),
          if (next != null)
            CdKeyValueRow(
              label: l10n.loanNext,
              value: CdPrivateText(
                (hide) => l10n.loanNextDue(
                  MoneyFormat.format(next.total, hide: hide),
                  next.dueOn.display,
                ),
              ),
            ),
          CdKeyValueRow(
            label: l10n.loanRemainingInterest,
            value: CdAmount(loan.remaining.interest, size: CdAmountSize.row),
          ),
          CdKeyValueRow(
            label: l10n.loanRate,
            value: Text(
              l10n.loanRateValue(
                loanRateText(l10n, loan.effectiveRate),
                loan.indexer,
              ),
            ),
          ),
          if (loan.lastDueOn case final lastDueOn?)
            CdKeyValueRow(
              label: l10n.loanLastDue,
              value: Text(lastDueOn.display),
            ),
          if (loan.paidLate) ...[
            const SizedBox(height: AppSpacing.md),
            CdInlineBanner(
              icon: Symbols.warning_rounded,
              tone: MoneyTone.overdue,
              message: l10n.loanLateFees(
                MoneyFormat.format(
                  loan.paid.lateFees,
                  hide: ref.watch(hideAmountsProvider),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          CdButton.tonal(
            key: LoansScreen.prepayKey(loan.id),
            expand: true,
            icon: Symbols.savings_rounded,
            label: l10n.loanPrepay,
            onPressed: () => showPrepaymentSheet(context, loan),
          ),
        ],
      ),
    );
  }
}

class _ConfirmDelete extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.loanDeleteMessage,
          style: AppTextStyles.bodyLg.copyWith(
            color: context.palette.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        CdButton.danger(
          key: LoansScreen.confirmDeleteKey,
          expand: true,
          label: l10n.loanDelete,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: AppSpacing.sm),
        CdButton.text(
          expand: true,
          label: l10n.cancelButton,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}
