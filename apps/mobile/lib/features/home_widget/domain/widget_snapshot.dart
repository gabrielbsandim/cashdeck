import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:cashdeck/features/outlook/domain/safe_to_spend.dart';
import 'package:equatable/equatable.dart';

/// The keys the Android widget reads; `CashdeckWidgetProvider.kt` mirrors
/// them one to one.
abstract final class WidgetKeys {
  static const hidden = 'hidden';
  static const updatedTime = 'updated_time';
  static const updatedOn = 'updated_on';
  static const safeAmount = 'safe_amount';
  static const safeUntil = 'safe_until';
  static const safeShort = 'safe_short';
  static const safeTotal = 'safe_total';
  static const safeDays = 'safe_days';
  static const billPayee = 'bill_payee';
  static const billAmount = 'bill_amount';
  static const billDue = 'bill_due';
  static const billOverdue = 'bill_overdue';
  static const cardAmount = 'card_amount';
  static const cardDue = 'card_due';

  static const List<String> all = [
    hidden,
    updatedTime,
    updatedOn,
    safeAmount,
    safeUntil,
    safeShort,
    safeTotal,
    safeDays,
    billPayee,
    billAmount,
    billDue,
    billOverdue,
    cardAmount,
    cardDue,
  ];
}

/// What the home screen widget shows, already formatted, keyed by
/// [WidgetKeys]. A part whose source has not loaded is left out, so the widget
/// keeps what it showed; an empty payee or card amount means there is none.
/// The update time moves only when some part loaded.
final class WidgetSnapshot extends Equatable {
  const new(this.values);

  /// [hide] masks every amount: privacy mode, or a safe zone the widget
  /// cannot check from the home screen.
  factory from({
    required DateTime now,
    required bool hide,
    SafeToSpend? safeToSpend,
    List<Bill>? bills,
    InsightsOverview? overview,
  }) {
    final today = CalendarDate.brazilToday(now);
    final loaded = safeToSpend != null || bills != null || overview != null;
    String amount(Money money) => MoneyFormat.format(money, hide: hide);
    return WidgetSnapshot({
      WidgetKeys.hidden: hide,
      if (loaded) ...{
        WidgetKeys.updatedTime: brazilTime(now),
        WidgetKeys.updatedOn: today.iso,
      },
      if (safeToSpend != null) ..._safeToSpend(safeToSpend, amount),
      if (bills != null) ..._nextBill(nextBillOf(bills, today), today, amount),
      if (overview != null) ..._cardBill(overview.cards, amount),
    });
  }

  final Map<String, Object> values;

  @override
  List<Object?> get props => [values];
}

/// The open bill due first, overdue ones included; one the bank debits on
/// its own and that only waits for the statement is not the user's to pay.
Bill? nextBillOf(List<Bill> bills, CalendarDate today) {
  final open = [
    for (final bill in bills)
      if (!bill.isSettled && !bill.awaitsBankDebit(today)) bill,
  ]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  return open.firstOrNull;
}

Map<String, Object> _safeToSpend(
  SafeToSpend free,
  String Function(Money) amount,
) => {
  WidgetKeys.safeAmount: amount(
    free.isShort ? Money(-free.shortBy.cents) : free.daily,
  ),
  WidgetKeys.safeUntil: free.until.dayMonth,
  WidgetKeys.safeShort: free.isShort,
  WidgetKeys.safeTotal: amount(free.total),
  WidgetKeys.safeDays: free.days,
};

Map<String, Object> _nextBill(
  Bill? bill,
  CalendarDate today,
  String Function(Money) amount,
) => {
  WidgetKeys.billPayee: bill?.payee ?? '',
  WidgetKeys.billAmount: bill == null ? '' : amount(bill.amount),
  WidgetKeys.billDue: bill?.dueDate.dayMonth ?? '',
  WidgetKeys.billOverdue: bill?.isOverdue(today) ?? false,
};

Map<String, Object> _cardBill(
  CardsSummary? cards,
  String Function(Money) amount,
) => {
  WidgetKeys.cardAmount: cards == null ? '' : amount(cards.bill),
  WidgetKeys.cardDue: cards?.dueOn?.dayMonth ?? '',
};
