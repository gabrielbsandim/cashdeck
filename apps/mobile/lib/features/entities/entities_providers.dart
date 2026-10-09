import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/entities/data/api_entity_profile_repository.dart';
import 'package:cashdeck/features/entities/data/fake_entity_profile_repository.dart';
import 'package:cashdeck/features/entities/domain/entity_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final entityProfileRepositoryProvider = Provider<EntityProfileRepository>((
  ref,
) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeEntityProfileRepository(),
    Backend.api => ApiEntityProfileRepository(ref.watch(dioProvider)),
  };
});
