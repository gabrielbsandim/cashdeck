import { shiftMonth, type LocalDate } from '@/calendar/local-date'
import { type Installment, type Transaction } from '@/entities/transaction'
import { Money } from '@/money/money'

// One card purchase split into installments, as far as the bills show it.
export type InstallmentPlan = {
  readonly key: string
  readonly accountId: string
  readonly name: string
  readonly categoryId: string | null
  // The latest installment billed so far, 1 to count.
  readonly number: number
  readonly count: number
  readonly amount: Money
  readonly purchaseOn: LocalDate | null
  readonly lastBilledOn: LocalDate
  readonly transactionIds: readonly string[]
}

// Banks print the counter in the description ("PARC 03/10"), which would
// split one purchase into a plan per month.
export function purchaseName(description: string): string {
  return description
    .replace(/\b(parc(ela)?\.?\s*)?\d{1,2}\s*(\/|de)\s*\d{1,2}\b/gi, '')
    .replace(/\s{2,}/g, ' ')
    .trim()
}

const installmentOf = (transaction: Transaction) =>
  transaction.installment as Installment

function planKey(transaction: Transaction): string {
  const installment = installmentOf(transaction)
  const origin =
    installment.purchaseOn ??
    purchaseName(transaction.merchant ?? transaction.description).toLowerCase()
  return [
    transaction.accountId,
    origin,
    installment.count,
    -transaction.amount.cents,
  ].join('|')
}

const isCharge = (transaction: Transaction) =>
  transaction.installment !== null && transaction.amount.isNegative()

export function groupInstallments(
  transactions: readonly Transaction[],
): InstallmentPlan[] {
  const groups = new Map<string, Transaction[]>()
  for (const transaction of transactions.filter(isCharge)) {
    const key = planKey(transaction)
    groups.set(key, [...(groups.get(key) ?? []), transaction])
  }
  return [...groups].map(([key, charges]) => {
    const ordered = [...charges].sort(
      (a, b) =>
        installmentOf(b).number - installmentOf(a).number ||
        b.bookedOn.localeCompare(a.bookedOn),
    )
    const latest = ordered[0] as Transaction
    const installment = installmentOf(latest)
    return {
      key,
      accountId: latest.accountId,
      name: purchaseName(latest.merchant ?? latest.description),
      categoryId: latest.categoryId,
      number: installment.number,
      count: installment.count,
      amount: latest.amount.negate(),
      purchaseOn: installment.purchaseOn,
      lastBilledOn: latest.bookedOn,
      transactionIds: ordered.map(charge => charge.id),
    }
  })
}

export const remainingInstallments = (plan: InstallmentPlan) =>
  plan.count - plan.number

// The month of the last installment, counting one per month from the latest.
export function finalMonth(plan: InstallmentPlan): string {
  return shiftMonth(plan.lastBilledOn.slice(0, 7), remainingInstallments(plan))
}

// What the plans still charge in each month, from `from` on.
export function committedByMonth(
  plans: readonly InstallmentPlan[],
  from: string,
  months: number,
): Array<{ month: string; amount: Money }> {
  return Array.from({ length: months }, (_, index) => {
    const month = shiftMonth(from, index)
    const cents = plans
      .filter(plan => {
        const billed = plan.lastBilledOn.slice(0, 7)
        return month > billed && month <= finalMonth(plan)
      })
      .reduce((total, plan) => total + plan.amount.cents, 0)
    return { month, amount: Money.of(cents) }
  })
}
