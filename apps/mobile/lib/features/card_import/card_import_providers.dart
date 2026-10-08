import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/card_import/data/fake_card_import_repository.dart';
import 'package:cashdeck/features/card_import/domain/card_statement.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// No statement endpoint yet, so both backends read the fake.
final cardImportRepositoryProvider = Provider<CardImportRepository>(
  (ref) => FakeCardImportRepository(ref.watch(clockProvider)),
);
