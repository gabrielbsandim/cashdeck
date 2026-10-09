import 'dart:async';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_filter_chip.dart';
import 'package:cashdeck/core/widgets/inputs/cd_search_field.dart';
import 'package:cashdeck/core/widgets/layout/cd_options_sheet.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/money/cd_transaction_row.dart';
import 'package:cashdeck/core/widgets/money/privacy_toggle.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/entities/presentation/entity_switcher.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transaction_labels.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const new({super.key});

  static const searchKey = Key('transactions-search');
  static const accountFilterKey = Key('transactions-filter-account');
  static const categoryFilterKey = Key('transactions-filter-category');
  static const loadMoreKey = Key('transactions-load-more');
  static const allOptionKey = Key('transactions-filter-all');
  static const uncategorizedOptionKey = Key(
    'transactions-filter-uncategorized',
  );

  static Key rowKey(String id) => Key('transaction-$id');

  static Key optionKey(String id) => Key('transactions-option-$id');

  /// How long typing pauses before the search runs.
  static const searchDelay = Duration(milliseconds: 350);

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      TransactionsScreen.searchDelay,
      () => ref.read(transactionFiltersProvider.notifier).search(text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final transactions = ref.watch(transactionsControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.transactionsTitle),
        actions: const [PrivacyToggle()],
      ),
      body: Column(
        children: [
          const EntitySwitcher(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.sm,
              AppSpacing.screenGutter,
              0,
            ),
            child: CdSearchField(
              key: TransactionsScreen.searchKey,
              controller: _search,
              hint: l10n.transactionsSearchHint,
              onChanged: _onSearch,
              loading: transactions.isLoading && transactions.hasValue,
            ),
          ),
          const _FilterBar(),
          Expanded(
            child: switch (transactions) {
              AsyncValue(value: final list?) when list.items.isEmpty => _Empty(
                filtered: list.filtered,
                onClear: _clearFilters,
              ),
              AsyncValue(value: final list?) => _TransactionList(list: list),
              AsyncError(:final error) => CdErrorState(
                failure: failureOf(error),
                onRetry: () => ref.invalidate(transactionsControllerProvider),
              ),
              _ => const CdSkeleton(rows: 6),
            },
          ),
        ],
      ),
    );
  }

  void _clearFilters() {
    _search.clear();
    ref.read(transactionFiltersProvider.notifier).clear();
  }
}

class _Empty extends StatelessWidget {
  const new({required this.filtered, required this.onClear});

  final bool filtered;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (filtered) {
      return CdEmptyState(
        icon: Symbols.search_off_rounded,
        title: l10n.transactionsNoMatchTitle,
        message: l10n.transactionsNoMatchMessage,
        actionLabel: l10n.transactionsClearFilters,
        onAction: onClear,
      );
    }
    return CdEmptyState(
      icon: Symbols.receipt_long_rounded,
      title: l10n.transactionsEmptyTitle,
      message: l10n.transactionsEmptyMessage,
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const new();

  Future<void> _pickAccount(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final filters = ref.read(transactionFiltersProvider);
    final accounts = await ref.read(transactionAccountsProvider.future);
    if (!context.mounted) return;
    final picked = await showOptionsSheet<String?>(
      context,
      title: l10n.transactionsFilterAccount,
      options: [
        PickerOption(
          value: null,
          label: l10n.transactionsAllAccounts,
          key: TransactionsScreen.allOptionKey,
          selected: filters.accountId == null,
        ),
        for (final account in accounts)
          PickerOption(
            value: account.id,
            label: account.name,
            key: TransactionsScreen.optionKey(account.id),
            icon: Symbols.account_balance_rounded,
            selected: filters.accountId == account.id,
          ),
      ],
    );
    if (picked == null) return;
    ref.read(transactionFiltersProvider.notifier).selectAccount(picked.$1);
  }

  Future<void> _pickCategory(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final filters = ref.read(transactionFiltersProvider);
    final categories = await ref.read(categoriesProvider.future);
    if (!context.mounted) return;
    final picked = await showOptionsSheet<(String?, bool)>(
      context,
      title: l10n.transactionsFilterCategory,
      options: [
        PickerOption(
          value: (null, false),
          label: l10n.transactionsAllCategories,
          key: TransactionsScreen.allOptionKey,
          selected: filters.categoryId == null && !filters.uncategorized,
        ),
        PickerOption(
          value: (null, true),
          label: l10n.transactionUncategorized,
          key: TransactionsScreen.uncategorizedOptionKey,
          icon: Symbols.help_rounded,
          selected: filters.uncategorized,
        ),
        for (final category in categories)
          PickerOption(
            value: (category.id, false),
            label: categoryName(l10n, category),
            key: TransactionsScreen.optionKey(category.id),
            icon: categoryIcon(category),
            selected: filters.categoryId == category.id,
          ),
      ],
    );
    if (picked == null) return;
    final (categoryId, uncategorized) = picked.$1;
    ref
        .read(transactionFiltersProvider.notifier)
        .selectCategory(categoryId, uncategorized: uncategorized);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final filters = ref.watch(transactionFiltersProvider);
    final accounts = ref.watch(transactionAccountsProvider).value ?? const [];
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final account = accounts
        .where((item) => item.id == filters.accountId)
        .firstOrNull;
    final category = categories
        .where((item) => item.id == filters.categoryId)
        .firstOrNull;
    final categoryLabel = switch ((filters.uncategorized, category)) {
      (true, _) => l10n.transactionUncategorized,
      (false, final Category chosen) => categoryName(l10n, chosen),
      (false, null) => l10n.transactionsFilterCategory,
    };
    final categorySet = filters.uncategorized || filters.categoryId != null;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenGutter),
      child: Row(
        children: [
          CdFilterChip(
            key: TransactionsScreen.accountFilterKey,
            label: account?.name ?? l10n.transactionsFilterAccount,
            icon: Symbols.account_balance_rounded,
            dropdown: true,
            selected: filters.accountId != null,
            onTap: () => _pickAccount(context, ref),
          ),
          const SizedBox(width: AppSpacing.sm),
          CdFilterChip(
            key: TransactionsScreen.categoryFilterKey,
            label: categoryLabel,
            icon: Symbols.category_rounded,
            dropdown: true,
            selected: categorySet,
            onTap: () => _pickCategory(context, ref),
          ),
        ],
      ),
    );
  }
}

class _TransactionList extends ConsumerWidget {
  const new({required this.list});

  final TransactionList list;

  Future<void> _loadMore(BuildContext context, WidgetRef ref) async {
    final failure = await ref
        .read(transactionsControllerProvider.notifier)
        .loadMore();
    if (failure == null || !context.mounted) return;
    await showOutcomeToast(context, failure, success: '');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final today = CalendarDate.brazilToday(ref.watch(clockProvider).now());
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final consolidated =
        ref.watch(entityScopeProvider) == EntityScope.consolidated;
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: [
        for (final day in groupByDay(list.items)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.lg,
              AppSpacing.screenGutter,
              AppSpacing.xs,
            ),
            child: CdSectionHeader(
              title: dayLabel(l10n, day.day, today, locale),
              small: true,
            ),
          ),
          for (final transaction in day.items)
            CdTransactionRow(
              key: TransactionsScreen.rowKey(transaction.id),
              icon: categoryIcon(categoryOf(transaction, categories)),
              leading: consolidated
                  ? EntityKindBadge(kind: transaction.owner, size: 40)
                  : null,
              title: transaction.description,
              subtitle: transactionCategoryLabel(l10n, transaction, categories),
              amount: transaction.amount,
              kind: amountKindOf(transaction),
              onTap: () => _open(context, transaction),
            ),
        ],
        if (list.hasMore)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: CdButton.text(
              key: TransactionsScreen.loadMoreKey,
              label: l10n.transactionsLoadMore,
              loading: list.loadingMore,
              onPressed: () => _loadMore(context, ref),
            ),
          ),
      ],
    );
  }

  void _open(BuildContext context, Transaction transaction) {
    final transferId = transaction.transferId;
    if (transaction.opensTransfer && transferId != null) {
      context.go(AppRoutes.transfer(transferId));
      return;
    }
    context.go(AppRoutes.transaction(transaction.id), extra: transaction);
  }
}
