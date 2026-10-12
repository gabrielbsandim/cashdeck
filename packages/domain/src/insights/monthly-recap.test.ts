import { describe, expect, it } from 'vitest'
import {
  buildMonthlyRecap,
  categoryShifts,
  centsChange,
  closedMonthOf,
  type MonthlyRecapInput,
  type RecapSubscription,
  requireClosedMonth,
  savingsPercent,
  subscriptionShifts,
  topCategory,
} from '@/insights/monthly-recap'
import { ValidationError } from '@/shared/domain-error'

const subscription = (
  key: string,
  chargedMonths: string[],
): RecapSubscription => ({ key, name: key, cents: 3_990, chargedMonths })

const INPUT: MonthlyRecapInput = {
  month: '2026-09',
  flow: { income: 800_000, expenses: 600_000 },
  previousFlow: { income: 800_000, expenses: 500_000 },
  categories: [
    { categoryId: 'food', cents: 200_000 },
    { categoryId: 'fun', cents: 50_000 },
  ],
  previousCategories: [{ categoryId: 'food', cents: 120_000 }],
  subscriptions: [
    subscription('music', ['2026-08', '2026-09']),
    subscription('video', ['2026-09']),
  ],
  netWorth: { end: 5_000_000, previousEnd: 4_800_000 },
}

describe('recap months', () => {
  it('covers the month before the given day', () => {
    expect(closedMonthOf('2026-10-01')).toBe('2026-09')
    expect(closedMonthOf('2026-01-15')).toBe('2025-12')
  })

  it('accepts a closed month and refuses an open or malformed one', () => {
    expect(requireClosedMonth('2026-09', '2026-10-01')).toBe('2026-09')
    expect(requireClosedMonth('2025-12', '2026-10-01')).toBe('2025-12')
    expect(() => requireClosedMonth('2026-10', '2026-10-01')).toThrow(
      'already closed',
    )
    expect(() => requireClosedMonth('2026-13', '2026-10-01')).toThrow(
      ValidationError,
    )
  })
})

describe('centsChange', () => {
  it('gives the difference and its percent of the previous amount', () => {
    expect(centsChange(12_000, 10_000)).toEqual({ cents: 2_000, percent: 20 })
    expect(centsChange(-5_000, -10_000)).toEqual({ cents: 5_000, percent: 50 })
  })

  it('has no percent without a previous amount', () => {
    expect(centsChange(10_000, 0)).toEqual({ cents: 10_000, percent: null })
  })
})

describe('savingsPercent', () => {
  it('is the share of the income kept, negative when it ran short', () => {
    expect(savingsPercent({ income: 1_000, expenses: 750, net: 250 })).toBe(25)
    expect(savingsPercent({ income: 1_000, expenses: 1_200, net: -200 })).toBe(
      -20,
    )
  })

  it('is unknown without income', () => {
    expect(savingsPercent({ income: 0, expenses: 500, net: -500 })).toBeNull()
  })
})

describe('topCategory', () => {
  it('picks the biggest spending with its share of the month', () => {
    expect(topCategory(INPUT.categories, 400_000)).toEqual({
      categoryId: 'food',
      cents: 200_000,
      sharePercent: 50,
    })
  })

  it('never claims more than the whole', () => {
    expect(topCategory(INPUT.categories, 0)?.sharePercent).toBe(100)
  })

  it('has none without spending', () => {
    expect(topCategory([], 0)).toBeNull()
    expect(topCategory([{ categoryId: 'food', cents: 0 }], 0)).toBeNull()
  })
})

describe('categoryShifts', () => {
  it('ranks the biggest moves each way and drops the small ones', () => {
    const shifts = categoryShifts(
      [
        { categoryId: 'food', cents: 200_000 },
        { categoryId: 'fun', cents: 50_000 },
        { categoryId: 'bus', cents: 10_000 },
      ],
      [
        { categoryId: 'food', cents: 120_000 },
        { categoryId: 'bus', cents: 12_000 },
        { categoryId: 'trip', cents: 90_000 },
      ],
    )
    expect(shifts.rose.map(shift => shift.categoryId)).toEqual(['food', 'fun'])
    expect(shifts.rose[1]).toEqual({
      categoryId: 'fun',
      cents: 50_000,
      previousCents: 0,
      change: { cents: 50_000, percent: null },
    })
    expect(shifts.fell).toEqual([
      {
        categoryId: 'trip',
        cents: 0,
        previousCents: 90_000,
        change: { cents: -90_000, percent: -100 },
      },
    ])
  })

  it('keeps the top three', () => {
    const current = ['a', 'b', 'c', 'd'].map((categoryId, index) => ({
      categoryId,
      cents: (index + 1) * 10_000,
    }))
    expect(
      categoryShifts(current, []).rose.map(shift => shift.categoryId),
    ).toEqual(['d', 'c', 'b'])
    expect(
      categoryShifts([], current).fell.map(shift => shift.categoryId),
    ).toEqual(['d', 'c', 'b'])
  })
})

describe('subscriptionShifts', () => {
  it('finds the ones that started and stopped in the month', () => {
    const shifts = subscriptionShifts(
      [
        subscription('kept', ['2026-08', '2026-09']),
        subscription('new', ['2026-09']),
        subscription('gone', ['2026-07', '2026-08']),
        subscription('back', ['2026-07', '2026-09']),
        subscription('skipped', ['2026-08', '2026-10']),
        subscription('old', ['2026-05']),
      ],
      '2026-09',
    )
    expect(shifts.started.map(item => item.key)).toEqual(['new'])
    expect(shifts.stopped.map(item => item.key)).toEqual(['gone'])
  })
})

describe('buildMonthlyRecap', () => {
  it('puts the month together', () => {
    const facts = buildMonthlyRecap(INPUT)
    expect(facts).toMatchObject({
      month: '2026-09',
      flow: { income: 800_000, expenses: 600_000, net: 200_000 },
      previousFlow: { net: 300_000 },
      incomeChange: { cents: 0, percent: 0 },
      expensesChange: { cents: 100_000, percent: 20 },
      savingsPercent: 25,
      previousSavingsPercent: 38,
      topCategory: { categoryId: 'food', sharePercent: 33 },
      netWorth: { end: 5_000_000, change: { cents: 200_000, percent: 4 } },
    })
    expect(facts.rose.map(shift => shift.categoryId)).toEqual(['food', 'fun'])
    expect(facts.started.map(item => item.key)).toEqual(['video'])
    expect(facts.stopped).toEqual([])
  })

  it('leaves the net worth out when it is unknown', () => {
    expect(buildMonthlyRecap({ ...INPUT, netWorth: null }).netWorth).toBeNull()
  })
})
