import { describe, expect, it } from 'vitest'
import { Money } from '@/money/money'
import {
  budgetAvailable,
  budgetLevel,
  budgetUsage,
  createBudget,
  crossedThreshold,
  friendlyCents,
  isMonth,
  medianCents,
  rolloverInto,
  spendingUsage,
  suggestLimit,
} from '@/planning/budget'
import { ValidationError } from '@/shared/domain-error'

const base = {
  id: 'b1',
  tenantId: 't1',
  entityId: 'pf',
  categoryId: 'food',
  month: '2026-10',
  limit: Money.of(500_00),
  rollover: false,
}

describe('createBudget', () => {
  it('starts with nothing carried', () => {
    expect(createBudget(base).carried).toEqual(Money.zero())
    expect(budgetAvailable(createBudget(base))).toEqual(Money.of(500_00))
  })

  it('refuses a bad month, a limit that is not positive and a negative carry', () => {
    expect(() => createBudget({ ...base, month: '2026-13' })).toThrow(
      ValidationError,
    )
    expect(() => createBudget({ ...base, limit: Money.zero() })).toThrow(
      'positive limit',
    )
    expect(() => createBudget({ ...base, carried: Money.of(-1) })).toThrow(
      'negative leftover',
    )
  })

  it('reads a month', () => {
    expect(isMonth('2026-01')).toBe(true)
    expect(isMonth('2026-00')).toBe(false)
    expect(isMonth('26-01')).toBe(false)
  })
})

describe('usage', () => {
  const budget = createBudget({ ...base, carried: Money.of(100_00) })

  it('measures the spending against the limit plus the carry', () => {
    expect(budgetUsage(budget, Money.of(300_00))).toEqual({
      available: Money.of(600_00),
      remaining: Money.of(300_00),
      percent: 50,
      level: 'OK',
    })
    expect(budgetUsage(budget, Money.of(500_00)).level).toBe('NEAR')
    expect(budgetUsage(budget, Money.of(700_00))).toMatchObject({
      remaining: Money.of(-100_00),
      percent: 116,
      level: 'REACHED',
    })
    expect(budgetUsage(budget, Money.of(-10_00)).percent).toBe(0)
  })

  it('reads nothing available as nothing used', () => {
    expect(spendingUsage(Money.zero(), Money.zero())).toEqual({
      available: Money.zero(),
      remaining: Money.zero(),
      percent: 0,
      level: 'OK',
    })
  })

  it('names the level and the highest threshold crossed', () => {
    expect(budgetLevel(79)).toBe('OK')
    expect(budgetLevel(80)).toBe('NEAR')
    expect(budgetLevel(100)).toBe('REACHED')
    expect(crossedThreshold(79)).toBeNull()
    expect(crossedThreshold(85)).toBe(80)
    expect(crossedThreshold(140)).toBe(100)
  })
})

describe('rolloverInto', () => {
  const next = { id: 'b2', month: '2026-11' }

  it('carries the leftover only with rollover on', () => {
    const rolling = createBudget({
      ...base,
      rollover: true,
      carried: Money.of(50_00),
    })
    expect(rolloverInto(rolling, Money.of(400_00), next)).toEqual({
      ...rolling,
      ...next,
      carried: Money.of(150_00),
    })
    expect(rolloverInto(createBudget(base), Money.of(100_00), next)).toEqual({
      ...base,
      ...next,
      carried: Money.zero(),
    })
  })

  it('never carries an overspend', () => {
    const rolling = createBudget({ ...base, rollover: true })
    expect(rolloverInto(rolling, Money.of(600_00), next).carried).toEqual(
      Money.zero(),
    )
  })
})

describe('suggestions', () => {
  it('takes the median of the months', () => {
    expect(medianCents([])).toBe(0)
    expect(medianCents([30, 10, 20])).toBe(20)
    expect(medianCents([10, 21])).toBe(16)
  })

  it('rounds up to a friendly step', () => {
    expect(friendlyCents(0)).toBe(0)
    expect(friendlyCents(-5)).toBe(0)
    expect(friendlyCents(43_21)).toBe(50_00)
    expect(friendlyCents(432_10)).toBe(450_00)
    expect(friendlyCents(1_234_56)).toBe(1_300_00)
    expect(suggestLimit([410_00, 380_00, 900_00])).toEqual(Money.of(450_00))
  })
})
