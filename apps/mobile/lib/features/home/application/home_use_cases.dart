import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/home/domain/home_repository.dart';
import 'package:cashdeck/features/home/domain/home_summary.dart';

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
