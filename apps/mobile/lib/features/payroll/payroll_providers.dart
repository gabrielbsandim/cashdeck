import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/payroll/data/fake_payroll_repository.dart';
import 'package:cashdeck/features/payroll/domain/payroll.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// No payroll endpoint yet, so both backends read the fake.
final payrollRepositoryProvider = Provider<PayrollRepository>(
  (ref) => FakePayrollRepository(ref.watch(clockProvider)),
);
