import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/home/domain/home_summary.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';

void main() {
  test('a forecast spends daily, applies events and finds its lowest day', () {
    final forecast = CashForecast.project(
      from: testToday,
      start: const Money(10_000),
      dailySpend: const Money(1_000),
      events: const {2: Money(-5_000), 3: Money(20_000)},
      days: 4,
      floor: const Money(3_000),
    );

    expect(forecast.balances, const [
      Money(10_000),
      Money(9_000),
      Money(3_000),
      Money(22_000),
      Money(21_000),
    ]);
    expect(forecast.lowestDay, 2);
    expect(forecast.lowest, const Money(3_000));
    expect(forecast.lowestDate, const CalendarDate(2026, 10, 10));
    expect(forecast.last, const Money(21_000));
    expect(forecast.lastDate, const CalendarDate(2026, 10, 12));
    expect(
      forecast,
      CashForecast(
        from: testToday,
        balances: forecast.balances,
        floor: const Money(3_000),
      ),
    );
  });

  test('a budget is exceeded only past its limit', () {
    const atLimit = BudgetSummary(
      category: BudgetCategory.groceries,
      spent: Money(100),
      limit: Money(100),
    );
    const past = BudgetSummary(
      category: BudgetCategory.restaurants,
      spent: Money(101),
      limit: Money(100),
    );

    expect(atLimit.exceeded, isFalse);
    expect(past.exceeded, isTrue);
  });

  test('the consolidated view counts transfers apart from the net', () {
    const summary = ConsolidatedSummary(
      personal: Money(3_000),
      company: Money(1_000),
      externalIn: Money(900),
      externalOut: Money(-400),
      transfers: [
        InternalTransfer(
          id: 'a',
          kind: InternalTransferKind.proLabore,
          amount: Money(200),
          on: testToday,
        ),
        InternalTransfer(
          id: 'b',
          kind: InternalTransferKind.profitDistribution,
          amount: Money(300),
          on: testToday,
        ),
      ],
    );
    const empty = ConsolidatedSummary(
      personal: Money(0),
      company: Money(0),
      externalIn: Money(0),
      externalOut: Money(0),
      transfers: [],
    );

    expect(summary.total, const Money(4_000));
    expect(summary.internal, const Money(500));
    expect(summary.net, const Money(500));
    expect(summary.personalShare, 0.75);
    expect(empty.personalShare, 0);
  });

  test('every summary and alert compares by value', () {
    final sync = SyncInfo(accountCount: 1, syncedAt: testNow);
    const reserve = ReserveSummary(
      institution: 'Banco Exemplo',
      product: 'CDB',
      balance: Money(1),
      monthYield: Money(1),
      coverDays: 1,
      cdiPercent: 100,
    );
    const forecast = CashForecast(
      from: testToday,
      balances: [Money(1), Money(1)],
      floor: Money(0),
    );
    const budget = BudgetSummary(
      category: BudgetCategory.transport,
      spent: Money(1),
      limit: Money(2),
    );
    PersonalSummary personal() => PersonalSummary(
      balance: const Money(1),
      sync: sync,
      reserve: reserve,
      forecast: forecast,
      budgets: const [budget],
      alerts: [
        AssistedPaymentAlert(
          billId: 'bill',
          payee: 'Payee',
          reason: 'Motivo',
          at: testNow,
        ),
        BudgetExceededAlert(budget: budget, at: testNow),
      ],
    );
    CompanySummary company() => CompanySummary(
      cash: const Money(1),
      sync: sync,
      billed: const Money(1),
      invoiceCount: 1,
      dasEstimate: const Money(1),
      dasDue: testToday,
      inss: const TaxEstimate(amount: Money(1), due: testToday),
      drafts: const [
        InvoiceDraft(
          id: 'draft',
          customer: 'Cliente Exemplo',
          amount: Money(1),
          recurring: false,
          issueOn: testToday,
        ),
      ],
      unbilled: const [
        UnbilledReceipt(
          id: 'receipt',
          payer: 'Pagador Exemplo',
          amount: Money(1),
          receivedOn: testToday,
        ),
      ],
    );

    expect(personal(), personal());
    expect(company(), company());
    expect(personal().props, hasLength(6));
    expect(company().props, hasLength(9));
    expect(company().inss?.props, hasLength(2));
    expect(reserve.props, hasLength(6));
    expect(budget.props, hasLength(4));
    expect(company().drafts.single.props, hasLength(5));
    expect(company().unbilled.single.props, hasLength(4));
    expect(
      const InternalTransfer(
        id: 'a',
        kind: InternalTransferKind.proLabore,
        amount: Money(1),
        on: testToday,
      ).props,
      hasLength(4),
    );
    expect(
      const ConsolidatedSummary(
        personal: Money(0),
        company: Money(0),
        externalIn: Money(0),
        externalOut: Money(0),
        transfers: [],
      ).props,
      hasLength(5),
    );
  });
}
