import { describe, expect, it } from 'vitest'
import {
  expectedIncome,
  type IncomeCredit,
  lastDayOfMonth,
  monthlyDatesBetween,
  nextMonthlyDate,
  type Obligation,
  proratedBudgetLeft,
  safeToSpend,
} from '@/forecast/safe-to-spend'
import { Money } from '@/money/money'

const credit = (key: string, on: string, cents: number): IncomeCredit => ({
  key,
  on,
  amount: Money.of(cents),
})

const owed = (
  overrides: Partial<Obligation> & Pick<Obligation, 'on'>,
): Obligation => ({
  kind: 'BILL',
  label: 'Power',
  amount: Money.of(10000),
  fromReserve: false,
  ...overrides,
})

describe('calendar helpers', () => {
  it('finds the last day of a month', () => {
    expect(lastDayOfMonth('2026-02-10')).toBe('2026-02-28')
    expect(lastDayOfMonth('2026-12-31')).toBe('2026-12-31')
  })

  it('moves to the next date on a day of the month', () => {
    expect(nextMonthlyDate('2026-10-08', 20)).toBe('2026-10-20')
    expect(nextMonthlyDate('2026-10-08', 5)).toBe('2026-11-05')
    expect(nextMonthlyDate('2026-10-05', 5)).toBe('2026-11-05')
    expect(nextMonthlyDate('2027-01-31', 31)).toBe('2027-02-28')
    expect(nextMonthlyDate('2027-02-28', 31)).toBe('2027-03-31')
  })

  it('lists the dates of a day of the month in a range', () => {
    expect(monthlyDatesBetween(10, '2026-10-08', '2026-12-10')).toEqual([
      '2026-10-10',
      '2026-11-10',
      '2026-12-10',
    ])
    expect(monthlyDatesBetween(8, '2026-10-08', '2026-10-31')).toEqual([
      '2026-10-08',
    ])
    expect(monthlyDatesBetween(1, '2026-10-08', '2026-10-31')).toEqual([])
  })
})

describe('expectedIncome', () => {
  it('projects the soonest monthly stream and adds those on the same day', () => {
    const income = expectedIncome(
      [
        credit('salary', '2026-08-05', 800000),
        credit('salary', '2026-09-05', 800000),
        credit('salary', '2026-10-05', 820000),
        credit('bonus', '2026-09-20', 300000),
        credit('bonus', '2026-08-20', 300000),
        credit('rent', '2026-09-05', 250000),
        credit('rent', '2026-08-05', 250000),
      ],
      '2026-10-08',
    )
    expect(income).toEqual({ on: '2026-10-20', amount: Money.of(300000) })
  })

  it('adds the streams that arrive on the same day', () => {
    const income = expectedIncome(
      [
        credit('salary', '2026-08-25', 500000),
        credit('salary', '2026-09-25', 500000),
        credit('rent', '2026-08-25', 200000),
        credit('rent', '2026-09-25', 200000),
      ],
      '2026-10-08',
    )
    expect(income).toEqual({ on: '2026-10-25', amount: Money.of(700000) })
  })

  it('keeps the largest credit of a month for a payer', () => {
    const income = expectedIncome(
      [
        credit('company', '2026-09-05', 100000),
        credit('company', '2026-09-20', 900000),
        credit('company', '2026-08-20', 900000),
        credit('company', '2026-08-02', 100000),
      ],
      '2026-10-08',
    )
    expect(income).toEqual({ on: '2026-10-20', amount: Money.of(900000) })
  })

  it('ignores one-off, stale, small and negative credits', () => {
    expect(
      expectedIncome(
        [
          credit('once', '2026-10-01', 900000),
          credit('old', '2026-06-10', 900000),
          credit('old', '2026-07-10', 900000),
          credit('refund', '2026-09-12', -500),
          credit('refund', '2026-10-01', -500),
        ],
        '2026-10-08',
      ),
    ).toBeNull()
    const income = expectedIncome(
      [
        credit('salary', '2026-09-28', 800000),
        credit('salary', '2026-08-28', 800000),
        credit('cashback', '2026-09-10', 1000),
        credit('cashback', '2026-08-10', 1000),
      ],
      '2026-10-08',
    )
    expect(income).toEqual({ on: '2026-10-28', amount: Money.of(800000) })
  })
})

describe('safeToSpend', () => {
  it('splits what is left until the income over the days before it', () => {
    const result = safeToSpend({
      today: '2026-10-08',
      cash: Money.of(500000),
      reserve: Money.of(15000),
      income: { on: '2026-10-20', amount: Money.of(800000) },
      obligations: [
        owed({ on: '2026-10-15', label: 'Water', fromReserve: true }),
        owed({ on: '2026-10-10', label: 'Rent', fromReserve: true }),
        owed({
          on: '2026-10-20',
          kind: 'CARD',
          label: 'Card',
          amount: Money.of(50000),
        }),
        owed({ on: '2026-10-10', kind: 'SUBSCRIPTION', label: 'Music' }),
        owed({ on: '2026-10-21', label: 'Later' }),
      ],
    })
    expect(result.until).toBe('2026-10-20')
    expect(result.days).toBe(12)
    expect(result.total.cents).toBe(500000 - 20000 + 15000 - 50000 - 10000)
    expect(result.daily.cents).toBe(Math.floor(435000 / 12))
    expect(result.shortBy.cents).toBe(0)
    expect(result.lines.map(line => [line.kind, line.amount.cents])).toEqual([
      ['SUBSCRIPTION', -10000],
      ['BILL', -10000],
      ['BILL', -10000],
      ['CARD', -50000],
      ['RESERVE', 15000],
    ])
    expect(result.lines.map(line => line.label)).toEqual([
      'Music',
      'Rent',
      'Water',
      'Card',
      '',
    ])
  })

  it('falls back to the end of the month without a known income', () => {
    const result = safeToSpend({
      today: '2026-10-08',
      cash: Money.of(240000),
      reserve: Money.of(-500),
      income: null,
      obligations: [owed({ on: '2026-10-10', fromReserve: true })],
    })
    expect(result.until).toBe('2026-10-31')
    expect(result.days).toBe(24)
    expect(result.total.cents).toBe(230000)
    expect(result.lines.map(line => line.kind)).toEqual(['BILL'])
  })

  it('takes what cash spent today whole off what is left for today', () => {
    const leftAfter = (cash: number, spent: number) =>
      safeToSpend({
        today: '2026-10-08',
        cash: Money.of(cash),
        reserve: Money.zero(),
        income: null,
        obligations: [],
        spentToday: Money.of(spent),
      }).daily.cents
    expect(leftAfter(240000, 0)).toBe(10000)
    expect(leftAfter(238000, 2000)).toBe(8000)
    expect(leftAfter(230000, 10000)).toBe(0)
  })

  it('says how short the money falls, with nothing to spend', () => {
    const result = safeToSpend({
      today: '2026-10-08',
      cash: Money.of(5000),
      reserve: Money.zero(),
      income: { on: '2026-10-08', amount: Money.of(100) },
      obligations: [owed({ on: '2026-10-08' })],
    })
    expect(result.days).toBe(1)
    expect(result.total.cents).toBe(-5000)
    expect(result.daily.cents).toBe(0)
    expect(result.shortBy.cents).toBe(5000)
  })

  it('reserves the budgets left for the part of the month the window covers', () => {
    const result = safeToSpend({
      today: '2026-10-22',
      cash: Money.of(100000),
      reserve: Money.zero(),
      income: { on: '2026-10-27', amount: Money.of(800000) },
      obligations: [],
      budgets: [
        { label: 'Groceries', left: Money.of(20000) },
        { label: 'Bars', left: Money.of(20000) },
        { label: 'Fuel', left: Money.of(-3000) },
      ],
    })
    expect(result.days).toBe(5)
    expect(
      result.lines.map(line => [
        line.kind,
        line.label,
        line.amount.cents,
        line.on,
      ]),
    ).toEqual([
      ['BUDGET', 'Bars', -10000, null],
      ['BUDGET', 'Groceries', -10000, null],
    ])
    expect(result.total.cents).toBe(80000)
  })
})

describe('proratedBudgetLeft', () => {
  it('keeps the share of the days left in the month the window covers', () => {
    expect(proratedBudgetLeft(Money.of(31000), '2026-10-01', 31).cents).toBe(
      31000,
    )
    expect(proratedBudgetLeft(Money.of(31000), '2026-10-01', 10).cents).toBe(
      10000,
    )
    expect(proratedBudgetLeft(Money.of(1000), '2026-10-30', 40).cents).toBe(
      1000,
    )
    expect(proratedBudgetLeft(Money.of(1000), '2026-10-01', 1).cents).toBe(33)
  })

  it('keeps nothing of a budget already spent or overspent', () => {
    expect(proratedBudgetLeft(Money.zero(), '2026-10-01', 10).isZero()).toBe(
      true,
    )
    expect(proratedBudgetLeft(Money.of(-500), '2026-10-01', 10).isZero()).toBe(
      true,
    )
  })
})
