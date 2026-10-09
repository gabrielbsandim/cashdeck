import { type LocalDate } from '@/calendar/local-date'
import { type Money } from '@/money/money'

export const FUNDING_STATUSES = [
  'IN_FLIGHT',
  'SUBMITTED',
  'PAID',
  'NOT_NEEDED',
  'FAILED',
] as const
export type FundingStatus = (typeof FUNDING_STATUSES)[number]

// One round moves the shortfall of a set of bills from the personal reserve to
// the account that pays them; a later round of the same day covers late bills.
export type ReserveFunding = {
  readonly id: string
  readonly tenantId: string
  readonly entityId: string
  readonly day: LocalDate
  readonly round: number
  readonly billIds: readonly string[]
  readonly billsTotal: Money
  readonly available: Money | null
  readonly amount: Money
  readonly status: FundingStatus
  readonly reason: string | null
  readonly externalId: string | null
  readonly idempotencyKey: string
  readonly at: Date
}

export function fundingKey(
  entityId: string,
  day: LocalDate,
  round: number,
): string {
  return `reserve:${entityId}:${day}:${round}`
}

export function fundingShortfall(
  billsCents: number,
  availableCents: number,
): number {
  return Math.max(0, billsCents - Math.max(0, availableCents))
}

const FUNDED: readonly FundingStatus[] = ['SUBMITTED', 'PAID', 'NOT_NEEDED']

export function isFunded(status: FundingStatus): boolean {
  return FUNDED.includes(status)
}

// The latest round that names the bill decides whether it may be paid.
export function fundingFor(
  rounds: readonly ReserveFunding[],
  billId: string,
): ReserveFunding | null {
  return rounds.filter(round => round.billIds.includes(billId)).at(-1) ?? null
}
