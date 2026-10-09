import { describe, expect, it } from 'vitest'
import { Money } from '@/money/money'
import {
  annexFor,
  dasDueDate,
  effectiveRate,
  estimateDas,
  fatorR,
  issRate,
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

describe('issRate', () => {
  it('takes the ISS share of the effective rate', () => {
    expect(issRate('III', Money.of(19_183_166))).toBeCloseTo(0.020226, 6)
    expect(issRate('III', reais(120_000))).toBeCloseTo(0.0201)
    expect(issRate('V', reais(100_000))).toBeCloseTo(0.0217)
  })

  it('caps at 5% and leaves the last bracket to the city', () => {
    expect(issRate('III', reais(3_500_000))).toBe(0.05)
    expect(issRate('III', reais(4_000_000))).toBeNull()
  })
})

describe('estimateDas', () => {
  const das = (input: Partial<Parameters<typeof estimateDas>[0]>) =>
    estimateDas({
      annex: 'III',
      domesticRbt12: reais(120_000),
      exportRbt12: Money.zero(),
      domestic: Money.zero(),
      exports: Money.zero(),
      ...input,
    }).cents

  it('spares exports from ISS, PIS and COFINS', () => {
    expect(das({ domestic: reais(10_000) })).toBe(60_000)
    expect(das({ exports: reais(10_000) })).toBe(30_540)
  })

  it('finds each market rate from its own RBT12', () => {
    expect(
      das({ domesticRbt12: reais(360_000), domestic: reais(10_000) }),
    ).toBe(86_000)
    expect(das({ exportRbt12: reais(360_000), exports: reais(10_000) })).toBe(
      43_774,
    )
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
