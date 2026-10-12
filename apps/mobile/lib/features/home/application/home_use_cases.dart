import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/home/domain/home_repository.dart';
import 'package:cashdeck/features/home/domain/home_summary.dart';
import 'package:cashdeck/features/home/domain/invoice_draft_edit.dart';

/// The summary Início shows for [EntityScope].
final class LoadHome {
  const new(this._repository);

  final HomeRepository _repository;

  Future<Result<HomeSummary>> call(EntityScope scope) async {
    final result = switch (scope) {
      EntityScope.personal => await _repository.personal(),
      EntityScope.company => await _repository.company(),
      EntityScope.consolidated => await _repository.consolidated(),
    };
    return result;
  }
}

/// What the Asaas balance pays a month and what it lacks now.
final class LoadFundingPlan {
  const new(this._repository);

  final HomeRepository _repository;

  Future<Result<FundingPlan>> call() => _repository.funding();
}

final class ApproveInvoiceDraft {
  const new(this._repository);

  final HomeRepository _repository;

  Future<Result<CompanySummary>> call(String id) =>
      _repository.approveDraft(id);
}

final class IssueInvoiceForReceipt {
  const new(this._repository);

  final HomeRepository _repository;

  Future<Result<CompanySummary>> call(String receiptId) =>
      _repository.issueInvoiceFor(receiptId);
}

/// A draft as the editor opens it.
final class LoadInvoiceDraft {
  const new(this._repository);

  final HomeRepository _repository;

  Future<Result<InvoiceDraftDetail>> call(String id) =>
      _repository.invoiceDraft(id);
}

/// Saves what the user changed in a draft; with nothing changed nothing is
/// sent and the summary is read again.
final class UpdateInvoiceDraft {
  const new(this._repository);

  final HomeRepository _repository;

  Future<Result<CompanySummary>> call(String id, InvoiceDraftEdit edit) {
    if (edit.isEmpty) return _repository.company();
    return _repository.updateDraft(id, edit);
  }
}
