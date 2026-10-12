import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:equatable/equatable.dart';

/// The window the net worth history covers.
enum NetWorthPeriod {
  sixMonths(6),
  twelveMonths(12);

  new(this.months);

  final int months;
}

/// What the entity has and owes: cash and investments are assets, what the
/// cards owe is the liability.
final class NetWorthComposition extends Equatable {
  const new({
    required this.cash,
    required this.investments,
    required this.cardDebt,
    required this.assets,
    required this.liabilities,
    required this.total,
  });

  final Money cash;
  final Money investments;
  final Money cardDebt;
  final Money assets;
  final Money liabilities;
  final Money total;

  bool get isEmpty => assets.cents == 0 && liabilities.cents == 0;

  @override
  List<Object?> get props => [
    cash,
    investments,
    cardDebt,
    assets,
    liabilities,
    total,
  ];
}

final class NetWorthChange extends Equatable {
  const new({required this.amount, this.percent});

  final Money amount;

  /// Null when the earlier value was zero.
  final double? percent;

  /// Positive for a rise, negative for a fall, zero for no change.
  int get direction => amount.cents.sign;

  @override
  List<Object?> get props => [amount, percent];
}

final class NetWorthPoint extends Equatable {
  const new({
    required this.on,
    required this.assets,
    required this.liabilities,
    required this.total,
  });

  final CalendarDate on;
  final Money assets;
  final Money liabilities;
  final Money total;

  @override
  List<Object?> get props => [on, assets, liabilities, total];
}

final class EntityNetWorth extends Equatable {
  const new({required this.kind, required this.current});

  final EntityKind kind;
  final NetWorthComposition current;

  @override
  List<Object?> get props => [kind, current];
}

/// Net worth today, how it moved, and one point per month end then today.
final class NetWorth extends Equatable {
  const new({
    required this.asOf,
    required this.current,
    required this.fromLastMonth,
    required this.fromYearAgo,
    this.entities = const [],
    this.series = const [],
  });

  final CalendarDate asOf;
  final NetWorthComposition current;
  final NetWorthChange fromLastMonth;
  final NetWorthChange fromYearAgo;
  final List<EntityNetWorth> entities;
  final List<NetWorthPoint> series;

  bool get isEmpty =>
      current.isEmpty && series.every((point) => point.total.cents == 0);

  @override
  List<Object?> get props => [
    asOf,
    current,
    fromLastMonth,
    fromYearAgo,
    entities,
    series,
  ];
}
