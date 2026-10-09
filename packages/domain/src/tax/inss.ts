import { Money } from '@/money/money'

// The partner's 11% on the pro-labore stops at the 2026 contribution ceiling
// (Portaria Interministerial MPS/MF 13/2026).
export const INSS_PRO_LABORE_RATE = 0.11
export const INSS_CEILING_CENTS = 847_555

export function proLaboreInss(proLabore: Money): Money {
  const base = Math.min(Math.max(proLabore.cents, 0), INSS_CEILING_CENTS)
  return Money.of(Math.round(base * INSS_PRO_LABORE_RATE), proLabore.currency)
}
