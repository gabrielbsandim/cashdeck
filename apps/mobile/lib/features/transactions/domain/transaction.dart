import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:equatable/equatable.dart';

enum TransactionKind { income, expense, transfer }

/// Who chose the category: a learned rule, the model or the user.
enum CategorySource { rule, ai, user }

final class Transaction extends Equatable {
  const new({
    required this.id,
    required this.accountId,
    required this.owner,
    required this.amount,
    required this.bookedOn,
    required this.description,
    required this.kind,
    this.categoryId,
    this.transferId,
    this.invoiceId,
    this.note,
    this.categorizedBy,
    this.categoryConfidence,
    this.merchant,
    this.installment,
  });

  final String id;
  final String accountId;
  final EntityKind owner;
  final Money amount;
  final CalendarDate bookedOn;
  final String description;
  final TransactionKind kind;
  final String? categoryId;
  final String? transferId;
  final String? invoiceId;
  final String? note;
  final CategorySource? categorizedBy;

  /// From 0 to 1, set when the model chose the category.
  final double? categoryConfidence;

  /// The store as the bank names it, cleaner than [description].
  final String? merchant;
  final TransactionInstallment? installment;

  String get displayName => merchant ?? description;

  bool get isUncategorized => categoryId == null;

  /// A transfer between the entities opens the transfer it belongs to.
  bool get opensTransfer =>
      kind == TransactionKind.transfer && transferId != null;

  @override
  List<Object?> get props => [
    id,
    accountId,
    owner,
    amount,
    bookedOn,
    description,
    kind,
    categoryId,
    transferId,
    invoiceId,
    note,
    categorizedBy,
    categoryConfidence,
    merchant,
    installment,
  ];
}

/// One charge of a card purchase split in [count] parts.
final class TransactionInstallment extends Equatable {
  const new({required this.number, required this.count, this.purchaseOn});

  final int number;
  final int count;
  final CalendarDate? purchaseOn;

  String get label => '$number/$count';

  @override
  List<Object?> get props => [number, count, purchaseOn];
}

final class Category extends Equatable {
  const new({
    required this.id,
    required this.name,
    this.key,
    this.icon,
    this.parentId,
  });

  final String id;

  /// A built-in category's stable key, which the app translates.
  final String? key;
  final String name;
  final String? icon;
  final String? parentId;

  @override
  List<Object?> get props => [id, key, name, icon, parentId];
}

enum AccountType { checking, savings, creditCard, investment, wallet }

/// The bank's logo and brand colour, from the Open Finance connector.
final class AccountLogo extends Equatable {
  const new({required this.imageUrl, this.color});

  final String imageUrl;

  /// `#RRGGBB`, when the connector has one.
  final String? color;

  @override
  List<Object?> get props => [imageUrl, color];
}

/// A card's limit and bill dates.
final class CreditLine extends Equatable {
  const new({
    required this.limit,
    required this.available,
    this.usedPercent,
    this.closesOn,
    this.dueOn,
    this.brand,
  });

  final Money limit;
  final Money available;
  final int? usedPercent;
  final CalendarDate? closesOn;
  final CalendarDate? dueOn;
  final String? brand;

  Money get used => limit - available;

  @override
  List<Object?> get props => [
    limit,
    available,
    usedPercent,
    closesOn,
    dueOn,
    brand,
  ];
}

/// How an Open Finance account last synced.
enum SyncState { updated, updating, needsAction, outdated }

final class AccountSync extends Equatable {
  const new({required this.state, this.lastSyncAt});

  final SyncState state;
  final DateTime? lastSyncAt;

  @override
  List<Object?> get props => [state, lastSyncAt];
}

/// An account a transaction can be filtered by.
final class TransactionAccount extends Equatable {
  const new({
    required this.id,
    required this.name,
    required this.owner,
    required this.institution,
    this.type,
    this.balance = const Money(0),
    this.isReserve = false,
    this.numberSuffix,
    this.logo,
    this.credit,
    this.sync,
  });

  final String id;
  final String name;
  final EntityKind owner;
  final String institution;

  /// Null when the server sent a type this build does not know.
  final AccountType? type;
  final Money balance;
  final bool isReserve;

  /// The last digits of the account or card number.
  final String? numberSuffix;
  final AccountLogo? logo;
  final CreditLine? credit;

  /// Null for a manual account.
  final AccountSync? sync;

  /// Counts toward the home balance, as the server's cash account types do.
  bool get isCash =>
      !balance.isForeign &&
      switch (type) {
        AccountType.checking ||
        AccountType.savings ||
        AccountType.wallet => true,
        _ => false,
      };

  @override
  List<Object?> get props => [
    id,
    name,
    owner,
    institution,
    type,
    balance,
    isReserve,
    numberSuffix,
    logo,
    credit,
    sync,
  ];
}

/// What the list shows: the scope, the filters and the text searched.
final class TransactionQuery extends Equatable {
  const new({
    required this.scope,
    this.accountId,
    this.categoryId,
    this.uncategorized = false,
    this.search = '',
  });

  final EntityScope scope;
  final String? accountId;
  final String? categoryId;
  final bool uncategorized;
  final String search;

  /// The entity the server filters by; null when both are shown.
  EntityKind? get entity => switch (scope) {
    EntityScope.personal => EntityKind.personal,
    EntityScope.company => EntityKind.company,
    EntityScope.consolidated => null,
  };

  bool get filtered =>
      accountId != null || categoryId != null || uncategorized || search != '';

  bool matches(Transaction transaction) {
    final term = search.trim().toLowerCase();
    final text = '${transaction.description} ${transaction.note ?? ''}'
        .toLowerCase();
    return scope.includes(transaction.owner) &&
        (accountId == null || transaction.accountId == accountId) &&
        (categoryId == null || transaction.categoryId == categoryId) &&
        (!uncategorized || transaction.isUncategorized) &&
        (term.isEmpty || text.contains(term));
  }

  @override
  List<Object?> get props => [
    scope,
    accountId,
    categoryId,
    uncategorized,
    search,
  ];
}

final class TransactionPage extends Equatable {
  const new({required this.items, this.nextCursor});

  final List<Transaction> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;

  @override
  List<Object?> get props => [items, nextCursor];
}

/// A change to one transaction. A null field stays as it is; an empty
/// [note] clears it.
final class TransactionUpdate extends Equatable {
  const new category(String this.categoryId, {required this.applyToSimilar})
    : note = null;

  const new note(String this.note) : categoryId = null, applyToSimilar = false;

  final String? categoryId;
  final String? note;
  final bool applyToSimilar;

  @override
  List<Object?> get props => [categoryId, note, applyToSimilar];
}

final class TransactionUpdateResult extends Equatable {
  const new({required this.transaction, required this.similarUpdated});

  final Transaction transaction;

  /// How many other transactions took the same category.
  final int similarUpdated;

  @override
  List<Object?> get props => [transaction, similarUpdated];
}

/// The transactions of one calendar day, newest day first.
final class TransactionDay extends Equatable {
  const new(this.day, this.items);

  final CalendarDate day;
  final List<Transaction> items;

  @override
  List<Object?> get props => [day, items];
}

List<TransactionDay> groupByDay(List<Transaction> transactions) {
  final days = <CalendarDate, List<Transaction>>{};
  for (final transaction in transactions) {
    days.putIfAbsent(transaction.bookedOn, () => []).add(transaction);
  }
  final ordered = days.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final day in ordered) TransactionDay(day, days[day]!)];
}

abstract interface class TransactionsRepository {
  Future<Result<TransactionPage>> list(
    TransactionQuery query, {
    String? cursor,
  });

  Future<Result<TransactionUpdateResult>> update(
    String id,
    TransactionUpdate update,
  );

  Future<Result<List<TransactionAccount>>> accounts();
}

abstract interface class CategoriesRepository {
  Future<Result<List<Category>>> list();
}
