import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/investments/domain/investments.dart';

abstract interface class InvestmentsRepository {
  Future<Result<Investments>> investments(EntityScope scope);
}
