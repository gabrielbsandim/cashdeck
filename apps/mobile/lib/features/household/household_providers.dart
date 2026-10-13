import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/household/application/household_use_cases.dart';
import 'package:cashdeck/features/household/data/api_household_repository.dart';
import 'package:cashdeck/features/household/data/fake_household_repository.dart';
import 'package:cashdeck/features/household/domain/household.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final householdRepositoryProvider = Provider<HouseholdRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeHouseholdRepository(),
    Backend.api => ApiHouseholdRepository(ref.watch(dioProvider)),
  };
});

final loadHouseholdProvider = Provider<LoadHousehold>(
  (ref) => LoadHousehold(ref.watch(householdRepositoryProvider)),
);

final saveHouseholdProvider = Provider<SaveHousehold>(
  (ref) => SaveHousehold(ref.watch(householdRepositoryProvider)),
);
