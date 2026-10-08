import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/receipts/data/api_receipts_repository.dart';
import 'package:cashdeck/features/receipts/data/fake_receipts_repository.dart';
import 'package:cashdeck/features/receipts/domain/receipt.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final receiptsRepositoryProvider = Provider<ReceiptsRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeReceiptsRepository(ref.watch(clockProvider)),
    Backend.api => ApiReceiptsRepository(ref.watch(dioProvider)),
  };
});
