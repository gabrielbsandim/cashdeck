import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/transactions/data/api_transfers_repository.dart';
import 'package:cashdeck/features/transactions/data/fake_transfers_repository.dart';
import 'package:cashdeck/features/transactions/domain/internal_transfer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final transfersRepositoryProvider = Provider<TransfersRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeTransfersRepository(ref.watch(clockProvider)),
    Backend.api => ApiTransfersRepository(ref.watch(dioProvider)),
  };
});
