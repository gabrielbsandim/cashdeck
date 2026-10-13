import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/household/domain/household.dart';

/// A fictional household in memory, with the server's rules.
final class FakeHouseholdRepository implements HouseholdRepository {
  new({this.latency = const Duration(milliseconds: 300)});

  final Duration latency;
  var _household = const Household([
    HouseholdMember(name: 'Ana Exemplo', taxId: '11144477735'),
  ]);

  @override
  Future<Result<Household>> get() async {
    await Future<void>.delayed(latency);
    return Ok(_household);
  }

  @override
  Future<Result<Household>> save(Household household) async {
    await Future<void>.delayed(latency);
    if (!household.isValid) {
      return const Err(ValidationFailure('Informe um CPF válido.'));
    }
    _household = household;
    return Ok(household);
  }
}
