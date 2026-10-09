import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_icon_tile.dart';
import 'package:cashdeck/core/widgets/layout/cd_key_value_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_options_sheet.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/entities/presentation/entity_switcher.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transaction_labels.dart';
import 'package:cashdeck/features/transactions/presentation/transaction_pickers.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_controller.dart';
import 'package:cashdeck/features/transactions/transactions_providers.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// One transaction: where it came from, its category and a note. Opened with
/// the row as `extra`, or found among the rows the list already loaded.
class TransactionDetailScreen extends ConsumerStatefulWidget {
  const new({required this.transactionId, this.initial, super.key});

  static const categoryKey = Key('transaction-category');
  static const noteKey = Key('transaction-note');
  static const saveNoteKey = Key('transaction-save-note');
  static const transferKey = Key('transaction-open-transfer');

  static Key categoryOptionKey(String id) => Key('transaction-category-$id');

  final String transactionId;
  final Transaction? initial;

  @override
  ConsumerState<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState
    extends ConsumerState<TransactionDetailScreen> {
  Transaction? _edited;
  var _saving = false;
  final _note = TextEditingController();
  String? _noteSeed;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Transaction? _current() {
    final known = _edited ?? widget.initial;
    if (known != null) return known;
    final loaded = ref.watch(transactionsControllerProvider).value?.items;
    return loaded?.where((item) => item.id == widget.transactionId).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final transaction = _current();
    final listLoading = ref.watch(transactionsControllerProvider).isLoading;
    if (transaction == null) {
      return Scaffold(
        appBar: AppBar(),
        body: listLoading
            ? const CdSkeleton(rows: 3)
            : CdEmptyState(
                icon: Symbols.search_off_rounded,
                title: l10n.transactionNotFound,
              ),
      );
    }
    _seedNote(transaction);
    return Scaffold(
      appBar: AppBar(),
      body: _Body(
        transaction: transaction,
        note: _note,
        saving: _saving,
        onCategory: () => _changeCategory(transaction),
        onSaveNote: () => _save(TransactionUpdate.note(_note.text)),
      ),
    );
  }

  void _seedNote(Transaction transaction) {
    final seed = '${transaction.id}:${transaction.note}';
    if (_noteSeed == seed) return;
    _noteSeed = seed;
    _note.text = transaction.note ?? '';
  }

  Future<void> _changeCategory(Transaction transaction) async {
    final l10n = AppLocalizations.of(context);
    final categories = await ref.read(categoriesProvider.future);
    if (!mounted) return;
    final picked = await showOptionsSheet<Category>(
      context,
      title: l10n.transactionPickCategory,
      options: [
        for (final category in categories)
          PickerOption(
            value: category,
            label: categoryName(l10n, category),
            key: TransactionDetailScreen.categoryOptionKey(category.id),
            icon: categoryIcon(category),
            selected: category.id == transaction.categoryId,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    final apply = await askApplyToSimilar(context);
    if (apply == null) return;
    await _save(
      TransactionUpdate.category(picked.$1.id, applyToSimilar: apply),
    );
  }

  Future<void> _save(TransactionUpdate update) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    final result = await ref
        .read(updateTransactionProvider)
        .call(widget.transactionId, update);
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case Ok(:final value):
        setState(() => _edited = value.transaction);
        _refreshList(value);
        await showCdToast(
          context,
          icon: Symbols.task_alt_rounded,
          message: _savedMessage(l10n, update, value.similarUpdated),
        );
      case Err(:final failure):
        await showOutcomeToast(context, failure, success: '');
    }
  }

  void _refreshList(TransactionUpdateResult result) {
    if (result.similarUpdated > 0) {
      ref.invalidate(transactionsControllerProvider);
      return;
    }
    ref
        .read(transactionsControllerProvider.notifier)
        .replace(result.transaction);
  }

  static String _savedMessage(
    AppLocalizations l10n,
    TransactionUpdate update,
    int similar,
  ) {
    if (update.categoryId == null) return l10n.transactionNoteSaved;
    if (similar == 0) return l10n.transactionCategorySaved;
    return l10n.transactionCategorySavedSimilar(similar);
  }
}

class _Body extends ConsumerWidget {
  const new({
    required this.transaction,
    required this.note,
    required this.saving,
    required this.onCategory,
    required this.onSaveNote,
  });

  final Transaction transaction;
  final TextEditingController note;
  final bool saving;
  final VoidCallback onCategory;
  final VoidCallback onSaveNote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final accounts = ref.watch(transactionAccountsProvider).value ?? const [];
    final account = accounts
        .where((item) => item.id == transaction.accountId)
        .firstOrNull;
    final source = categorySourceLabel(l10n, transaction);
    final transferId = transaction.transferId;
    final secondary = AppTextStyles.bodyMd.copyWith(
      color: palette.onSurfaceVariant,
    );
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      children: [
        Center(
          child: CdIconTile(
            categoryIcon(categoryOf(transaction, categories)),
            size: 56,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          transaction.description,
          textAlign: TextAlign.center,
          style: AppTextStyles.titleMd.copyWith(color: palette.onSurface),
        ),
        CdAmount(
          transaction.amount,
          size: CdAmountSize.lg,
          kind: amountKindOf(transaction),
          textAlign: TextAlign.center,
        ),
        Text(
          transaction.bookedOn.display,
          textAlign: TextAlign.center,
          style: secondary,
        ),
        const SizedBox(height: AppSpacing.xl),
        CdCard(
          child: Column(
            children: [
              CdKeyValueRow(
                label: l10n.transactionAccountLabel,
                value: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EntityKindBadge(kind: transaction.owner, size: 24),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        account?.name ?? l10n.transactionAccountUnknown,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: AppSpacing.lg),
              CdListRow(
                key: TransactionDetailScreen.categoryKey,
                padding: EdgeInsets.zero,
                icon: Symbols.category_rounded,
                title: transactionCategoryLabel(l10n, transaction, categories),
                subtitle: source ?? l10n.transactionCategoryHint,
                chevron: true,
                onTap: saving ? null : onCategory,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        CdTextField(
          key: TransactionDetailScreen.noteKey,
          label: l10n.transactionNoteLabel,
          hintText: l10n.transactionNoteHint,
          controller: note,
          maxLines: 3,
        ),
        const SizedBox(height: AppSpacing.sm),
        CdButton.tonal(
          key: TransactionDetailScreen.saveNoteKey,
          label: l10n.transactionSaveNote,
          loading: saving,
          onPressed: onSaveNote,
        ),
        if (transaction.opensTransfer && transferId != null) ...[
          const SizedBox(height: AppSpacing.lg),
          CdButton.outlined(
            key: TransactionDetailScreen.transferKey,
            icon: Symbols.sync_alt_rounded,
            label: l10n.transactionOpenTransfer,
            onPressed: () => context.go(AppRoutes.transfer(transferId)),
          ),
        ],
      ],
    );
  }
}
