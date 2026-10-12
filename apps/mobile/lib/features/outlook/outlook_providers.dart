import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/outlook/application/outlook_use_cases.dart';
import 'package:cashdeck/features/outlook/data/api_outlook_repository.dart';
import 'package:cashdeck/features/outlook/data/fake_outlook_repository.dart';
import 'package:cashdeck/features/outlook/domain/outlook_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final outlookRepositoryProvider = Provider<OutlookRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeOutlookRepository(ref.watch(clockProvider)),
    Backend.api => ApiOutlookRepository(ref.watch(dioProvider)),
  };
});

final loadSafeToSpendProvider = Provider<LoadSafeToSpend>(
  (ref) => LoadSafeToSpend(ref.watch(outlookRepositoryProvider)),
);

final setSavingsTargetProvider = Provider<SetSavingsTarget>(
  (ref) => SetSavingsTarget(ref.watch(outlookRepositoryProvider)),
);

final loadIncomeSourcesProvider = Provider<LoadIncomeSources>(
  (ref) => LoadIncomeSources(ref.watch(outlookRepositoryProvider)),
);

final setIncomeSourcesProvider = Provider<SetIncomeSources>(
  (ref) => SetIncomeSources(ref.watch(outlookRepositoryProvider)),
);

final loadNetWorthProvider = Provider<LoadNetWorth>(
  (ref) => LoadNetWorth(ref.watch(outlookRepositoryProvider)),
);
