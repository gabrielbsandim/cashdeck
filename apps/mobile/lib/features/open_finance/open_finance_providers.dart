import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/open_finance/data/api_open_finance_repository.dart';
import 'package:cashdeck/features/open_finance/data/fake_open_finance_repository.dart';
import 'package:cashdeck/features/open_finance/domain/item_lookup.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final openFinanceRepositoryProvider = Provider<OpenFinanceRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeOpenFinanceRepository(),
    Backend.api => ApiOpenFinanceRepository(ref.watch(dioProvider)),
  };
});
