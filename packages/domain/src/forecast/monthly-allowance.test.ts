import { describe, expect, it } from 'vitest'
import {
  cashShortfall,
  monthlyAllowance,
  typicalMonth,
} from '@/forecast/monthly-allowance'
import { type Obligation } from '@/forecast/safe-to-spend'
import { Money } from '@/money/money'

const owed = (
  overrides: Partial<Obligation> & Pick<Obligation, 'on'>,
): Obligation => ({
  kind: 'BILL',
  label: 'Power',
  amount: Money.of(10000),
  fromReserve: false,
  ...overrides,
})

describe('typicalMonth', () => {
  it('ignores one outlier month and never saves below zero', () => {
    const typical = typicalMonth([
      { month: '2026-07', income: 2_000_000, expenses: 2_100_000 },
      { month: '2026-08', income: 5_700_000, expenses: 2_500_000 },
      { month: '2026-09', income: 2_200_001, expenses: 2_300_000 },
      { month: '2026-10', income: 2_200_000, expenses: 2_300_000 },
    ])
    expect(typical).toEqual({
      income: Money.of(2_200_001),
      saved: Money.zero(),
      months: 4,
    })
  })

  it('knows nothing without a closed month', () => {
    expect(typicalMonth([])).toBeNull()
  })
})

describe('monthlyAllowance', () => {
  it('takes the target, the spending and what is still owed off the income', () => {
    const allowance = monthlyAllowance({
      today: '2026-10-12',
      income: Money.of(2_000_000),
      savings: Money.of(500_000),
      spentOnCards: Money.of(400_000),
      spentFromAccounts: Money.of(100_000),
      obligations: [
        owed({ on: '2026-10-29', label: 'Mortgage', kind: 'FIXED' }),
        owed({ on: '2026-10-05', label: 'Late power' }),
        owed({ on: '2026-11-02', label: 'Next month' }),
      ],
      budgets: [{ label: 'Groceries', left: Money.of(30000) }],
    })
    expect(allowance).toMatchObject({
      until: '2026-10-31',
      days: 20,
      total: { cents: 950_000 },
      daily: { cents: 47_500 },
      shortBy: { cents: 0 },
    })
    expect(
      allowance.lines.map(line => [line.kind, line.label, line.amount.cents]),
    ).toEqual([
      ['INCOME', '', 2_000_000],
      ['SAVINGS', '', -500_000],
      ['SPENT_CARD', '', -400_000],
      ['SPENT_ACCOUNT', '', -100_000],
      ['BILL', 'Late power', -10000],
      ['FIXED', 'Mortgage', -10000],
      ['BUDGET', 'Groceries', -30000],
    ])
  })

  it('says how far the month is overspent', () => {
    const allowance = monthlyAllowance({
      today: '2026-10-31',
      income: Money.of(100_000),
      savings: Money.zero(),
      spentOnCards: Money.of(150_000),
      spentFromAccounts: Money.zero(),
      obligations: [],
    })
    expect(allowance).toMatchObject({
      days: 1,
      total: { cents: -50_000 },
      daily: { cents: 0 },
      shortBy: { cents: 50_000 },
    })
  })
})

describe('cashShortfall', () => {
  it('is what checking and the reserve leave unpaid until the day', () => {
    const obligations = [
      owed({ on: '2026-10-20', amount: Money.of(30000), fromReserve: true }),
      owed({ on: '2026-10-25', amount: Money.of(50000) }),
      owed({ on: '2026-12-01', amount: Money.of(999_999) }),
    ]
    const shortfall = (cash: number) =>
      cashShortfall({
        until: '2026-11-11',
        cash: Money.of(cash),
        reserve: Money.of(20000),
        obligations,
      }).cents
    expect(shortfall(40000)).toBe(20000)
    expect(shortfall(70000)).toBe(0)
  })
})
