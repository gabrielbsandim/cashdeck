import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/insights/domain/card_timeline.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:cashdeck/features/insights/domain/insights_repository.dart';

final class LoadInsightsOverview {
  const new(this._repository);

  final InsightsRepository _repository;

  Future<Result<InsightsOverview>> call(
    EntityScope scope,
    InsightPeriod period,
  ) => _repository.overview(scope, period);
}

/// Six or twelve months ending at `month`, the current one by default.
final class LoadMonthlyInsights {
  const new(this._repository);

  final InsightsRepository _repository;

  static const counts = [6, 12];

  Future<Result<MonthlyInsights>> call(
    EntityScope scope, {
    int count = 6,
    YearMonth? month,
  }) {
    if (!counts.contains(count)) {
      throw ArgumentError.value(count, 'count', 'Expected 6 or 12');
    }
    return _repository.months(scope, count: count, month: month);
  }
}

final class LoadInstallments {
  const new(this._repository);

  final InsightsRepository _repository;

  Future<Result<Installments>> call(EntityScope scope) =>
      _repository.installments(scope);
}

/// Confirmed subscriptions and suggestions, each list by charge day.
final class LoadSubscriptions {
  const new(this._repository);

  final InsightsRepository _repository;

  Future<Result<Subscriptions>> call(EntityScope scope) =>
      _repository.subscriptions(scope);
}

/// Each card with its bills, newest first.
final class LoadCardBills {
  const new(this._repository);

  final InsightsRepository _repository;

  Future<Result<List<CardBills>>> call(EntityScope scope) =>
      _repository.cardBills(scope);
}

final class LoadCardTimeline {
  const new(this._repository);

  final InsightsRepository _repository;

  Future<Result<CardTimeline>> call(String accountId) =>
      _repository.cardTimeline(accountId);
}

enum SubscriptionDecision { confirm, dismiss }

final class DecideSubscription {
  const new(this._repository);

  final InsightsRepository _repository;

  Future<Result<void>> call(
    String transactionId,
    SubscriptionDecision decision,
  ) async {
    if (decision == SubscriptionDecision.dismiss) {
      return await _repository.dismissSubscription(transactionId);
    }
    return switch (await _repository.confirmSubscription(transactionId)) {
      Ok() => const Ok(null),
      Err(:final failure) => Err(failure),
    };
  }
}

final class RemoveSubscription {
  const new(this._repository);

  final InsightsRepository _repository;

  Future<Result<void>> call(String id) => _repository.removeSubscription(id);
}
