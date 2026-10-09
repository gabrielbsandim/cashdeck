import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/transactions_providers.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The filters the user set on the list; the scope comes from the switcher.
final class TransactionFilters extends Equatable {
  const new({
    this.accountId,
    this.categoryId,
    this.uncategorized = false,
    this.search = '',
    this.from,
    this.to,
  });

  final String? accountId;
  final String? categoryId;
  final bool uncategorized;
  final String search;

  /// Booking days to keep, both included; both null or both set.
  final CalendarDate? from;
  final CalendarDate? to;

  TransactionQuery queryFor(EntityScope scope) => TransactionQuery(
    scope: scope,
    accountId: accountId,
    categoryId: categoryId,
    uncategorized: uncategorized,
    search: search,
    from: from,
    to: to,
  );

  @override
  List<Object?> get props => [
    accountId,
    categoryId,
    uncategorized,
    search,
    from,
    to,
  ];
}

class TransactionFiltersController extends Notifier<TransactionFilters> {
  @override
  TransactionFilters build() {
    ref.listen(entityScopeProvider, (_, _) => selectAccount(null));
    return const TransactionFilters();
  }

  void search(String text) => state = TransactionFilters(
    accountId: state.accountId,
    categoryId: state.categoryId,
    uncategorized: state.uncategorized,
    search: text.trim(),
    from: state.from,
    to: state.to,
  );

  void selectAccount(String? accountId) => state = TransactionFilters(
    accountId: accountId,
    categoryId: state.categoryId,
    uncategorized: state.uncategorized,
    search: state.search,
    from: state.from,
    to: state.to,
  );

  /// One category, only the uncategorized ones, or every category.
  void selectCategory(String? categoryId, {bool uncategorized = false}) =>
      state = TransactionFilters(
        accountId: state.accountId,
        categoryId: uncategorized ? null : categoryId,
        uncategorized: uncategorized,
        search: state.search,
        from: state.from,
        to: state.to,
      );

  /// From [from] to [to], both included; the same day twice keeps one day.
  void selectDays(CalendarDate from, CalendarDate to) {
    if (to.isBefore(from)) {
      throw ArgumentError.value(to, 'to', 'Expected on or after from');
    }
    state = _withDays(from, to);
  }

  void clearDays() => state = _withDays(null, null);

  TransactionFilters _withDays(CalendarDate? from, CalendarDate? to) =>
      TransactionFilters(
        accountId: state.accountId,
        categoryId: state.categoryId,
        uncategorized: state.uncategorized,
        search: state.search,
        from: from,
        to: to,
      );

  void clear() => state = const TransactionFilters();
}

final NotifierProvider<TransactionFiltersController, TransactionFilters>
transactionFiltersProvider =
    NotifierProvider.autoDispose<
      TransactionFiltersController,
      TransactionFilters
    >(TransactionFiltersController.new);

/// What the list holds: the pages loaded so far and the cursor of the next.
final class TransactionList extends Equatable {
  const new({
    required this.items,
    required this.filtered,
    this.nextCursor,
    this.loadingMore = false,
  });

  final List<Transaction> items;
  final String? nextCursor;
  final bool loadingMore;

  /// True when a filter or a search narrowed the list.
  final bool filtered;

  bool get hasMore => nextCursor != null;

  TransactionList copyWith({
    List<Transaction>? items,
    String? nextCursor,
    bool clearCursor = false,
    bool? loadingMore,
  }) => TransactionList(
    items: items ?? this.items,
    filtered: filtered,
    nextCursor: clearCursor ? null : nextCursor ?? this.nextCursor,
    loadingMore: loadingMore ?? this.loadingMore,
  );

  @override
  List<Object?> get props => [items, nextCursor, loadingMore, filtered];
}

class TransactionsController extends AsyncNotifier<TransactionList> {
  late TransactionQuery _query;

  @override
  Future<TransactionList> build() async {
    final scope = ref.watch(entityScopeProvider);
    _query = ref.watch(transactionFiltersProvider).queryFor(scope);
    final page = (await ref.watch(listTransactionsProvider).call(_query))
        .orThrow;
    return TransactionList(
      items: page.items,
      nextCursor: page.nextCursor,
      filtered: _query.filtered,
    );
  }

  Future<AppFailure?> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) {
      return null;
    }
    state = AsyncData(current.copyWith(loadingMore: true));
    final result = await ref
        .read(listTransactionsProvider)
        .call(_query, cursor: current.nextCursor);
    switch (result) {
      case Ok(:final value):
        state = AsyncData(
          current.copyWith(
            items: [...current.items, ...value.items],
            nextCursor: value.nextCursor,
            clearCursor: value.nextCursor == null,
            loadingMore: false,
          ),
        );
        return null;
      case Err(:final failure):
        state = AsyncData(current);
        return failure;
    }
  }

  /// Puts a transaction changed on its detail screen back in the list.
  void replace(Transaction transaction) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        items: [
          for (final item in current.items)
            if (item.id == transaction.id) transaction else item,
        ],
      ),
    );
  }
}

final AsyncNotifierProvider<TransactionsController, TransactionList>
transactionsControllerProvider =
    AsyncNotifierProvider.autoDispose<TransactionsController, TransactionList>(
      TransactionsController.new,
      retry: noRetry,
    );

final FutureProvider<List<Category>> categoriesProvider =
    FutureProvider.autoDispose<List<Category>>(
      (ref) async => (await ref.watch(listCategoriesProvider).call()).orThrow,
      retry: noRetry,
    );

final FutureProvider<List<TransactionAccount>> transactionAccountsProvider =
    FutureProvider.autoDispose<List<TransactionAccount>>(
      (ref) async =>
          (await ref
                  .watch(listTransactionAccountsProvider)
                  .call(ref.watch(entityScopeProvider)))
              .orThrow,
      retry: noRetry,
    );
