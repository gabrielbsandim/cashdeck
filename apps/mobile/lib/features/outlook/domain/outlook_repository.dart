import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/outlook/domain/net_worth.dart';
import 'package:cashdeck/features/outlook/domain/safe_to_spend.dart';

abstract interface class OutlookRepository {
  Future<Result<SafeToSpend>> safeToSpend({
    EntityKind entity = EntityKind.personal,
  });

  Future<Result<NetWorth>> netWorth(EntityScope scope, NetWorthPeriod period);

  /// The person's monthly savings target; null goes back to what a typical
  /// month leaves over.
  Future<Result<void>> setSavingsTarget(Money? savings);

  /// The payers of the last six months, the chosen ones flagged.
  Future<Result<List<IncomeSourceCandidate>>> incomeSources();

  /// The payers counted as income; none counts every credit not own money.
  Future<Result<void>> setIncomeSources(List<IncomeSource> sources);
}
