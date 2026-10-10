import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:equatable/equatable.dart';

enum TimelineBillState { past, closed, open, forecast }

/// Whether a closed bill was paid, as far as the card's credits show it.
enum BillPayment { paid, due, unconfirmed }

/// An installment a forecast bill will carry that is not posted yet.
final class PlannedInstallment extends Equatable {
  const new({
    required this.key,
    required this.name,
    required this.number,
    required this.count,
    required this.amount,
    this.categoryId,
  });

  final String key;
  final String name;
  final String? categoryId;
  final int number;
  final int count;
  final Money amount;

  String get label => '$number/$count';

  @override
  List<Object?> get props => [key, name, categoryId, number, count, amount];
}

final class TimelineBill extends Equatable {
  const new({
    required this.dueOn,
    required this.total,
    required this.state,
    required this.range,
    this.closesOn,
    this.minimum,
    this.payment,
    this.installments = const [],
  });

  /// Null when the issuer left the closing day out.
  final CalendarDate? closesOn;
  final CalendarDate dueOn;
  final Money total;
  final Money? minimum;
  final TimelineBillState state;

  /// Null on the open and forecast bills.
  final BillPayment? payment;

  /// The booking days whose charges this bill holds.
  final DateSpan range;
  final List<PlannedInstallment> installments;

  bool get isForecast => state == TimelineBillState.forecast;

  @override
  List<Object?> get props => [
    closesOn,
    dueOn,
    total,
    minimum,
    state,
    payment,
    range,
    installments,
  ];
}

/// One card's bills, oldest first, to move through month by month.
final class CardTimeline extends Equatable {
  const new({
    required this.accountId,
    required this.name,
    required this.owner,
    required this.bills,
    this.suffix,
    this.current,
  });

  final String accountId;
  final String name;
  final String? suffix;
  final EntityKind owner;
  final List<TimelineBill> bills;

  /// The open bill, where the timeline starts; null without bills.
  final int? current;

  /// [current] kept inside [bills], so a stale index never breaks a page.
  int get start =>
      bills.isEmpty ? 0 : (current ?? 0).clamp(0, bills.length - 1);

  @override
  List<Object?> get props => [accountId, name, suffix, owner, bills, current];
}
