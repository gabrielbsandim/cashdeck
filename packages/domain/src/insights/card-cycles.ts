import {
  addDays,
  type LocalDate,
  localDate,
  shiftMonth,
} from '@/calendar/local-date'
import { type Transaction } from '@/entities/transaction'
import {
  type InstallmentPlan,
  remainingInstallments,
} from '@/insights/installments'
import { Money } from '@/money/money'

// The booking days one card bill holds and the day it is due.
export type BillCycle = {
  readonly from: LocalDate
  readonly closesOn: LocalDate
  readonly dueOn: LocalDate
}

// One installment a plan has still to charge, on the bill that will carry it.
export type ProjectedInstallment = {
  readonly key: string
  readonly name: string
  readonly categoryId: string | null
  readonly number: number
  readonly count: number
  readonly amount: Money
}

export const BILL_PAYMENTS = ['PAID', 'DUE', 'UNCONFIRMED'] as const
export type BillPayment = (typeof BILL_PAYMENTS)[number]

// Issuers post a payment from a few days before the closing day to some days
// after the due date, when it clears.
const PAYMENT_LEAD_DAYS = 5
const PAYMENT_GRACE_DAYS = 10

// The same day of `day` in a month `months` later, kept inside short months.
function dayLater(day: LocalDate, months: number): LocalDate {
  const month = shiftMonth(day.slice(0, 7), months)
  const [year, value] = month.split('-').map(Number) as [number, number]
  const last = localDate(year, value + 1, 0)
  const same = `${month}-${day.slice(8)}`
  return same < last ? same : last
}

export const cycleHolds = (cycle: BillCycle, day: LocalDate) =>
  cycle.from <= day && day <= cycle.closesOn

// The cycles after `cycle`, closing and due on the same days of later months.
export function cyclesAfter(cycle: BillCycle, count: number): BillCycle[] {
  return Array.from({ length: count }, (_, index) => ({
    from: addDays(dayLater(cycle.closesOn, index), 1),
    closesOn: dayLater(cycle.closesOn, index + 1),
    dueOn: dayLater(cycle.dueOn, index + 1),
  }))
}

// What the charges booked inside a cycle add up to, refunds left out.
export function chargesIn(
  cycle: BillCycle,
  transactions: readonly Transaction[],
): Money {
  const cents = transactions
    .filter(
      transaction =>
        transaction.amount.isNegative() &&
        cycleHolds(cycle, transaction.bookedOn),
    )
    .reduce((sum, transaction) => sum - transaction.amount.cents, 0)
  return Money.of(cents)
}

// Each plan charges once per bill, so the installment after the latest one
// lands on the cycle after the one holding it. `cycles` go oldest first.
export function projectInstallments(
  plans: readonly InstallmentPlan[],
  cycles: readonly BillCycle[],
): ProjectedInstallment[][] {
  const projected = cycles.map((): ProjectedInstallment[] => [])
  for (const plan of plans) {
    const holder = cycles.findIndex(cycle =>
      cycleHolds(cycle, plan.lastBilledOn),
    )
    if (holder < 0) {
      continue
    }
    for (let ahead = 1; ahead <= remainingInstallments(plan); ahead++) {
      projected[holder + ahead]?.push({
        key: plan.key,
        name: plan.name,
        categoryId: plan.categoryId,
        number: plan.number + ahead,
        count: plan.count,
        amount: plan.amount,
      })
    }
  }
  return projected
}

// Paid when the credits posted to the card around its dates cover the bill.
export function billPayment(
  cycle: BillCycle,
  total: Money,
  transactions: readonly Transaction[],
  day: LocalDate,
): BillPayment {
  const from = addDays(cycle.closesOn, -PAYMENT_LEAD_DAYS)
  const to = addDays(cycle.dueOn, PAYMENT_GRACE_DAYS)
  const paid = transactions
    .filter(
      transaction =>
        transaction.amount.isPositive() &&
        transaction.bookedOn >= from &&
        transaction.bookedOn <= to,
    )
    .reduce((sum, transaction) => sum + transaction.amount.cents, 0)
  if (paid >= total.cents) {
    return 'PAID'
  }
  return day <= cycle.dueOn ? 'DUE' : 'UNCONFIRMED'
}
