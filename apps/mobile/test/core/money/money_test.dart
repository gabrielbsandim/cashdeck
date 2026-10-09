import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const nbsp = '\u00A0';
  const minus = MoneyFormat.minus;

  test('is integer cents of a currency', () {
    const amount = Money(-1050);

    expect(Money.brlFromReais(10.5), const Money(1050));
    expect(amount.isNegative, isTrue);
    expect(amount.abs, const Money(1050));
    expect(amount.isForeign, isFalse);
    expect(const Money(1, currency: 'USD').isForeign, isTrue);
    expect(const Money(100) + const Money(50), const Money(150));
    expect(const Money(100) - const Money(150), const Money(-50));
    expect(-const Money(7, currency: 'USD'), const Money(-7, currency: 'USD'));
    expect(const Money(100).compareTo(const Money(50)), greaterThan(0));
    expect(
      () => const Money(1) + const Money(1, currency: 'USD'),
      throwsArgumentError,
    );
  });

  test('formats reais with a true minus', () {
    expect(MoneyFormat.format(const Money(123456)), 'R\$${nbsp}1.234,56');
    expect(
      MoneyFormat.format(const Money(-123456)),
      '${minus}R\$${nbsp}1.234,56',
    );
  });

  test('a sign can be forced or dropped', () {
    expect(
      MoneyFormat.format(const Money(780000), sign: MoneySign.plus),
      '+R\$${nbsp}7.800,00',
    );
    expect(
      MoneyFormat.format(const Money(-780000), sign: MoneySign.plus),
      '${minus}R\$${nbsp}7.800,00',
    );
    expect(
      MoneyFormat.format(const Money(-500), sign: MoneySign.none),
      'R\$${nbsp}5,00',
    );
  });

  test('a foreign currency shows its symbol or code', () {
    expect(
      MoneyFormat.format(const Money(2000, currency: 'USD')),
      'US\$${nbsp}20,00',
    );
    expect(
      MoneyFormat.format(const Money(2000, currency: 'EUR')),
      '€${nbsp}20,00',
    );
    expect(
      MoneyFormat.format(const Money(2000, currency: 'GBP')),
      'GBP${nbsp}20,00',
    );
  });

  test('hides the figure and the sign when privacy is on', () {
    expect(
      MoneyFormat.format(const Money(-123456), hide: true),
      'R\$$nbsp••••',
    );
    expect(MoneyFormat.whole(const Money(120000), hide: true), 'R\$$nbsp••••');
    expect(
      MoneyFormat.format(const Money(780000), hide: true, sign: MoneySign.plus),
      'R\$$nbsp••••',
    );
    expect(
      MoneyFormat.compact(const Money(430000), hide: true),
      'R\$$nbsp••••',
    );
    expect(MoneyFormat.digits(const Money(1), hide: true), MoneyFormat.hidden);
  });

  test(
    'whole, compact and digits drop what a chart or field does not need',
    () {
      expect(MoneyFormat.whole(const Money(120049)), 'R\$${nbsp}1.200');
      expect(
        MoneyFormat.compact(const Money(430000)),
        matches(RegExp(r'^R\$\u00A04,3\smil$')),
      );
      expect(MoneyFormat.digits(const Money(123456)), '1.234,56');
    },
  );
}
