import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/investments/application/investments_use_cases.dart';
import 'package:cashdeck/features/investments/data/api_investments_repository.dart';
import 'package:cashdeck/features/investments/data/fake_investments_repository.dart';
import 'package:cashdeck/features/investments/domain/investments_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final investmentsRepositoryProvider = Provider<InvestmentsRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeInvestmentsRepository(ref.watch(clockProvider)),
    Backend.api => ApiInvestmentsRepository(ref.watch(dioProvider)),
  };
});

final loadInvestmentsProvider = Provider<LoadInvestments>(
  (ref) => LoadInvestments(ref.watch(investmentsRepositoryProvider)),
);
