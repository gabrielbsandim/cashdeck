import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/insights/domain/card_timeline.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';

abstract interface class InsightsRepository {
  Future<Result<InsightsOverview>> overview(
    EntityScope scope,
    InsightPeriod period,
  );

  Future<Result<MonthlyInsights>> months(
    EntityScope scope, {
    required int count,
    YearMonth? month,
  });

  Future<Result<Installments>> installments(EntityScope scope);

  Future<Result<Subscriptions>> subscriptions(EntityScope scope);

  Future<Result<List<CardBills>>> cardBills(EntityScope scope);

  /// One card's bills, past, open and forecast, oldest first.
  Future<Result<CardTimeline>> cardTimeline(String accountId);

  /// Confirms the recurrence [transactionId] belongs to; returns its id.
  Future<Result<String>> confirmSubscription(String transactionId);

  Future<Result<void>> dismissSubscription(String transactionId);

  Future<Result<void>> removeSubscription(String id);
}
