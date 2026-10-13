import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/home_widget/domain/widget_snapshot.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';
import '../home_widget_support.dart';

String _brl(String figure) => 'R\$\u00A0$figure';

final String _masked = _brl(MoneyFormat.hidden);

void main() {
  group('WidgetSnapshot.from', () {
    test('formats every part and stamps the Brazil time of the update', () {
      final snapshot = WidgetSnapshot.from(
        now: testNow,
        hide: false,
        safeToSpend: safeToSpendOf(),
        bills: [
          testBill(
            payee: 'Energia Exemplo',
            amount: const Money(18_990),
            dueDate: testToday.addDays(4),
          ),
        ],
        overview: overviewWith(
          const CardsSummary(
            bill: Money(123_456),
            count: 1,
            dueOn: CalendarDate(2026, 10, 15),
          ),
        ),
      );

      expect(snapshot.values, <String, Object>{
        WidgetKeys.hidden: false,
        WidgetKeys.updatedTime: '12:00',
        WidgetKeys.updatedOn: '2026-10-08',
        WidgetKeys.safeAmount: _brl('85,00'),
        WidgetKeys.safeUntil: '31/10',
        WidgetKeys.safeShort: false,
        WidgetKeys.safeTotal: _brl('1.955,00'),
        WidgetKeys.safeDays: 23,
        WidgetKeys.billPayee: 'Energia Exemplo',
        WidgetKeys.billAmount: _brl('189,90'),
        WidgetKeys.billDue: '12/10',
        WidgetKeys.billOverdue: false,
        WidgetKeys.cardAmount: _brl('1.234,56'),
        WidgetKeys.cardDue: '15/10',
      });
    });

    test('masks every amount under privacy and keeps names and dates', () {
      final snapshot = WidgetSnapshot.from(
        now: testNow,
        hide: true,
        safeToSpend: safeToSpendOf(),
        bills: [testBill(payee: 'Energia Exemplo')],
        overview: overviewWith(
          const CardsSummary(bill: Money(123_456), count: 1),
        ),
      );

      expect(snapshot.values[WidgetKeys.hidden], isTrue);
      expect(snapshot.values[WidgetKeys.safeAmount], _masked);
      expect(snapshot.values[WidgetKeys.safeTotal], _masked);
      expect(snapshot.values[WidgetKeys.safeDays], 23);
      expect(snapshot.values[WidgetKeys.billAmount], _masked);
      expect(snapshot.values[WidgetKeys.cardAmount], _masked);
      expect(snapshot.values[WidgetKeys.billPayee], 'Energia Exemplo');
      expect(snapshot.values[WidgetKeys.billDue], '08/10');
    });

    test('shows what is missing as a negative amount when short', () {
      final snapshot = WidgetSnapshot.from(
        now: testNow,
        hide: false,
        safeToSpend: safeToSpendOf(
          daily: const Money(0),
          shortBy: const Money(12_000),
        ),
      );

      expect(
        snapshot.values[WidgetKeys.safeAmount],
        '${MoneyFormat.minus}${_brl('120,00')}',
      );
      expect(snapshot.values[WidgetKeys.safeShort], isTrue);
    });

    test('leaves out the parts that have not loaded', () {
      final snapshot = WidgetSnapshot.from(
        now: testNow,
        hide: false,
        bills: const [],
      );

      expect(snapshot.values.keys, isNot(contains(WidgetKeys.safeAmount)));
      expect(snapshot.values.keys, isNot(contains(WidgetKeys.cardAmount)));
      expect(snapshot.values[WidgetKeys.billPayee], '');
      expect(snapshot.values[WidgetKeys.billAmount], '');
      expect(snapshot.values[WidgetKeys.billDue], '');
      expect(snapshot.values[WidgetKeys.billOverdue], isFalse);
    });

    test('keeps the update time while nothing loaded', () {
      final snapshot = WidgetSnapshot.from(now: testNow, hide: true);

      expect(snapshot.values, {WidgetKeys.hidden: true});
    });

    test('says there is no card when the overview has none', () {
      final snapshot = WidgetSnapshot.from(
        now: testNow,
        hide: false,
        overview: overviewWith(null),
      );

      expect(snapshot.values[WidgetKeys.cardAmount], '');
      expect(snapshot.values[WidgetKeys.cardDue], '');
    });

    test('leaves the card due date blank when the issuer gave none', () {
      final snapshot = WidgetSnapshot.from(
        now: testNow,
        hide: false,
        overview: overviewWith(const CardsSummary(bill: Money(500), count: 1)),
      );

      expect(snapshot.values[WidgetKeys.cardAmount], _brl('5,00'));
      expect(snapshot.values[WidgetKeys.cardDue], '');
    });

    test('flags an overdue bill', () {
      final snapshot = WidgetSnapshot.from(
        now: testNow,
        hide: false,
        bills: [testBill(dueDate: testToday.addDays(-2))],
      );

      expect(snapshot.values[WidgetKeys.billOverdue], isTrue);
      expect(snapshot.values[WidgetKeys.billDue], '06/10');
    });

    test('compares by value', () {
      expect(
        WidgetSnapshot.from(now: testNow, hide: false),
        WidgetSnapshot.from(now: testNow, hide: false),
      );
    });
  });

  group('nextBillOf', () {
    test('picks the open bill due first, overdue ones included', () {
      final overdue = testBill(id: 'late', dueDate: testToday.addDays(-1));
      final bills = [
        testBill(id: 'later', dueDate: testToday.addDays(9)),
        overdue,
        testBill(id: 'soon', dueDate: testToday.addDays(1)),
      ];

      expect(nextBillOf(bills, testToday), overdue);
    });

    test('skips settled bills and the ones the bank debits late', () {
      final bills = [
        testBill(id: 'paid', status: BillStatus.paid),
        testBill(id: 'cancelled', status: BillStatus.cancelled),
        testBill(id: 'debit', dueDate: testToday.addDays(-1), autoDebit: true),
      ];

      expect(nextBillOf(bills, testToday), isNull);
    });

    test('keeps an automatic debit that is not due yet', () {
      final debit = testBill(dueDate: testToday.addDays(3), autoDebit: true);

      expect(nextBillOf([debit], testToday), debit);
    });
  });

  test('lists every key once', () {
    expect(WidgetKeys.all.toSet(), hasLength(WidgetKeys.all.length));
    expect(WidgetKeys.all, hasLength(14));
  });
}
