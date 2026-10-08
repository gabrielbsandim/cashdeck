import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/receipts/data/fake_receipts_repository.dart';
import 'package:cashdeck/features/receipts/domain/receipt.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// No receipt endpoint yet, so both backends read the fake.
final receiptsRepositoryProvider = Provider<ReceiptsRepository>(
  (ref) => FakeReceiptsRepository(ref.watch(clockProvider)),
);
