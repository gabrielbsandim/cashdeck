import { describe, expect, it } from 'vitest'
import { Money } from '@/money/money'
import {
  annexFor,
  dasDueDate,
  effectiveRate,
  estimateDas,
  fatorR,
} from '@/tax/simples'

const reais = (value: number) => Money.of(value * 100)

describe('Fator R', () => {
  it('picks Annex III at 28% of payroll over revenue, else V', () => {
    expect(fatorR(reais(28_000), reais(100_000))).toBeCloseTo(0.28)
    expect(fatorR(reais(1), Money.zero())).toBe(0)
    expect(annexFor(reais(28_000), reais(100_000))).toBe('III')
    expect(annexFor(reais(27_999), reais(100_000))).toBe('V')
  })
})

describe('effectiveRate', () => {
  it('uses the nominal rate in the first bracket and without history', () => {
    expect(effectiveRate('III', Money.zero())).toBe(0.06)
    expect(effectiveRate('III', reais(120_000))).toBeCloseTo(0.06)
    expect(effectiveRate('V', reais(100_000))).toBeCloseTo(0.155)
  })

  it('subtracts the deduction in higher brackets', () => {
    expect(effectiveRate('III', reais(360_000))).toBeCloseTo(0.086)
    expect(effectiveRate('V', reais(720_000))).toBeCloseTo(0.18125)
    expect(effectiveRate('III', reais(9_000_000))).toBeCloseTo(0.258)
  })
})

describe('estimateDas', () => {
  it('spares exports from ISS, PIS and COFINS', () => {
    expect(
      estimateDas({
        annex: 'III',
        rbt12: reais(120_000),
        domestic: reais(10_000),
        exports: Money.zero(),
      }).cents,
    ).toBe(60_000)
    expect(
      estimateDas({
        annex: 'III',
        rbt12: reais(120_000),
        domestic: Money.zero(),
        exports: reais(10_000),
      }).cents,
    ).toBe(30_540)
  })
})

describe('dasDueDate', () => {
  it('falls on the 20th of the next month or the business day before', () => {
    expect(dasDueDate('2026-09')).toBe('2026-10-20')
    expect(dasDueDate('2026-10')).toBe('2026-11-19')
    expect(dasDueDate('2026-11')).toBe('2026-12-18')
    expect(dasDueDate('2026-12')).toBe('2027-01-20')
  })
})
