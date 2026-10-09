import { type LocalDate } from '@/calendar/local-date'
import { ValidationError } from '@/shared/domain-error'

export const DEVIATION_SAMPLE = 3

function median(values: readonly number[]): number {
  const sorted = [...values].sort((a, b) => a - b)
  const middle = Math.floor(sorted.length / 2)
  if (sorted.length % 2 === 1) {
    return sorted[middle] as number
  }
  return ((sorted[middle - 1] as number) + (sorted[middle] as number)) / 2
}

// Compares with the median of the latest paid amounts, newest first, so one
// odd month does not move the reference. No history means nothing to compare.
export function deviatesFromHistory(
  amountCents: number,
  paidCents: readonly number[],
  maxPercent: number | null,
): boolean {
  const recent = paidCents.slice(0, DEVIATION_SAMPLE)
  if (maxPercent === null || recent.length === 0) {
    return false
  }
  const reference = median(recent)
  return Math.abs(amountCents - reference) * 100 > reference * maxPercent
}

const CUTOFF_PATTERN = /^([01]\d|2[0-3]):[0-5]\d$/

export function assertCutoff(cutoff: string): string {
  if (!CUTOFF_PATTERN.test(cutoff)) {
    throw new ValidationError(`"${cutoff}" is not a HH:MM time.`)
  }
  return cutoff
}

// Brazil has had no daylight saving since 2019, so Sao Paulo is a fixed
// UTC-03:00 offset.
export function approvalCutoff(dueDate: LocalDate, cutoff: string): Date {
  return new Date(`${dueDate}T${assertCutoff(cutoff)}:00.000-03:00`)
}

export function approvalExpired(
  dueDate: LocalDate,
  cutoff: string,
  now: Date,
): boolean {
  return now.getTime() > approvalCutoff(dueDate, cutoff).getTime()
}
