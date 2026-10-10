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
