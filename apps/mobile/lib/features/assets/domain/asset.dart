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
  });

  final AssetKind kind;
  final String name;
  final CalendarDate acquiredOn;
  final Money value;
  final bool byFipe;
  final FipeVehicle? fipe;
  final String? loanId;

  bool get _priced => kind == AssetKind.vehicle && byFipe;

  AssetProblem? problemOn(CalendarDate today) {
    if (acquiredOn.compareTo(today) > 0) return AssetProblem.futureDate;
    if (_priced) return fipe == null ? AssetProblem.vehicle : null;
    if (name.trim().isEmpty) return AssetProblem.name;
    if (value.cents <= 0) return AssetProblem.value;
    return null;
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
  ];
}

enum AssetProblem { name, value, vehicle, futureDate }

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
