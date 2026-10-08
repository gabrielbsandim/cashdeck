import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:equatable/equatable.dart';

/// An aggregator item id is a UUID, checked before the server is asked.
bool isValidItemId(String value) =>
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
        .hasMatch(value.trim().toLowerCase());

final class FoundAccount extends Equatable {
  const new({required this.id, required this.name, required this.balance});

  final String id;
  final String name;

  /// Negative for a card, which carries what is owed.
  final Money balance;

  @override
  List<Object?> get props => [id, name, balance];
}

sealed class ItemLookup extends Equatable {
  const new();
}

final class ItemFound extends ItemLookup {
  const new({
    required this.institution,
    required this.consentUntil,
    required this.accounts,
  });

  final String institution;
  final CalendarDate consentUntil;
  final List<FoundAccount> accounts;

  @override
  List<Object?> get props => [institution, consentUntil, accounts];
}

final class ItemNotFound extends ItemLookup {
  const new();

  @override
  List<Object?> get props => [];
}

final class ItemAlreadyConnected extends ItemLookup {
  const new(this.owner);

  final EntityKind owner;

  @override
  List<Object?> get props => [owner];
}

abstract interface class OpenFinanceRepository {
  Future<Result<ItemLookup>> lookup(String itemId);

  /// Imports [accountIds] of the item for [owner]; returns how many.
  Future<Result<int>> import(
    String itemId,
    Set<String> accountIds,
    EntityKind owner,
  );
}
