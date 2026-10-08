import { describe, expect, it } from 'vitest'

import {
  calculateCostMillicents,
  formatMillicentsBrl4Decimals,
  millicentsToBrl,
  millicentsToReais,
} from '@/llm/pricing'

describe('calculateCostMillicents', () => {
  it('returns 0 for unknown models', () => {
    expect(
      calculateCostMillicents({
        modelId: 'unknown',
        inputTokens: 1_000,
        outputTokens: 1_000,
      }),
    ).toBe(0)
  })

  it('computes Gemini 2.5 Flash cost using default BRL/USD rate', () => {
    const millicents = calculateCostMillicents({
      modelId: 'gemini-2.5-flash',
      inputTokens: 1_000_000,
      outputTokens: 1_000_000,
    })
    expect(millicents).toBe(1_400_000)
  })

  it('honors a custom BRL/USD rate', () => {
    const millicents = calculateCostMillicents({
      modelId: 'gemini-2.5-flash',
      inputTokens: 1_000_000,
      outputTokens: 0,
      brlPerUsd: 6,
    })
    expect(millicents).toBe(180_000)
  })

  it('prices Gemini 2.5 Flash-Lite (so the kill switch can trip)', () => {
    const millicents = calculateCostMillicents({
      modelId: 'gemini-2.5-flash-lite',
      inputTokens: 1_000_000,
      outputTokens: 1_000_000,
    })
    expect(millicents).toBe(250_000)
  })

  it('strips a gateway provider prefix before the pricing lookup', () => {
    const prefixed = calculateCostMillicents({
      modelId: 'google/gemini-2.5-flash-lite',
      inputTokens: 1_000_000,
      outputTokens: 1_000_000,
    })
    expect(prefixed).toBe(250_000)
  })

  it('keeps a call worth a fraction of a cent, which used to round to zero', () => {
    expect(
      calculateCostMillicents({
        modelId: 'gemini-2.5-flash',
        inputTokens: 1_000,
        outputTokens: 1_000,
      }),
    ).toBe(1_400)
    expect(
      calculateCostMillicents({
        modelId: 'gemini-2.5-flash',
        inputTokens: 100,
        outputTokens: 0,
      }),
    ).toBe(15)
  })

  it('still rounds, one thousandth of a cent down', () => {
    expect(
      calculateCostMillicents({
        modelId: 'gemini-2.5-flash',
        inputTokens: 1,
        outputTokens: 0,
      }),
    ).toBe(0)
  })
})

describe('millicentsToBrl', () => {
  it('formats the unit the columns store back into reais', () => {
    expect(millicentsToBrl(1_400_000)).toBe('14.00')
    expect(millicentsToBrl(3_000)).toBe('0.03')
  })

  it('shows nothing rather than a wrong number below a centavo', () => {
    expect(millicentsToBrl(15)).toBe('0.00')
  })
})

describe('millicentsToReais', () => {
  it('carries the factor the two string formatters share', () => {
    expect(millicentsToReais(1_400_000)).toBe(14)
    expect(millicentsToReais(1234)).toBeCloseTo(0.01234, 10)
    expect(millicentsToReais(0)).toBe(0)
  })
})

describe('formatMillicentsBrl4Decimals', () => {
  it('keeps an amount below a centavo readable, where two decimals cannot', () => {
    expect(format4(1234)).toBe('R$ 0,0123')
    expect(format4(15)).toBe('R$ 0,0002')
    expect(millicentsToBrl(15)).toBe('0.00')
  })

  it('formats a whole month of every company together', () => {
    expect(format4(79_940)).toBe('R$ 0,7994')
  })

  it('formats zero without inventing a value', () => {
    expect(format4(0)).toBe('R$ 0,0000')
  })
})

function format4(millicents: number): string {
  return formatMillicentsBrl4Decimals(millicents).replace(/\u00a0/g, ' ')
}
