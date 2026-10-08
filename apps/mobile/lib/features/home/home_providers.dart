import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/home/application/home_use_cases.dart';
import 'package:cashdeck/features/home/data/fake_home_repository.dart';
import 'package:cashdeck/features/home/domain/home_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The API has no summary endpoint yet, so both backends read the fake.
final homeRepositoryProvider = Provider<HomeRepository>(
  (ref) => FakeHomeRepository(ref.watch(clockProvider)),
);

final loadHomeProvider = Provider<LoadHome>(
  (ref) => LoadHome(ref.watch(homeRepositoryProvider)),
);

final approveInvoiceDraftProvider = Provider<ApproveInvoiceDraft>(
  (ref) => ApproveInvoiceDraft(ref.watch(homeRepositoryProvider)),
);

final issueInvoiceForReceiptProvider = Provider<IssueInvoiceForReceipt>(
  (ref) => IssueInvoiceForReceipt(ref.watch(homeRepositoryProvider)),
);
