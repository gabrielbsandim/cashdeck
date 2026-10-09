import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:equatable/equatable.dart';

enum InsightPeriod { week, month, sixMonths, year }

final class DateSpan extends Equatable {
  const new(this.from, this.to);

  final CalendarDate from;
  final CalendarDate to;

  @override
  List<Object?> get props => [from, to];
}

final class SpendPoint extends Equatable {
  const new(this.day, this.cumulative);

  final CalendarDate day;
  final Money cumulative;

  @override
  List<Object?> get props => [day, cumulative];
}

final class MerchantSpend extends Equatable {
  const new({required this.name, required this.total, required this.count});

  final String name;
  final Money total;
  final int count;

  @override
  List<Object?> get props => [name, total, count];
}

/// One slice of the spending; a null [categoryId] is the uncategorized rest.
final class CategoryShare extends Equatable {
  const new({
    required this.total,
    required this.sharePercent,
    this.categoryId,
    this.key,
    this.name,
    this.icon,
    this.changePercent,
  });

  final String? categoryId;
  final String? key;
  final String? name;
  final String? icon;
  final Money total;
  final int sharePercent;

  /// Against the previous period; null when there was nothing to compare.
  final int? changePercent;

  @override
  List<Object?> get props => [
    categoryId,
    key,
    name,
    icon,
    total,
    sharePercent,
    changePercent,
  ];
}

final class CashFlow extends Equatable {
  const new({
    required this.income,
    required this.expenses,
    required this.result,
  });

  final Money income;
  final Money expenses;
  final Money result;

  @override
  List<Object?> get props => [income, expenses, result];
}

final class CardsSummary extends Equatable {
  const new({
    required this.bill,
    required this.count,
    this.dueOn,
    this.limit,
    this.used,
    this.usedPercent,
  });

  final Money bill;
  final CalendarDate? dueOn;
  final int count;
  final Money? limit;
  final Money? used;
  final int? usedPercent;

  @override
  List<Object?> get props => [bill, dueOn, count, limit, used, usedPercent];
}

final class BillsDue extends Equatable {
  const new({required this.days, required this.total, required this.count});

  final int days;
  final Money total;
  final int count;

  @override
  List<Object?> get props => [days, total, count];
}

final class SpendSummary extends Equatable {
  const new({
    required this.total,
    required this.previous,
    required this.series,
    required this.previousSeries,
    required this.topMerchants,
    this.changePercent,
  });

  final Money total;

  /// The previous period up to the same day.
  final Money previous;
  final int? changePercent;
  final List<SpendPoint> series;
  final List<SpendPoint> previousSeries;
  final List<MerchantSpend> topMerchants;

  @override
  List<Object?> get props => [
    total,
    previous,
    changePercent,
    series,
    previousSeries,
    topMerchants,
  ];
}

final class InsightsOverview extends Equatable {
  const new({
    required this.period,
    required this.range,
    required this.previousRange,
    required this.spend,
    required this.categoryTotal,
    required this.categories,
    required this.flow,
    required this.billsDue,
    this.cards,
  });

  final InsightPeriod period;
  final DateSpan range;
  final DateSpan previousRange;
  final SpendSummary spend;
  final Money categoryTotal;
  final List<CategoryShare> categories;
  final CashFlow flow;
  final CardsSummary? cards;
  final BillsDue billsDue;

  @override
  List<Object?> get props => [
    period,
    range,
    previousRange,
    spend,
    categoryTotal,
    categories,
    flow,
    cards,
    billsDue,
  ];
}

final class MonthResult extends Equatable {
  const new({
    required this.month,
    required this.income,
    required this.expenses,
    required this.result,
  });

  final YearMonth month;
  final Money income;
  final Money expenses;
  final Money result;

  @override
  List<Object?> get props => [month, income, expenses, result];
}

final class SavingsRate extends Equatable {
  const new({required this.trend, this.percent, this.averagePercent});

  /// Null without income in the month.
  final int? percent;

  /// Of the three months before.
  final int? averagePercent;
  final List<(YearMonth, int?)> trend;

  @override
  List<Object?> get props => [percent, averagePercent, trend];
}

final class CategoryChange extends Equatable {
  const new({
    required this.categoryId,
    required this.name,
    required this.total,
    required this.average,
    required this.delta,
    this.key,
    this.icon,
  });

  final String categoryId;
  final String? key;
  final String name;
  final String? icon;
  final Money total;
  final Money average;
  final Money delta;

  @override
  List<Object?> get props => [
    categoryId,
    key,
    name,
    icon,
    total,
    average,
    delta,
  ];
}

final class FixedCost extends Equatable {
  const new({
    required this.subscriptions,
    required this.installments,
    required this.bills,
    required this.total,
    required this.income,
    this.sharePercent,
  });

  final Money subscriptions;
  final Money installments;
  final Money bills;
  final Money total;
  final Money income;
  final int? sharePercent;

  @override
  List<Object?> get props => [
    subscriptions,
    installments,
    bills,
    total,
    income,
    sharePercent,
  ];
}

final class LeftThisMonth extends Equatable {
  const new({
    required this.balance,
    required this.billsDue,
    required this.cardBill,
    required this.left,
  });

  final Money balance;
  final Money billsDue;
  final Money cardBill;
  final Money left;

  @override
  List<Object?> get props => [balance, billsDue, cardBill, left];
}

final class CompanyToPersonal extends Equatable {
  const new({required this.transfers, required this.taxes});

  final Money transfers;
  final Money taxes;

  @override
  List<Object?> get props => [transfers, taxes];
}

enum InsightTone { positive, negative, neutral }

/// A sentence the server picked for the month; the app words it.
sealed class Insight extends Equatable {
  const new(this.tone);

  final InsightTone tone;
}

final class CategoryAboveAverage extends Insight {
  const new({
    required InsightTone tone,
    required this.categoryId,
    required this.name,
    required this.percent,
    required this.amount,
  }) : super(tone);

  final String categoryId;
  final String name;
  final int percent;
  final Money amount;

  @override
  List<Object?> get props => [tone, categoryId, name, percent, amount];
}

final class InstallmentsCommitted extends Insight {
  const new({
    required InsightTone tone,
    required this.month,
    required this.amount,
  }) : super(tone);

  final YearMonth month;
  final Money amount;

  @override
  List<Object?> get props => [tone, month, amount];
}

final class SavingsRateChanged extends Insight {
  const new({
    required InsightTone tone,
    required this.percent,
    required this.averagePercent,
  }) : super(tone);

  final int percent;
  final int averagePercent;

  @override
  List<Object?> get props => [tone, percent, averagePercent];
}

final class SubscriptionPriceUp extends Insight {
  const new({
    required InsightTone tone,
    required this.name,
    required this.amount,
    required this.previousAmount,
  }) : super(tone);

  final String name;
  final Money amount;
  final Money previousAmount;

  @override
  List<Object?> get props => [tone, name, amount, previousAmount];
}

final class MonthlyInsights extends Equatable {
  const new({
    required this.month,
    required this.months,
    required this.savings,
    required this.rose,
    required this.fell,
    required this.fixedCost,
    required this.insights,
    this.leftThisMonth,
    this.companyToPersonal,
  });

  final YearMonth month;
  final List<MonthResult> months;
  final SavingsRate savings;
  final List<CategoryChange> rose;
  final List<CategoryChange> fell;
  final FixedCost fixedCost;

  /// Only for the current month.
  final LeftThisMonth? leftThisMonth;

  /// Only when the company is in scope.
  final CompanyToPersonal? companyToPersonal;
  final List<Insight> insights;

  @override
  List<Object?> get props => [
    month,
    months,
    savings,
    rose,
    fell,
    fixedCost,
    leftThisMonth,
    companyToPersonal,
    insights,
  ];
}

final class InstallmentPlan extends Equatable {
  const new({
    required this.key,
    required this.accountId,
    required this.card,
    required this.owner,
    required this.name,
    required this.number,
    required this.count,
    required this.amount,
    required this.paid,
    required this.remaining,
    required this.total,
    required this.lastBilledOn,
    required this.finalMonth,
    this.cardSuffix,
    this.categoryId,
    this.purchaseOn,
  });

  final String key;
  final String accountId;
  final String card;
  final String? cardSuffix;
  final EntityKind owner;
  final String name;
  final String? categoryId;

  /// The latest installment billed, 1 to [count].
  final int number;
  final int count;
  final Money amount;
  final Money paid;
  final Money remaining;
  final Money total;
  final CalendarDate? purchaseOn;
  final CalendarDate lastBilledOn;
  final YearMonth finalMonth;

  int get left => count - number;

  @override
  List<Object?> get props => [
    key,
    accountId,
    card,
    cardSuffix,
    owner,
    name,
    categoryId,
    number,
    count,
    amount,
    paid,
    remaining,
    total,
    purchaseOn,
    lastBilledOn,
    finalMonth,
  ];
}

final class Installments extends Equatable {
  const new({required this.months, required this.plans});

  /// What the plans still charge, month by month from next month.
  final List<(YearMonth, Money)> months;
  final List<InstallmentPlan> plans;

  @override
  List<Object?> get props => [months, plans];
}

enum SubscriptionMonthStatus { paid, upcoming, late }

final class Subscription extends Equatable {
  const new({
    required this.key,
    required this.owner,
    required this.name,
    required this.amount,
    required this.priceChanged,
    required this.dayOfMonth,
    required this.thisMonth,
    required this.transactionIds,
    this.id,
    this.previousAmount,
    this.lastChargeOn,
    this.accountId,
    this.categoryId,
  });

  /// Null for a suggestion the user has not decided on.
  final String? id;
  final String key;
  final EntityKind owner;
  final String name;
  final Money amount;
  final Money? previousAmount;
  final bool priceChanged;
  final int dayOfMonth;
  final CalendarDate? lastChargeOn;
  final SubscriptionMonthStatus thisMonth;
  final String? accountId;
  final String? categoryId;
  final List<String> transactionIds;

  bool get isSuggestion => id == null;

  @override
  List<Object?> get props => [
    id,
    key,
    owner,
    name,
    amount,
    previousAmount,
    priceChanged,
    dayOfMonth,
    lastChargeOn,
    thisMonth,
    accountId,
    categoryId,
    transactionIds,
  ];
}

final class Subscriptions extends Equatable {
  const new({
    required this.monthly,
    required this.yearly,
    required this.previousMonth,
    required this.items,
    required this.suggestions,
    this.changePercent,
  });

  final Money monthly;
  final Money yearly;
  final Money previousMonth;
  final int? changePercent;
  final List<Subscription> items;
  final List<Subscription> suggestions;

  @override
  List<Object?> get props => [
    monthly,
    yearly,
    previousMonth,
    changePercent,
    items,
    suggestions,
  ];
}

enum CardBillState { open, closed, past }

final class CardBill extends Equatable {
  const new({
    required this.dueOn,
    required this.total,
    required this.state,
    required this.range,
    this.closesOn,
    this.minimum,
  });

  /// Null when the issuer left the closing day out.
  final CalendarDate? closesOn;
  final CalendarDate dueOn;
  final Money total;
  final Money? minimum;
  final CardBillState state;

  /// The booking days whose charges this bill holds.
  final DateSpan range;

  @override
  List<Object?> get props => [closesOn, dueOn, total, minimum, state, range];
}

final class CardBills extends Equatable {
  const new({
    required this.accountId,
    required this.name,
    required this.owner,
    required this.bills,
    this.suffix,
  });

  final String accountId;
  final String name;
  final String? suffix;
  final EntityKind owner;

  /// Newest first.
  final List<CardBill> bills;

  /// The bill to look at first: one closed and still to pay, else the open
  /// one, else the latest.
  int? get focus {
    if (bills.isEmpty) return null;
    final closed = bills.indexWhere(
      (bill) => bill.state == CardBillState.closed,
    );
    return closed < 0 ? 0 : closed;
  }

  List<CardBill> _closed(int count) => bills
      .where((bill) => bill.state != CardBillState.open)
      .take(count)
      .toList();

  /// Mean of up to [count] bills that already closed; null without any.
  Money? average([int count = 6]) {
    final closed = _closed(count);
    if (closed.isEmpty) return null;
    final sum = closed.fold(0, (total, bill) => total + bill.total.cents);
    return Money((sum / closed.length).round());
  }

  /// How many bills [average] covers.
  int averaged([int count = 6]) => _closed(count).length;

  @override
  List<Object?> get props => [accountId, name, suffix, owner, bills];
}
