import 'package:cashdeck/core/money/money.dart';
import 'package:intl/intl.dart';

/// How a sign shows: [natural] puts a true minus on a negative amount,
/// [plus] also marks a positive one, [none] drops it (own transfers).
enum MoneySign { natural, plus, none }

abstract final class MoneyFormat {
  static const hidden = '••••';
  static const minus = '−';
  static const _space = ' ';

  static const Map<String, String> _symbols = {
    Money.brl: r'R$',
    'USD': r'US$',
    'EUR': '€',
  };

  static String symbolOf(String currency) => _symbols[currency] ?? currency;

  /// `R$ 1.234,56`, `−R$ 1.234,56`, `+R$ 7.800,00` or `US$ 20,00`.
  static String format(
    Money money, {
    bool hide = false,
    MoneySign sign = MoneySign.natural,
  }) {
    final number = NumberFormat.decimalPatternDigits(
      locale: 'pt_BR',
      decimalDigits: 2,
    ).format(money.cents.abs() / 100);
    return _compose(money, number, hide: hide, sign: sign);
  }

  /// Whole units only, as budgets read: `R$ 1.200`.
  static String whole(Money money, {bool hide = false}) {
    final number = NumberFormat.decimalPattern('pt_BR')
        .format((money.cents.abs() / 100).round());
    return _compose(money, number, hide: hide, sign: MoneySign.natural);
  }

  /// A short amount for chart centers: `R$ 4,3 mil`.
  static String compact(Money money, {bool hide = false}) {
    final number = NumberFormat.compact(locale: 'pt_BR')
        .format(money.cents.abs() / 100);
    return _compose(money, number, hide: hide, sign: MoneySign.natural);
  }

  /// The bare number without symbol, as a currency field shows it.
  static String digits(Money money, {bool hide = false}) {
    if (hide) return hidden;
    return NumberFormat.decimalPatternDigits(
      locale: 'pt_BR',
      decimalDigits: 2,
    ).format(money.cents / 100);
  }

  static String _compose(
    Money money,
    String number, {
    required bool hide,
    required MoneySign sign,
  }) {
    final symbol = symbolOf(money.currency);
    final prefix = _signOf(money, hide: hide, sign: sign);
    return '$prefix$symbol$_space${hide ? hidden : number}';
  }

  static String _signOf(
    Money money, {
    required bool hide,
    required MoneySign sign,
  }) {
    if (hide || sign == MoneySign.none) return '';
    if (money.isNegative) return minus;
    return sign == MoneySign.plus ? '+' : '';
  }
}
