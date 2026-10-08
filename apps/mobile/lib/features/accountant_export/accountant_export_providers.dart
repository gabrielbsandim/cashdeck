import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/accountant_export/data/fake_accountant_export_repository.dart';
import 'package:cashdeck/features/accountant_export/domain/accountant_export.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// No export endpoint yet, so both backends read the fake.
final accountantExportRepositoryProvider = Provider<AccountantExportRepository>(
  (ref) => FakeAccountantExportRepository(ref.watch(clockProvider)),
);
