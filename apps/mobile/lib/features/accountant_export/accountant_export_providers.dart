import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/accountant_export/data/api_accountant_export_repository.dart';
import 'package:cashdeck/features/accountant_export/data/fake_accountant_export_repository.dart';
import 'package:cashdeck/features/accountant_export/domain/accountant_export.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final accountantExportRepositoryProvider = Provider<AccountantExportRepository>(
  (ref) {
    return switch (ref.watch(appConfigProvider).backend) {
      Backend.fake => FakeAccountantExportRepository(ref.watch(clockProvider)),
      Backend.api => ApiAccountantExportRepository(ref.watch(dioProvider)),
    };
  },
);
