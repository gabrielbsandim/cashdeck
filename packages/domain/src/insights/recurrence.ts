import { daysBetween, type LocalDate } from '@/calendar/local-date'
import { normalizeDescription } from '@/categories/category'
import { type Transaction } from '@/entities/transaction'
import { type Money } from '@/money/money'

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
}

const MIN_MONTHS = 3
// A monthly charge missing for longer than this has stopped.
const STALE_DAYS = 45
// How far the recent charges may drift from the latest one.
const MAX_DRIFT = 0.25
const RECENT_CHARGES = 3

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
  }
}

function steady(charge: RecurringCharge, charges: readonly Transaction[]) {
  const latest = charge.amount.cents
  return [...charges]
    .sort((a, b) => b.bookedOn.localeCompare(a.bookedOn))
    .slice(0, RECENT_CHARGES)
    .every(
      other => Math.abs(-other.amount.cents - latest) <= latest * MAX_DRIFT,
    )
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

// Charges seen in three or more months, about once a month, at a steady
// price and still running.
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
      steady(charge, charges)
    return recurring ? [charge] : []
  })
}
