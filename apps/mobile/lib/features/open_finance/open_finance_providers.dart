import 'package:cashdeck/features/open_finance/data/fake_open_finance_repository.dart';
import 'package:cashdeck/features/open_finance/domain/item_lookup.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// No item id endpoint yet, so both backends read the fake.
final openFinanceRepositoryProvider = Provider<OpenFinanceRepository>(
  (ref) => FakeOpenFinanceRepository(),
);
