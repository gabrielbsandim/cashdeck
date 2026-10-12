import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/loans/application/loans_use_cases.dart';
import 'package:cashdeck/features/loans/data/api_loans_repository.dart';
import 'package:cashdeck/features/loans/data/fake_loans_repository.dart';
import 'package:cashdeck/features/loans/domain/loan.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final loansRepositoryProvider = Provider<LoansRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeLoansRepository(ref.watch(clockProvider)),
    Backend.api => ApiLoansRepository(ref.watch(dioProvider)),
  };
});

final listLoansProvider = Provider<ListLoans>(
  (ref) => ListLoans(ref.watch(loansRepositoryProvider)),
);

final importLoanStatementProvider = Provider<ImportLoanStatement>(
  (ref) => ImportLoanStatement(ref.watch(loansRepositoryProvider)),
);

final simulatePrepaymentProvider = Provider<SimulatePrepayment>(
  (ref) => SimulatePrepayment(ref.watch(loansRepositoryProvider)),
);

final deleteLoanProvider = Provider<DeleteLoan>(
  (ref) => DeleteLoan(ref.watch(loansRepositoryProvider)),
);
