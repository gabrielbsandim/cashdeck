import { describe, expect, it } from 'vitest'
import { Money } from '@/money/money'
import { ValidationError } from '@/shared/domain-error'

describe('Money', () => {
  it('defaults to BRL and validates its input', () => {
    expect(Money.of(150).currency).toBe('BRL')
    expect(Money.zero('USD').toJSON()).toEqual({ cents: 0, currency: 'USD' })
    expect(() => Money.of(1.5)).toThrow(ValidationError)
    expect(() => Money.of(1, 'real')).toThrow('ISO 4217')
  })

  it('parses decimal strings', () => {
    expect(Money.fromDecimal('12.3').cents).toBe(1230)
    expect(Money.fromDecimal('0.05').cents).toBe(5)
    expect(Money.fromDecimal('-7').cents).toBe(-700)
    expect(Money.fromDecimal(' 1.99 ', 'EUR').toJSON()).toEqual({
      cents: 199,
      currency: 'EUR',
    })
    expect(() => Money.fromDecimal('1,50')).toThrow(ValidationError)
  })

  it('does arithmetic within one currency', () => {
    const a = Money.of(1000)
    const b = Money.of(250)
    expect(a.add(b).cents).toBe(1250)
    expect(b.subtract(a).cents).toBe(-750)
    expect(a.negate().isNegative()).toBe(true)
    expect(() => a.add(Money.of(1, 'USD'))).toThrow(
      'Cannot combine BRL with USD.',
    )
  })

  it('compares and inspects amounts', () => {
    expect(Money.of(1).compare(Money.of(2))).toBe(-1)
    expect(Money.of(2).compare(Money.of(2))).toBe(0)
    expect(Money.of(3).compare(Money.of(2))).toBe(1)
    expect(Money.zero().isZero()).toBe(true)
    expect(Money.of(5).isPositive()).toBe(true)
    expect(Money.of(5).equals(Money.of(5))).toBe(true)
    expect(Money.of(5).equals(Money.of(5, 'USD'))).toBe(false)
  })

  it('renders a decimal string', () => {
    expect(Money.of(123456).toDecimal()).toBe('1234.56')
    expect(Money.of(-5).toDecimal()).toBe('-0.05')
  })
})
