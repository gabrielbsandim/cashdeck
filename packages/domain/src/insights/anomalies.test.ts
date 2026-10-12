import { describe, expect, it } from 'vitest'
import { createTransaction } from '@/entities/transaction'
import {
  aboveAverage,
  averageOf,
  CARD_BILL_ABOVE_AVERAGE,
  chargeChange,
  isUnusual,
  median,
  UNUSUAL_PURCHASE,
  usualAmount,
} from '@/insights/anomalies'
import { summarizeCharges } from '@/insights/recurrence'
import { Money } from '@/money/money'

const charge = (entries: Array<[string, number]>) =>
  summarizeCharges(
    'streaming',
    entries.map(([bookedOn, cents], index) =>
      createTransaction({
        id: `c${index}`,
        tenantId: 't1',
        accountId: 'card',
        amount: Money.of(-cents),
        bookedOn,
        description: 'Streaming',
      }),
    ),
  )

describe('anomalies', () => {
  it('takes the median of odd and even samples', () => {
    expect(median([])).toBeNull()
    expect(median([5, 1, 3])).toBe(3)
    expect(median([4, 1, 3, 2])).toBe(2.5)
  })

  it('flags a purchase far above the usual and above the floor', () => {
    expect(usualAmount([100, 200], UNUSUAL_PURCHASE)).toBeNull()
    const usual = usualAmount([10_000, 9_000, 11_000], UNUSUAL_PURCHASE)
    expect(usual).toBe(10_000)
    expect(isUnusual(40_000, usual, UNUSUAL_PURCHASE)).toBe(true)
    expect(isUnusual(30_000, usual, UNUSUAL_PURCHASE)).toBe(false)
    expect(isUnusual(15_000, 1_000, UNUSUAL_PURCHASE)).toBe(false)
    expect(isUnusual(90_000, null, UNUSUAL_PURCHASE)).toBe(false)
  })

  it('compares a bill with the average of the ones before', () => {
    expect(averageOf([])).toBeNull()
    expect(averageOf([100, 201])).toBe(151)
    const history = [100_000, 110_000, 90_000]
    expect(aboveAverage(150_000, history, CARD_BILL_ABOVE_AVERAGE)).toEqual({
      average: 100_000,
      percent: 50,
    })
    expect(aboveAverage(125_000, history, CARD_BILL_ABOVE_AVERAGE)).toBeNull()
    expect(
      aboveAverage(1_400, [1_000, 1_000, 1_000], CARD_BILL_ABOVE_AVERAGE),
    ).toBeNull()
    expect(
      aboveAverage(150_000, [100_000, 100_000], CARD_BILL_ABOVE_AVERAGE),
    ).toBeNull()
    expect(aboveAverage(150_000, [], CARD_BILL_ABOVE_AVERAGE)).toBeNull()
  })

  it('reads a price increase or a second charge in the same month', () => {
    expect(
      chargeChange(
        charge([
          ['2026-09-05', 3990],
          ['2026-10-05', 4590],
        ]),
      ),
    ).toEqual({ kind: 'PRICE_UP', previous: Money.of(3990), percent: 15 })
    expect(
      chargeChange(
        charge([
          ['2026-09-05', 3990],
          ['2026-10-05', 3990],
          ['2026-10-07', 3990],
        ]),
      ),
    ).toEqual({ kind: 'DUPLICATE', month: '2026-10', count: 2 })
    expect(
      chargeChange(
        charge([
          ['2026-09-05', 3990],
          ['2026-10-05', 4050],
        ]),
      ),
    ).toBeNull()
    expect(chargeChange(charge([['2026-10-05', 3990]]))).toBeNull()
  })
})
