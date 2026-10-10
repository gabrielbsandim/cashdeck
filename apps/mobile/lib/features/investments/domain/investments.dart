import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:equatable/equatable.dart';

enum InvestmentKind {
  fixedIncome,
  fund,
  equity,
  etf,
  pension,
  structured,
  other,
}

/// How the issuer quotes the yield: 102% of CDI, IPCA plus 6.5 a year, or a
/// fixed 12% a year.
final class InvestmentRate extends Equatable {
  const new({this.percent, this.index, this.fixedAnnual});

  final double? percent;
  final String? index;
  final double? fixedAnnual;

  @override
  List<Object?> get props => [percent, index, fixedAnnual];
}

final class InvestmentPosition extends Equatable {
  const new({
    required this.id,
    required this.owner,
    required this.institutionId,
    required this.institution,
    required this.name,
    required this.kind,
    required this.balance,
    this.logo,
    this.subtype,
    this.issuer,
    this.pending = false,
    this.invested,
    this.profit,
    this.profitPercent,
    this.quantity,
    this.rate,
    this.lastMonthRate,
    this.lastTwelveMonthsRate,
    this.dueOn,
    this.valuedOn,
  });

  final String id;
  final EntityKind owner;
  final String institutionId;
  final String institution;
  final AccountLogo? logo;
  final String name;
  final InvestmentKind kind;

  /// The provider's own label, such as CDB, LCI or STOCK.
  final String? subtype;
  final String? issuer;

  /// Bought but not settled yet.
  final bool pending;

  /// Net of taxes and fees.
  final Money balance;
  final Money? invested;
  final Money? profit;
  final double? profitPercent;
  final double? quantity;
  final InvestmentRate? rate;
  final double? lastMonthRate;
  final double? lastTwelveMonthsRate;
  final CalendarDate? dueOn;
  final CalendarDate? valuedOn;

  bool get isLoss => profit?.isNegative ?? false;

  @override
  List<Object?> get props => [
    id,
    owner,
    institutionId,
    institution,
    logo,
    name,
    kind,
    subtype,
    issuer,
    pending,
    balance,
    invested,
    profit,
    profitPercent,
    quantity,
    rate,
    lastMonthRate,
    lastTwelveMonthsRate,
    dueOn,
    valuedOn,
  ];
}

final class InstitutionHoldings extends Equatable {
  const new({
    required this.institutionId,
    required this.institution,
    required this.total,
    required this.count,
    this.logo,
  });

  final String institutionId;
  final String institution;
  final AccountLogo? logo;
  final Money total;
  final int count;

  @override
  List<Object?> get props => [institutionId, institution, logo, total, count];
}

final class KindHoldings extends Equatable {
  const new({required this.kind, required this.total, required this.count});

  final InvestmentKind kind;
  final Money total;
  final int count;

  @override
  List<Object?> get props => [kind, total, count];
}

/// Every position held, with the totals in reais by institution and kind.
final class Investments extends Equatable {
  const new({
    required this.total,
    required this.invested,
    required this.profit,
    required this.institutions,
    required this.kinds,
    required this.positions,
    this.syncedAt,
  });

  final Money total;
  final Money invested;
  final Money profit;
  final DateTime? syncedAt;
  final List<InstitutionHoldings> institutions;
  final List<KindHoldings> kinds;
  final List<InvestmentPosition> positions;

  bool get isEmpty => positions.isEmpty;

  /// The profit over what was put in, null before anything was.
  double? get profitPercent => invested.cents > 0
      ? (profit.cents * 10000 / invested.cents).round() / 100
      : null;

  @override
  List<Object?> get props => [
    total,
    invested,
    profit,
    syncedAt,
    institutions,
    kinds,
    positions,
  ];
}

/// The window a performance looks back over, ending today.
enum PerformancePeriod { week, month, year }

/// The portfolio value on one day of the window.
final class PerformancePoint extends Equatable {
  const new(this.day, this.value);

  final CalendarDate day;
  final Money value;

  @override
  List<Object?> get props => [day, value];
}

/// What one position earned over the window.
final class PositionPerformance extends Equatable {
  const new({
    required this.id,
    required this.start,
    required this.end,
    required this.yieldAmount,
    this.yieldPercent,
  });

  final String id;
  final Money start;
  final Money end;
  final Money yieldAmount;
  final double? yieldPercent;

  @override
  List<Object?> get props => [id, start, end, yieldAmount, yieldPercent];
}

/// How the portfolio did over a window: what it was worth at each end, what
/// went in and out, what it earned and the CDI over the same days.
final class InvestmentPerformance extends Equatable {
  const new({
    required this.period,
    required this.from,
    required this.to,
    required this.start,
    required this.end,
    required this.contributions,
    required this.withdrawals,
    required this.yieldAmount,
    required this.series,
    this.yieldPercent,
    this.cdiPercent,
    this.estimated = false,
    this.positions = const [],
  });

  final PerformancePeriod period;
  final CalendarDate from;
  final CalendarDate to;
  final Money start;
  final Money end;
  final Money contributions;
  final Money withdrawals;
  final Money yieldAmount;
  final double? yieldPercent;
  final double? cdiPercent;

  /// The value at the start comes from market prices, not a stored balance.
  final bool estimated;
  final List<PerformancePoint> series;

  /// Sorted by yield, best first.
  final List<PositionPerformance> positions;

  /// The yield as a share of the CDI, as Brazilian banks quote it: 112 for
  /// 112% do CDI. Null without a positive CDI or a yield to compare.
  int? get ofCdi {
    final cdi = cdiPercent;
    final percent = yieldPercent;
    if (cdi == null || percent == null || cdi <= 0) return null;
    return (percent * 100 / cdi).round();
  }

  PositionPerformance? positionOf(String id) =>
      positions.where((position) => position.id == id).firstOrNull;

  @override
  List<Object?> get props => [
    period,
    from,
    to,
    start,
    end,
    contributions,
    withdrawals,
    yieldAmount,
    yieldPercent,
    cdiPercent,
    estimated,
    series,
    positions,
  ];
}

enum InvestmentMovementKind { buy, sell, income, tax, transfer, other }

/// A buy, sale, payout or tax on one position. The amount is always positive.
final class InvestmentMovement extends Equatable {
  const new({
    required this.id,
    required this.kind,
    required this.occurredOn,
    required this.amount,
    this.quantity,
    this.unitPrice,
  });

  final String id;
  final InvestmentMovementKind kind;
  final CalendarDate occurredOn;
  final Money amount;
  final double? quantity;
  final double? unitPrice;

  @override
  List<Object?> get props => [
    id,
    kind,
    occurredOn,
    amount,
    quantity,
    unitPrice,
  ];
}

/// One position with its performance over a window and every movement,
/// newest first.
final class InvestmentDetail extends Equatable {
  const new({
    required this.position,
    required this.performance,
    required this.movements,
  });

  final InvestmentPosition position;
  final InvestmentPerformance performance;
  final List<InvestmentMovement> movements;

  @override
  List<Object?> get props => [position, performance, movements];
}
