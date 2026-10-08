import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/rails/data/api_rails_repository.dart';
import 'package:cashdeck/features/rails/data/fake_rails_repository.dart';
import 'package:cashdeck/features/rails/domain/payment_rail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final railsRepositoryProvider = Provider<RailsRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeRailsRepository(ref.watch(clockProvider)),
    Backend.api => ApiRailsRepository(ref.watch(dioProvider)),
  };
});
