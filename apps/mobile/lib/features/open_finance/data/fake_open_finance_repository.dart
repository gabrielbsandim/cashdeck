import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/open_finance/domain/item_lookup.dart';

/// One fictional item that resolves, one already linked to the company and
/// nothing else.
final class FakeOpenFinanceRepository implements OpenFinanceRepository {
  new({this.latency = const Duration(milliseconds: 400)});

  final Duration latency;
  static const foundId = 'a3f9c2e1-58b4-4d7e-9a61-0c2b7e4f1d93';
  static const connectedId = 'b7e4f1d9-3a3f-4c2e-958b-4d7e9a610c2b';
  final Map<String, EntityKind> _connected = {connectedId: EntityKind.company};

  @override
  Future<Result<ItemLookup>> lookup(String itemId) async {
    await Future<void>.delayed(latency);
    final id = itemId.trim().toLowerCase();
    final owner = _connected[id];
    if (owner != null) return Ok(ItemAlreadyConnected(owner));
    if (id != foundId) return const Ok(ItemNotFound());
    return const Ok(
      ItemFound(
        institution: 'Banco Aurora',
        consentUntil: CalendarDate(2027, 4, 3),
        accounts: [
          FoundAccount(
            id: 'acc-checking',
            name: 'Conta corrente ••4410',
            balance: Money(541_218),
          ),
          FoundAccount(
            id: 'acc-reserve',
            name: 'Reserva · CDB',
            balance: Money(620_000),
          ),
          FoundAccount(
            id: 'acc-card',
            name: 'Cartão Aurora Gold',
            balance: Money(-183_044),
          ),
        ],
      ),
    );
  }

  @override
  Future<Result<int>> import(
    String itemId,
    Set<String> accountIds,
    EntityKind owner,
  ) async {
    await Future<void>.delayed(latency);
    if (accountIds.isEmpty) return const Err(ValidationFailure('accounts'));
    _connected[itemId.trim().toLowerCase()] = owner;
    return Ok(accountIds.length);
  }

  @override
  Future<Result<int>> sync(String connectionId, {required int days}) async {
    await Future<void>.delayed(latency);
    return Ok(days ~/ 3);
  }
}
