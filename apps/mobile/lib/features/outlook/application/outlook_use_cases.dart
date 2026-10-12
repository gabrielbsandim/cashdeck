import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/outlook/domain/net_worth.dart';
import 'package:cashdeck/features/outlook/domain/outlook_repository.dart';
import 'package:cashdeck/features/outlook/domain/safe_to_spend.dart';

final class LoadSafeToSpend {
  const new(this._repository);

  final OutlookRepository _repository;

  Future<Result<SafeToSpend>> call(EntityKind entity) =>
      _repository.safeToSpend(entity: entity);
}

final class LoadNetWorth {
  const new(this._repository);

  final OutlookRepository _repository;

  Future<Result<NetWorth>> call(EntityScope scope, NetWorthPeriod period) =>
      _repository.netWorth(scope, period);
}

/// Sets the person's monthly savings target; null goes back to what a
/// typical month leaves over.
final class SetSavingsTarget {
  const new(this._repository);

  final OutlookRepository _repository;

  Future<Result<void>> call(Money? savings) =>
      _repository.setSavingsTarget(savings);
}

final class LoadIncomeSources {
  const new(this._repository);

  final OutlookRepository _repository;

  Future<Result<List<IncomeSourceCandidate>>> call() =>
      _repository.incomeSources();
}

final class SetIncomeSources {
  const new(this._repository);

  final OutlookRepository _repository;

  Future<Result<void>> call(List<IncomeSource> sources) =>
      _repository.setIncomeSources(sources);
}
