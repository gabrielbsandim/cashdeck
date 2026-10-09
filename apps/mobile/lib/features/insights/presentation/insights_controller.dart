import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/insights/application/insights_use_cases.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:cashdeck/features/insights/insights_providers.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/transactions_providers.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

class InsightPeriodController extends Notifier<InsightPeriod> {
  @override
  InsightPeriod build() => InsightPeriod.month;

  InsightPeriod get period => state;

  set period(InsightPeriod period) => state = period;
}

final insightPeriodProvider =
    NotifierProvider<InsightPeriodController, InsightPeriod>(
      InsightPeriodController.new,
    );

final FutureProvider<InsightsOverview> insightsOverviewProvider =
    FutureProvider.autoDispose<InsightsOverview>((ref) async {
      final scope = ref.watch(entityScopeProvider);
      final period = ref.watch(insightPeriodProvider);
      return (await ref.watch(loadInsightsOverviewProvider)(
        scope,
        period,
      )).orThrow;
    }, retry: noRetry);

/// The month Análises looks at and how many months its bars show.
final class MonthWindow extends Equatable {
  const new({this.month, this.count = 6});

  /// Null for the current month.
  final YearMonth? month;
  final int count;

  @override
  List<Object?> get props => [month, count];
}

class MonthWindowController extends Notifier<MonthWindow> {
  @override
  MonthWindow build() => const MonthWindow();

  void show(YearMonth month, {required YearMonth current}) => state =
      MonthWindow(month: month == current ? null : month, count: state.count);

  void count(int count) =>
      state = MonthWindow(month: state.month, count: count);
}

final monthWindowProvider =
    NotifierProvider<MonthWindowController, MonthWindow>(
      MonthWindowController.new,
    );

final FutureProvider<MonthlyInsights> monthlyInsightsProvider =
    FutureProvider.autoDispose<MonthlyInsights>((ref) async {
      final scope = ref.watch(entityScopeProvider);
      final window = ref.watch(monthWindowProvider);
      return (await ref.watch(loadMonthlyInsightsProvider)(
        scope,
        count: window.count,
        month: window.month,
      )).orThrow;
    }, retry: noRetry);

final FutureProvider<Installments> installmentsProvider =
    FutureProvider.autoDispose<Installments>((ref) async {
      final scope = ref.watch(entityScopeProvider);
      return (await ref.watch(loadInstallmentsProvider)(scope)).orThrow;
    }, retry: noRetry);

final FutureProvider<List<CardBills>> cardBillsProvider =
    FutureProvider.autoDispose<List<CardBills>>((ref) async {
      final scope = ref.watch(entityScopeProvider);
      return (await ref.watch(loadCardBillsProvider)(scope)).orThrow;
    }, retry: noRetry);

/// A card and the booking days of one of its bills.
typedef BillCharges = ({String accountId, DateSpan range});

// A bill rarely holds more than a few pages; the cap keeps a wrong range cheap.
const _maxBillPages = 10;

final FutureProviderFamily<List<Transaction>, BillCharges> billChargesProvider =
    FutureProvider.autoDispose.family<List<Transaction>, BillCharges>((
      ref,
      bill,
    ) async {
      final list = ref.watch(listTransactionsProvider);
      final query = TransactionQuery(
        scope: EntityScope.consolidated,
        accountId: bill.accountId,
        from: bill.range.from,
        to: bill.range.to,
      );
      final charges = <Transaction>[];
      String? cursor;
      for (var page = 0; page < _maxBillPages; page++) {
        final result = (await list(query, cursor: cursor)).orThrow;
        charges.addAll(result.items);
        cursor = result.nextCursor;
        if (cursor == null) break;
      }
      return charges;
    }, retry: noRetry);

class SubscriptionsController extends AsyncNotifier<Subscriptions> {
  @override
  Future<Subscriptions> build() async {
    final scope = ref.watch(entityScopeProvider);
    return (await ref.watch(loadSubscriptionsProvider)(scope)).orThrow;
  }

  Future<AppFailure?> decide(
    Subscription suggestion,
    SubscriptionDecision decision,
  ) async {
    final transactionId = suggestion.transactionIds.firstOrNull;
    if (transactionId == null) return const UnexpectedFailure();
    return await _reload(
      await ref.read(decideSubscriptionProvider)(transactionId, decision),
    );
  }

  Future<AppFailure?> remove(Subscription subscription) async {
    final id = subscription.id;
    if (id == null) return const UnexpectedFailure();
    return await _reload(await ref.read(removeSubscriptionProvider)(id));
  }

  Future<AppFailure?> _reload(Result<void> result) async {
    if (result case Err(:final failure)) return failure;
    ref.invalidateSelf();
    await future;
    return null;
  }
}

final AsyncNotifierProvider<SubscriptionsController, Subscriptions>
subscriptionsControllerProvider =
    AsyncNotifierProvider.autoDispose<SubscriptionsController, Subscriptions>(
      SubscriptionsController.new,
      retry: noRetry,
    );
