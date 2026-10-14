import { describe, expect, it } from 'vitest'
import {
  comparePayment,
  incomeTaxRate,
  installmentsFadeMonth,
  yearlyFromDaily,
} from '@/planning/purchase-payment'

describe('income tax rate', () => {
  it('falls with the months the money stays invested', () => {
    expect([3, 6, 7, 12, 24, 25].map(incomeTaxRate)).toEqual([
      0.225, 0.225, 0.2, 0.2, 0.175, 0.15,
    ])
  })
})

describe('yearly from daily', () => {
  it('compounds the mean daily rate over the business days of a year', () => {
    expect(yearlyFromDaily([0.0551, 0.0551])).toBeCloseTo(14.891, 3)
  })

  it('knows nothing without rates', () => {
    expect(yearlyFromDaily([])).toBeNull()
  })
})

describe('compare payment', () => {
  const phone = {
    amountCents: 2_000_000,
    priceCents: 2_000_000,
    discountPercent: 5,
    installments: 10,
    yearlyPercent: 14,
  }

  it('prefers cash when the discount beats what the money earns meanwhile', () => {
    expect(comparePayment(phone)).toEqual({
      installments: 10,
      cashCents: 1_900_000,
      cardTodayCents: 1_906_686,
      better: 'CASH',
      gainCents: 6_686,
      breakEvenPercent: 4.7,
    })
  })

  it('prefers the card when there is no discount', () => {
    expect(comparePayment({ ...phone, discountPercent: 0 })).toMatchObject({
      cashCents: 2_000_000,
      better: 'CARD',
      gainCents: 93_314,
    })
  })

  it('takes the discount on the full price, before the trade-in', () => {
    expect(
      comparePayment({
        ...phone,
        amountCents: 300_000,
        priceCents: 400_000,
        installments: 3,
      }),
    ).toMatchObject({ cashCents: 280_000, cardTodayCents: 294_966 })
  })

  it('has nothing to compare at once or with nothing to pay', () => {
    expect(comparePayment({ ...phone, installments: 1 })).toBeNull()
    expect(comparePayment({ ...phone, amountCents: 0 })).toBeNull()
  })
})

describe('installments fade month', () => {
  const committed = [
    { month: '2026-11', cents: 348_700 },
    { month: '2026-12', cents: 298_900 },
    { month: '2027-01', cents: 73_600 },
    { month: '2027-02', cents: 18_500 },
    { month: '2027-03', cents: 8_900 },
  ]

  it('is the first month the installments stay under the limit', () => {
    expect(installmentsFadeMonth(committed, 100_000)).toBe('2027-01')
    expect(installmentsFadeMonth(committed, 10_000)).toBe('2027-03')
  })

  it('is the first month when they are already low', () => {
    expect(installmentsFadeMonth(committed, 400_000)).toBe('2026-11')
  })

  it('is unknown when they never fall under it', () => {
    expect(installmentsFadeMonth(committed, 1_000)).toBeNull()
    expect(installmentsFadeMonth([], 1_000)).toBeNull()
  })
})
