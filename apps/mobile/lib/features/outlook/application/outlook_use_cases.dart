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
