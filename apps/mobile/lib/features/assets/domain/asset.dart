import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:equatable/equatable.dart';

enum AssetKind { property, vehicle, other }

enum VehicleType { car, motorcycle, truck }

/// A model year in the FIPE table, which prices the vehicle every month.
final class FipeVehicle extends Equatable {
  const new({required this.type, required this.code, required this.modelYear});

  final VehicleType type;
  final String code;
  final int modelYear;

  @override
  List<Object?> get props => [type, code, modelYear];
}

/// A brand, model year or model in the FIPE table. A model carries the
/// table's year code, which also names its fuel.
final class VehicleOption extends Equatable {
  const new({required this.code, required this.name, this.year});

  final String code;
  final String name;
  final String? year;

  @override
  List<Object?> get props => [code, name, year];
}

/// A model found in the table, with its FIPE code and price this month.
final class CatalogVehicle extends Equatable {
  const new({required this.fipe, required this.model, required this.price});

  final FipeVehicle fipe;
  final String model;
  final Money price;

  @override
  List<Object?> get props => [fipe, model, price];
}

/// The loan that financed the asset and what it still owes.
final class AssetLoan extends Equatable {
  const new({required this.id, required this.name, required this.balance});

  final String id;
  final String name;
  final Money balance;

  @override
  List<Object?> get props => [id, name, balance];
}

/// One line of a bill, like the gas the tenant used.
final class BillLine extends Equatable {
  const new({required this.description, required this.amount});

  final String description;
  final Money amount;

  @override
  List<Object?> get props => [description, amount];
}

/// The latest bill of the rented building: what to ask the tenant for and
/// what the month leaves once the loan and the owner's share are paid.
final class RentCharge extends Equatable {
  const new({
    required this.billId,
    required this.dueDate,
    required this.billTotal,
    required this.passedOn,
    required this.total,
    required this.ownerCost,
    required this.result,
    this.attachmentId,
    this.installment,
  });

  final String billId;
  final CalendarDate dueDate;
  final Money billTotal;
  final List<BillLine> passedOn;
  final Money total;
  final Money ownerCost;
  final Money result;

  /// The bill's PDF, sent to the tenant with the charge.
  final String? attachmentId;
  final Money? installment;

  @override
  List<Object?> get props => [
    billId,
    dueDate,
    billTotal,
    passedOn,
    total,
    ownerCost,
    result,
    attachmentId,
    installment,
  ];
}

/// The tenant pays [rent] plus the lines of the building's bill, from
/// [billFrom], whose description holds one of [passThrough].
final class AssetRental extends Equatable {
  const new({
    required this.rent,
    required this.passThrough,
    required this.billFrom,
    this.charge,
  });

  final Money rent;
  final List<String> passThrough;
  final String billFrom;
  final RentCharge? charge;

  @override
  List<Object?> get props => [rent, passThrough, billFrom, charge];
}

/// What the person fills in to rent a good out. Pass-through words are typed
/// separated by commas.
final class RentalDraft extends Equatable {
  const new({
    required this.rent,
    required this.billFrom,
    this.passThrough = '',
  });

  final Money rent;
  final String billFrom;
  final String passThrough;

  List<String> get words => [
    for (final word in passThrough.split(','))
      if (word.trim().isNotEmpty) word.trim(),
  ];

  /// Whether it says the same as [rental].
  bool matches(AssetRental? rental) =>
      rental != null &&
      rental.rent == rent &&
      rental.billFrom == billFrom.trim() &&
      _sameWords(rental.passThrough, words);

  @override
  List<Object?> get props => [rent, billFrom, passThrough];
}

bool _sameWords(List<String> a, List<String> b) =>
    a.length == b.length && a.indexed.every((word) => word.$2 == b[word.$1]);

/// A property, vehicle or other good, at its latest value.
final class Asset extends Equatable {
  const new({
    required this.id,
    required this.entity,
    required this.kind,
    required this.name,
    required this.acquiredOn,
    required this.value,
    required this.valuedOn,
    required this.change,
    required this.equity,
    this.changePercent,
    this.soldOn,
    this.fipe,
    this.loan,
    this.rental,
  });

  final String id;
  final EntityKind entity;
  final AssetKind kind;
  final String name;
  final CalendarDate acquiredOn;
  final CalendarDate? soldOn;
  final Money value;
  final CalendarDate valuedOn;

  /// Since the first value known; the percent is null when that was zero.
  final Money change;
  final double? changePercent;
  final FipeVehicle? fipe;
  final AssetLoan? loan;

  /// The value less what the loan still owes.
  final Money equity;
  final AssetRental? rental;

  bool get sold => soldOn != null;

  @override
  List<Object?> get props => [
    id,
    entity,
    kind,
    name,
    acquiredOn,
    soldOn,
    value,
    valuedOn,
    change,
    changePercent,
    fipe,
    loan,
    equity,
    rental,
  ];
}

final class AssetsSummary extends Equatable {
  const new({
    required this.items,
    required this.value,
    required this.loanDebt,
    required this.equity,
  });

  final List<Asset> items;
  final Money value;
  final Money loanDebt;
  final Money equity;

  bool get isEmpty => items.isEmpty;

  @override
  List<Object?> get props => [items, value, loanDebt, equity];
}

/// What the person fills in to add an asset. A vehicle picked from the FIPE
/// table needs neither a name nor a value: the table gives both.
final class AssetDraft extends Equatable {
  const new({
    required this.kind,
    required this.acquiredOn,
    this.name = '',
    this.value = const Money(0),
    this.byFipe = false,
    this.fipe,
    this.loanId,
    this.rental,
  });

  final AssetKind kind;
  final String name;
  final CalendarDate acquiredOn;
  final Money value;
  final bool byFipe;
  final FipeVehicle? fipe;
  final String? loanId;

  /// Null when it is not rented out.
  final RentalDraft? rental;

  bool get _priced => kind == AssetKind.vehicle && byFipe;

  AssetProblem? problemOn(CalendarDate today) {
    if (acquiredOn.compareTo(today) > 0) return AssetProblem.futureDate;
    if (_priced) return fipe == null ? AssetProblem.vehicle : null;
    if (name.trim().isEmpty) return AssetProblem.name;
    if (value.cents <= 0) return AssetProblem.value;
    return switch (rental) {
      RentalDraft(:final rent) when rent.cents <= 0 => AssetProblem.rent,
      RentalDraft(:final billFrom) when billFrom.trim().isEmpty =>
        AssetProblem.billFrom,
      _ => null,
    };
  }

  @override
  List<Object?> get props => [
    kind,
    name,
    acquiredOn,
    value,
    byFipe,
    fipe,
    loanId,
    rental,
  ];
}

enum AssetProblem { name, value, vehicle, futureDate, rent, billFrom }

abstract interface class AssetsRepository {
  /// Properties first, then vehicles and other goods.
  Future<Result<AssetsSummary>> list();

  Future<Result<Asset>> create(AssetDraft draft);

  /// Sends only what the draft changes from [before].
  Future<Result<Asset>> edit(Asset before, AssetDraft draft);

  /// A new value holding from today.
  Future<Result<Asset>> revalue(String id, Money value);

  Future<Result<Asset>> markSold(String id, CalendarDate on);

  Future<Result<void>> delete(String id);

  /// The PDF of the building's bill behind [charge].
  Future<Result<LocalFile>> rentBill(RentCharge charge);

  /// The FIPE table, walked brand, model year, model.
  Future<Result<List<VehicleOption>>> brands(VehicleType type);

  Future<Result<List<VehicleOption>>> years(VehicleType type, String brand);

  Future<Result<List<VehicleOption>>> models(
    VehicleType type,
    String brand,
    int modelYear,
  );

  Future<Result<CatalogVehicle>> price(
    VehicleType type,
    String brand,
    VehicleOption model,
  );
}
