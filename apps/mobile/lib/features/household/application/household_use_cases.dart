import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/household/domain/household.dart';

final class LoadHousehold {
  const new(this._repository);

  final HouseholdRepository _repository;

  Future<Result<Household>> call() => _repository.get();
}

/// Saves the whole list. A list that breaks a rule never reaches the server.
final class SaveHousehold {
  const new(this._repository);

  final HouseholdRepository _repository;

  Future<Result<Household>> call(Household household) {
    if (!household.isValid) {
      return Future.value(const Err(UnexpectedFailure()));
    }
    return _repository.save(household);
  }
}
