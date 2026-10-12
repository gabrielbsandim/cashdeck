import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/home/domain/home_summary.dart';
import 'package:cashdeck/features/home/domain/invoice_draft_edit.dart';

abstract interface class HomeRepository {
  Future<Result<PersonalSummary>> personal();

  Future<Result<FundingPlan>> funding();

  Future<Result<CompanySummary>> company();

  Future<Result<ConsolidatedSummary>> consolidated();

  Future<Result<CompanySummary>> approveDraft(String id);

  Future<Result<CompanySummary>> issueInvoiceFor(String receiptId);

  Future<Result<InvoiceDraftDetail>> invoiceDraft(String id);

  /// Saves [edit] on a draft and answers the summary it now shows in.
  Future<Result<CompanySummary>> updateDraft(String id, InvoiceDraftEdit edit);
}
