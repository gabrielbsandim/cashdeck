import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/insights/application/insights_use_cases.dart';
import 'package:cashdeck/features/insights/data/api_insights_repository.dart';
import 'package:cashdeck/features/insights/data/fake_insights_repository.dart';
import 'package:cashdeck/features/insights/domain/insights_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final insightsRepositoryProvider = Provider<InsightsRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeInsightsRepository(ref.watch(clockProvider)),
    Backend.api => ApiInsightsRepository(ref.watch(dioProvider)),
  };
});

final loadInsightsOverviewProvider = Provider<LoadInsightsOverview>(
  (ref) => LoadInsightsOverview(ref.watch(insightsRepositoryProvider)),
);

final loadMonthlyInsightsProvider = Provider<LoadMonthlyInsights>(
  (ref) => LoadMonthlyInsights(ref.watch(insightsRepositoryProvider)),
);

final loadInstallmentsProvider = Provider<LoadInstallments>(
  (ref) => LoadInstallments(ref.watch(insightsRepositoryProvider)),
);

final loadSubscriptionsProvider = Provider<LoadSubscriptions>(
  (ref) => LoadSubscriptions(ref.watch(insightsRepositoryProvider)),
);

final loadCardBillsProvider = Provider<LoadCardBills>(
  (ref) => LoadCardBills(ref.watch(insightsRepositoryProvider)),
);

final decideSubscriptionProvider = Provider<DecideSubscription>(
  (ref) => DecideSubscription(ref.watch(insightsRepositoryProvider)),
);

final removeSubscriptionProvider = Provider<RemoveSubscription>(
  (ref) => RemoveSubscription(ref.watch(insightsRepositoryProvider)),
);
