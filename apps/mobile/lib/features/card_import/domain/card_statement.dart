import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:equatable/equatable.dart';

final class StatementLine extends Equatable {
  const new({
    required this.id,
    required this.merchant,
    required this.date,
    required this.amount,
    this.needsReview = false,
  });

  final String id;
  final String merchant;
  final CalendarDate date;

  /// In the card's currency, as the statement prints it.
  final Money amount;

  /// The reader was unsure about this line.
  final bool needsReview;

  @override
  List<Object?> get props => [id, merchant, date, amount, needsReview];
}

/// A card bill read from the statement PDF, for a card with no Open
/// Finance. [rate] is BRL per unit with four decimals; [iofBps] in basis
/// points.
final class CardStatement extends Equatable {
  const new({
    required this.card,
    required this.issuer,
    required this.closing,
    required this.due,
    required this.rate,
    required this.iofBps,
    required this.lines,
  });

  final String card;
  final String issuer;
  final CalendarDate closing;
  final CalendarDate due;
  final int rate;
  final int iofBps;
  final List<StatementLine> lines;

  Money brlOf(Money foreign) => Money((foreign.cents * rate / 10000).round());

  @override
  List<Object?> get props => [card, issuer, closing, due, rate, iofBps, lines];
}

/// The bill that the selected lines add up to: foreign subtotal, its BRL
/// conversion, IOF on top and the total.
final class StatementTotals extends Equatable {
  const new({required this.foreign, required this.subtotal, required this.iof});

  factory of(CardStatement statement, Set<String> selected) {
    final picked = [
      for (final line in statement.lines)
        if (selected.contains(line.id)) line,
    ];
    final currency = statement.lines.firstOrNull?.amount.currency ?? Money.brl;
    final foreign = picked.fold(
      Money(0, currency: currency),
      (sum, line) => sum + line.amount,
    );
    final subtotal = statement.brlOf(foreign);
    final iof = Money((subtotal.cents * statement.iofBps / 10000).round());
    return StatementTotals(foreign: foreign, subtotal: subtotal, iof: iof);
  }

  final Money foreign;
  final Money subtotal;
  final Money iof;

  Money get total => subtotal + iof;

  @override
  List<Object?> get props => [foreign, subtotal, iof];
}

abstract interface class CardImportRepository {
  Future<Result<CardStatement>> statement();

  /// Creates the bill for [total] due on the statement's date; returns its id.
  Future<Result<String>> createBill(CardStatement statement, Money total);
}
