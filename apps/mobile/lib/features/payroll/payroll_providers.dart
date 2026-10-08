import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/payroll/data/api_payroll_repository.dart';
import 'package:cashdeck/features/payroll/data/fake_payroll_repository.dart';
import 'package:cashdeck/features/payroll/domain/payroll.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final payrollRepositoryProvider = Provider<PayrollRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakePayrollRepository(ref.watch(clockProvider)),
    Backend.api => ApiPayrollRepository(ref.watch(dioProvider)),
  };
});
