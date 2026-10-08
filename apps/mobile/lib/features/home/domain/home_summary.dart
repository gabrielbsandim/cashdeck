import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:equatable/equatable.dart';

/// How many accounts feed a balance and when they last synced.
final class SyncInfo extends Equatable {
  const new({required this.accountCount, required this.syncedAt});

  final int accountCount;
  final DateTime syncedAt;

  @override
  List<Object?> get props => [accountCount, syncedAt];
}

/// The money set aside to pay bills, and how far it reaches.
final class ReserveSummary extends Equatable {
  const new({
    required this.institution,
    required this.product,
    required this.balance,
    required this.monthYield,
    required this.coverDays,
    required this.cdiPercent,
  });

  final String institution;
  final String product;
  final Money balance;
  final Money monthYield;
  final int coverDays;
  final int cdiPercent;

  @override
  List<Object?> get props => [
    institution,
    product,
    balance,
    monthYield,
    coverDays,
    cdiPercent,
  ];
}

enum BudgetCategory { transport, groceries, restaurants }

final class BudgetSummary extends Equatable {
  const new({required this.category, required this.spent, required this.limit});

  final BudgetCategory category;
  final Money spent;
  final Money limit;

  bool get exceeded => spent.cents > limit.cents;

  @override
  List<Object?> get props => [category, spent, limit];
}

/// One balance a day from [from], lowest point and safety floor included.
final class CashForecast extends Equatable {
  const new({required this.from, required this.balances, required this.floor});

  /// Spends [dailySpend] every day and applies each event on its day offset.
  factory project({
    required CalendarDate from,
    required Money start,
    required Money dailySpend,
    required Map<int, Money> events,
    required int days,
    required Money floor,
  }) {
    final balances = [start];
    for (var day = 1; day <= days; day++) {
      final event = events[day] ?? const Money(0);
      balances.add(balances.last + Money(-dailySpend.cents) + event);
    }
    return CashForecast(from: from, balances: balances, floor: floor);
  }

  final CalendarDate from;
  final List<Money> balances;
  final Money floor;

  int get lowestDay {
    var lowest = 0;
    for (var day = 1; day < balances.length; day++) {
      if (balances[day].cents < balances[lowest].cents) lowest = day;
    }
    return lowest;
  }

  Money get lowest => balances[lowestDay];

  CalendarDate get lowestDate => from.addDays(lowestDay);

  Money get last => balances.last;

  CalendarDate get lastDate => from.addDays(balances.length - 1);

  @override
  List<Object?> get props => [from, balances, floor];
}

/// Something Início surfaces that the user did not ask for.
sealed class HomeAlert extends Equatable {
  const new({required this.at});

  final DateTime at;
}

/// A bill the ladder moved to step 3; [reason] is the server's wording.
final class AssistedPaymentAlert extends HomeAlert {
  const new({
    required this.billId,
    required this.payee,
    required this.reason,
    required super.at,
  });

  final String billId;
  final String payee;
  final String reason;

  @override
  List<Object?> get props => [billId, payee, reason, at];
}

final class BudgetExceededAlert extends HomeAlert {
  const new({required this.budget, required super.at});

  final BudgetSummary budget;

  @override
  List<Object?> get props => [budget, at];
}

sealed class HomeSummary extends Equatable {
  const new();
}

final class PersonalSummary extends HomeSummary {
  const new({
    required this.balance,
    required this.sync,
    required this.reserve,
    required this.forecast,
    required this.budgets,
    required this.alerts,
  });

  final Money balance;
  final SyncInfo sync;
  final ReserveSummary reserve;
  final CashForecast forecast;
  final List<BudgetSummary> budgets;
  final List<HomeAlert> alerts;

  @override
  List<Object?> get props => [
    balance,
    sync,
    reserve,
    forecast,
    budgets,
    alerts,
  ];
}

/// An invoice the issuer prepared and waits for approval.
final class InvoiceDraft extends Equatable {
  const new({
    required this.id,
    required this.customer,
    required this.amount,
    required this.recurring,
    required this.issueOn,
  });

  final String id;
  final String customer;
  final Money amount;
  final bool recurring;
  final CalendarDate issueOn;

  @override
  List<Object?> get props => [id, customer, amount, recurring, issueOn];
}

/// Money the company received with no invoice issued for it yet.
final class UnbilledReceipt extends Equatable {
  const new({
    required this.id,
    required this.payer,
    required this.amount,
    required this.receivedOn,
  });

  final String id;
  final String payer;
  final Money amount;
  final CalendarDate receivedOn;

  @override
  List<Object?> get props => [id, payer, amount, receivedOn];
}

final class CompanySummary extends HomeSummary {
  const new({
    required this.cash,
    required this.sync,
    required this.billed,
    required this.invoiceCount,
    required this.dasEstimate,
    required this.dasDue,
    required this.drafts,
    required this.unbilled,
  });

  final Money cash;
  final SyncInfo sync;
  final Money billed;
  final int invoiceCount;
  final Money dasEstimate;
  final CalendarDate dasDue;
  final List<InvoiceDraft> drafts;
  final List<UnbilledReceipt> unbilled;

  @override
  List<Object?> get props => [
    cash,
    sync,
    billed,
    invoiceCount,
    dasEstimate,
    dasDue,
    drafts,
    unbilled,
  ];
}

enum InternalTransferKind { profitDistribution, proLabore }

/// Money moving between the person and the company: it leaves one entity
/// and enters the other, so the consolidated view never counts it twice.
final class InternalTransfer extends Equatable {
  const new({
    required this.id,
    required this.kind,
    required this.amount,
    required this.on,
  });

  final String id;
  final InternalTransferKind kind;
  final Money amount;
  final CalendarDate on;

  @override
  List<Object?> get props => [id, kind, amount, on];
}

final class ConsolidatedSummary extends HomeSummary {
  const new({
    required this.personal,
    required this.company,
    required this.externalIn,
    required this.externalOut,
    required this.transfers,
  });

  final Money personal;
  final Money company;
  final Money externalIn;

  /// Negative, as it leaves both entities.
  final Money externalOut;
  final List<InternalTransfer> transfers;

  Money get total => personal + company;

  Money get internal =>
      transfers.fold(const Money(0), (sum, transfer) => sum + transfer.amount);

  Money get net => externalIn + externalOut;

  /// The personal share of [total], from 0 to 1.
  double get personalShare =>
      total.cents == 0 ? 0 : personal.cents / total.cents;

  @override
  List<Object?> get props => [
    personal,
    company,
    externalIn,
    externalOut,
    transfers,
  ];
}
