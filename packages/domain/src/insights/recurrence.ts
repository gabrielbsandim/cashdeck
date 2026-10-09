import { daysBetween, type LocalDate } from '@/calendar/local-date'
import { normalizeDescription } from '@/categories/category'
import { type Transaction } from '@/entities/transaction'
import { type Money } from '@/money/money'

export type ChargeRecord = {
  readonly transactionId: string
  readonly bookedOn: LocalDate
  readonly amount: Money
}

export type RecurringCharge = {
  readonly key: string
  readonly name: string
  readonly accountId: string
  readonly categoryId: string | null
  readonly amount: Money
  readonly previousAmount: Money | null
  readonly dayOfMonth: number
  readonly lastChargeOn: LocalDate
  readonly months: number
  readonly transactionIds: readonly string[]
  // Newest first.
  readonly charges: readonly ChargeRecord[]
}

const MIN_MONTHS = 3
// A monthly charge missing for longer than this has stopped.
const STALE_DAYS = 45
// How far the recent charges may drift from the latest one.
const MAX_DRIFT = 0.25
const RECENT_CHARGES = 3
// A metered bill (power, water, gas) changes every month; a subscription keeps
// its price between rare increases, or drifts a little with the exchange rate.
const METERED_SPREAD = 0.05

export const recurrenceKey = (transaction: Transaction) =>
  normalizeDescription(transaction.merchant ?? transaction.description)

const isPlainExpense = (transaction: Transaction) =>
  transaction.amount.isNegative() && transaction.installment === null

export function summarizeCharges(
  key: string,
  charges: readonly Transaction[],
): RecurringCharge {
  const newest = [...charges].sort((a, b) =>
    b.bookedOn.localeCompare(a.bookedOn),
  )
  const latest = newest[0] as Transaction
  const previous = newest[1] ?? null
  return {
    key,
    name: latest.merchant ?? latest.description,
    accountId: latest.accountId,
    categoryId: latest.categoryId,
    amount: latest.amount.negate(),
    previousAmount: previous ? previous.amount.negate() : null,
    dayOfMonth: Number(latest.bookedOn.slice(8, 10)),
    lastChargeOn: latest.bookedOn,
    months: new Set(newest.map(charge => charge.bookedOn.slice(0, 7))).size,
    transactionIds: newest.map(charge => charge.id),
    charges: newest.map(charge => ({
      transactionId: charge.id,
      bookedOn: charge.bookedOn,
      amount: charge.amount.negate(),
    })),
  }
}

const recentCents = (charge: RecurringCharge) =>
  charge.charges.slice(0, RECENT_CHARGES).map(other => other.amount.cents)

function steady(charge: RecurringCharge) {
  const latest = charge.amount.cents
  return recentCents(charge).every(
    cents => Math.abs(cents - latest) <= latest * MAX_DRIFT,
  )
}

function metered(charge: RecurringCharge) {
  const recent = recentCents(charge)
  const lowest = Math.min(...recent)
  const allDifferent = new Set(recent).size === recent.length
  return allDifferent && Math.max(...recent) - lowest > lowest * METERED_SPREAD
}

export function groupByRecurrence(
  transactions: readonly Transaction[],
): Map<string, Transaction[]> {
  const groups = new Map<string, Transaction[]>()
  for (const transaction of transactions.filter(isPlainExpense)) {
    const key = recurrenceKey(transaction)
    if (key === '') {
      continue
    }
    groups.set(key, [...(groups.get(key) ?? []), transaction])
  }
  return groups
}

// Steady monthly charges seen in three or more months and still running. A
// metered utility bill recurs too, but it is a bill, not a subscription.
export function detectRecurring(
  transactions: readonly Transaction[],
  day: LocalDate,
): RecurringCharge[] {
  return [...groupByRecurrence(transactions)].flatMap(([key, charges]) => {
    const charge = summarizeCharges(key, charges)
    const monthly = charges.length <= charge.months + 1
    const running = daysBetween(charge.lastChargeOn, day) <= STALE_DAYS
    const recurring =
      charge.months >= MIN_MONTHS &&
      monthly &&
      running &&
      steady(charge) &&
      !metered(charge)
    return recurring ? [charge] : []
  })
}
