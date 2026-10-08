import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/home/application/home_use_cases.dart';
import 'package:cashdeck/features/home/data/api_home_repository.dart';
import 'package:cashdeck/features/home/data/fake_home_repository.dart';
import 'package:cashdeck/features/home/domain/home_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeHomeRepository(ref.watch(clockProvider)),
    Backend.api => ApiHomeRepository(ref.watch(dioProvider)),
  };
});

final loadHomeProvider = Provider<LoadHome>(
  (ref) => LoadHome(ref.watch(homeRepositoryProvider)),
);

final approveInvoiceDraftProvider = Provider<ApproveInvoiceDraft>(
  (ref) => ApproveInvoiceDraft(ref.watch(homeRepositoryProvider)),
);

final issueInvoiceForReceiptProvider = Provider<IssueInvoiceForReceipt>(
  (ref) => IssueInvoiceForReceipt(ref.watch(homeRepositoryProvider)),
);
