import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/bills/application/bills_use_cases.dart';
import 'package:cashdeck/features/bills/data/api_bills_repository.dart';
import 'package:cashdeck/features/bills/data/fake_bills_repository.dart';
import 'package:cashdeck/features/bills/domain/bills_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final billsRepositoryProvider = Provider<BillsRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeBillsRepository(ref.watch(clockProvider)),
    Backend.api => ApiBillsRepository(ref.watch(dioProvider)),
  };
});

final listBillsProvider = Provider<ListBills>(
  (ref) => ListBills(ref.watch(billsRepositoryProvider)),
);

final getBillProvider = Provider<GetBill>(
  (ref) => GetBill(ref.watch(billsRepositoryProvider)),
);

final markBillPaidProvider = Provider<MarkBillPaid>(
  (ref) => MarkBillPaid(ref.watch(billsRepositoryProvider)),
);

final confirmBillPaymentProvider = Provider<ConfirmBillPayment>(
  (ref) => ConfirmBillPayment(ref.watch(billsRepositoryProvider)),
);
