import { type RecurringCharge } from '@/insights/recurrence'
import { type Money } from '@/money/money'

export function median(values: readonly number[]): number | null {
  if (values.length === 0) {
    return null
  }
  const sorted = [...values].sort((a, b) => a - b)
  const middle = Math.floor(sorted.length / 2)
  if (sorted.length % 2 === 1) {
    return sorted[middle] as number
  }
  return ((sorted[middle - 1] as number) + (sorted[middle] as number)) / 2
}

export type UnusualThreshold = {
  // How many times the usual amount a charge must reach.
  factor: number
  // Below this nothing is worth a push, however unusual.
  minCents: number
  // Fewer past charges than this say nothing about the usual.
  minHistory: number
}

export const UNUSUAL_PURCHASE: UnusualThreshold = {
  factor: 3,
  minCents: 20_000,
  minHistory: 3,
}

// The median, so a single past outlier does not raise the bar.
export function usualAmount(
  history: readonly number[],
  threshold: UnusualThreshold,
): number | null {
  if (history.length < threshold.minHistory) {
    return null
  }
  return median(history)
}

export function isUnusual(
  cents: number,
  usual: number | null,
  threshold: UnusualThreshold,
): boolean {
  if (usual === null || cents < threshold.minCents) {
    return false
  }
  return cents > usual * threshold.factor
}

export type AboveAverageThreshold = {
  // The share above the average that counts, 0.3 for 30%.
  share: number
  minDeltaCents: number
  minHistory: number
}

export const CARD_BILL_ABOVE_AVERAGE: AboveAverageThreshold = {
  share: 0.3,
  minDeltaCents: 10_000,
  minHistory: 3,
}

export function averageOf(values: readonly number[]): number | null {
  if (values.length === 0) {
    return null
  }
  return Math.round(
    values.reduce((sum, value) => sum + value, 0) / values.length,
  )
}

export function aboveAverage(
  cents: number,
  history: readonly number[],
  threshold: AboveAverageThreshold,
): { average: number; percent: number } | null {
  const average = averageOf(history)
  if (average === null || history.length < threshold.minHistory) {
    return null
  }
  const delta = cents - average
  if (delta < threshold.minDeltaCents || delta <= average * threshold.share) {
    return null
  }
  return { average, percent: Math.round((delta * 100) / average) }
}

export type ChargeChange =
  | { kind: 'PRICE_UP'; previous: Money; percent: number }
  | { kind: 'DUPLICATE'; month: string; count: number }

// A charge priced in a foreign currency drifts a little every month; only a
// real increase is news.
const PRICE_UP_SHARE = 0.05

export function chargeChange(charge: RecurringCharge): ChargeChange | null {
  const month = charge.lastChargeOn.slice(0, 7)
  const count = charge.charges.filter(
    entry => entry.bookedOn.slice(0, 7) === month,
  ).length
  if (count > 1) {
    return { kind: 'DUPLICATE', month, count }
  }
  const previous = charge.previousAmount
  if (!previous) {
    return null
  }
  const increase = charge.amount.cents - previous.cents
  if (increase <= previous.cents * PRICE_UP_SHARE) {
    return null
  }
  return {
    kind: 'PRICE_UP',
    previous,
    percent: Math.round((increase * 100) / previous.cents),
  }
}
