import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/home/domain/home_summary.dart';

abstract interface class HomeRepository {
  Future<Result<PersonalSummary>> personal();

  Future<Result<FundingPlan>> funding();

  Future<Result<CompanySummary>> company();

  Future<Result<ConsolidatedSummary>> consolidated();

  Future<Result<CompanySummary>> approveDraft(String id);

  Future<Result<CompanySummary>> issueInvoiceFor(String receiptId);
}
