import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/recap/application/recap_use_cases.dart';
import 'package:cashdeck/features/recap/data/api_recap_repository.dart';
import 'package:cashdeck/features/recap/data/fake_recap_repository.dart';
import 'package:cashdeck/features/recap/domain/monthly_recap.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final recapRepositoryProvider = Provider<RecapRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => const FakeRecapRepository(),
    Backend.api => ApiRecapRepository(ref.watch(dioProvider)),
  };
});

final getMonthlyRecapProvider = Provider<GetMonthlyRecap>(
  (ref) => GetMonthlyRecap(ref.watch(recapRepositoryProvider)),
);
