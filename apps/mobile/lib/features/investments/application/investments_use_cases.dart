import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/investments/domain/investments.dart';
import 'package:cashdeck/features/investments/domain/investments_repository.dart';

final class LoadInvestments {
  const new(this._repository);

  final InvestmentsRepository _repository;

  Future<Result<Investments>> call(EntityScope scope) =>
      _repository.investments(scope);
}

final class LoadInvestmentPerformance {
  const new(this._repository);

  final InvestmentsRepository _repository;

  Future<Result<InvestmentPerformance>> call(
    EntityScope scope,
    PerformancePeriod period,
  ) => _repository.performance(scope, period);
}

final class LoadInvestmentDetail {
  const new(this._repository);

  final InvestmentsRepository _repository;

  Future<Result<InvestmentDetail>> call(String id, PerformancePeriod period) =>
      _repository.position(id, period);
}
