import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/transactions/data/fake_transfers_repository.dart';
import 'package:cashdeck/features/transactions/domain/internal_transfer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// No transfer endpoint yet, so both backends read the fake.
final transfersRepositoryProvider = Provider<TransfersRepository>(
  (ref) => FakeTransfersRepository(ref.watch(clockProvider)),
);
