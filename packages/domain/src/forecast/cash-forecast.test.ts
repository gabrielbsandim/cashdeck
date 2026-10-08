import { describe, expect, it } from 'vitest'
import {
  averageDailySpend,
  coverDays,
  projectBalances,
} from '@/forecast/cash-forecast'
import { Money } from '@/money/money'

describe('projectBalances', () => {
  it('spends the daily average and applies events on their day', () => {
    const balances = projectBalances({
      start: Money.of(1000),
      dailySpend: Money.of(100),
      events: [
        { day: 2, amount: Money.of(-300) },
        { day: 2, amount: Money.of(50) },
      ],
      days: 3,
    })
    expect(balances.map(balance => balance.cents)).toEqual([
      1000, 900, 550, 450,
    ])
  })
})

describe('averageDailySpend', () => {
  it('averages absolute expenses over the window', () => {
    expect(averageDailySpend([Money.of(-300), Money.of(-301)], 30).cents).toBe(
      20,
    )
    expect(averageDailySpend([], 30).cents).toBe(0)
  })
})

describe('coverDays', () => {
  it('counts the days of bills a balance pays, capped', () => {
    const bills = [
      { day: 10, amount: Money.of(500) },
      { day: 3, amount: Money.of(400) },
    ]
    expect(coverDays(Money.of(800), bills, 90)).toBe(10)
    expect(coverDays(Money.of(300), bills, 90)).toBe(3)
    expect(coverDays(Money.of(1000), bills, 90)).toBe(90)
    expect(coverDays(Money.of(0), [{ day: -2, amount: Money.of(1) }], 90)).toBe(
      0,
    )
    expect(
      coverDays(Money.of(0), [{ day: 120, amount: Money.of(1) }], 90),
    ).toBe(90)
  })
})
