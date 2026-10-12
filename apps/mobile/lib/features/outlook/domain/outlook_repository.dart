import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/outlook/domain/net_worth.dart';
import 'package:cashdeck/features/outlook/domain/safe_to_spend.dart';

abstract interface class OutlookRepository {
  Future<Result<SafeToSpend>> safeToSpend();

  Future<Result<NetWorth>> netWorth(EntityScope scope, NetWorthPeriod period);
}
