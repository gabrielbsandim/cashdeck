import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/rails/data/fake_rails_repository.dart';
import 'package:cashdeck/features/rails/domain/payment_rail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// No rails endpoint yet, so both backends read the fake.
final railsRepositoryProvider = Provider<RailsRepository>(
  (ref) => FakeRailsRepository(ref.watch(clockProvider)),
);
