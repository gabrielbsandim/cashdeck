import { describe, expect, it } from 'vitest'
import { Money } from '@/money/money'
import { proLaboreInss } from '@/tax/inss'

describe('proLaboreInss', () => {
  it('takes 11% of the pro-labore up to the ceiling', () => {
    expect(proLaboreInss(Money.of(500_000)).cents).toBe(55_000)
    expect(proLaboreInss(Money.of(2_000_000)).cents).toBe(93_231)
    expect(proLaboreInss(Money.zero()).cents).toBe(0)
  })
})
