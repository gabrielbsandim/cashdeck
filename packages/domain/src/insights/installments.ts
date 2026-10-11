import { localDate, shiftMonth, type LocalDate } from '@/calendar/local-date'
import { type Installment, type Transaction } from '@/entities/transaction'
import { Money } from '@/money/money'

// One card purchase split into installments, as far as the bills show it.
export type InstallmentPlan = {
  readonly key: string
  readonly accountId: string
  readonly name: string
  readonly categoryId: string | null
  // The latest installment billed so far, 1 to count, including the ones a
  // statement the bank never sent must have carried.
  readonly number: number
  readonly count: number
  readonly amount: Money
  readonly purchaseOn: LocalDate | null
  readonly lastBilledOn: LocalDate
  readonly transactionIds: readonly string[]
  // Billed installments no imported charge shows.
  readonly missing: readonly number[]
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

function planBase(transaction: Transaction): string {
  const installment = installmentOf(transaction)
  const origin =
    installment.purchaseOn ??
    purchaseName(transaction.merchant ?? transaction.description).toLowerCase()
  return [transaction.accountId, origin, installment.count].join('|')
}

const isCharge = (transaction: Transaction) =>
  transaction.installment !== null && transaction.amount.isNegative()

type PlanGroup = {
  key: string
  base: string
  cents: number
  charges: Transaction[]
}

const monthIndex = (date: LocalDate) => {
  const [year, month] = date.split('-').map(Number) as [number, number]
  return year * 12 + month
}

function shiftDate(date: LocalDate, months: number): LocalDate {
  const [year, month, day] = date.split('-').map(Number) as [
    number,
    number,
    number,
  ]
  return localDate(year, month + months, Math.min(day, 28))
}

// The first installment is booked on the purchase day; every later one on the
// statement's posting day, so those mark the months each card was billed.
function billedMonths(charges: readonly Transaction[]): Map<string, number> {
  const months = new Map<string, number>()
  for (const charge of charges.filter(item => installmentOf(item).number > 1)) {
    const month = monthIndex(charge.bookedOn)
    months.set(
      charge.accountId,
      Math.max(months.get(charge.accountId) ?? 0, month),
    )
  }
  return months
}

function joinableGroup(
  groups: readonly PlanGroup[],
  transaction: Transaction,
  base: string,
  cents: number,
): PlanGroup | undefined {
  const installment = installmentOf(transaction)
  // Splitting a price leaves under a cent per installment on one of them, and a
  // second charge of the same number is a second purchase at that price.
  return groups.find(
    item =>
      item.base === base &&
      Math.abs(item.cents - cents) < installment.count &&
      !item.charges.some(
        charge => installmentOf(charge).number === installment.number,
      ),
  )
}

// A later statement on the same card billed every running plan, so a gap means
// the bank left statements out. A first installment sits on the purchase day,
// which may fall after that statement closed, so it proves nothing.
function skippedStatements(
  latest: Transaction,
  billed: ReadonlyMap<string, number>,
): number {
  if (installmentOf(latest).number === 1) {
    return 0
  }
  const last = billed.get(latest.accountId) as number
  return last - monthIndex(latest.bookedOn)
}

function toPlan(
  { key, charges }: PlanGroup,
  billed: ReadonlyMap<string, number>,
): InstallmentPlan {
  const ordered = [...charges].sort(
    (a, b) => installmentOf(b).number - installmentOf(a).number,
  )
  const latest = ordered[0] as Transaction
  const installment = installmentOf(latest)
  const skipped = skippedStatements(latest, billed)
  const number = Math.min(installment.count, installment.number + skipped)
  const seen = new Set(ordered.map(charge => installmentOf(charge).number))
  const first = Math.min(...seen)
  return {
    key,
    accountId: latest.accountId,
    name: purchaseName(latest.merchant ?? latest.description),
    categoryId: latest.categoryId,
    number,
    count: installment.count,
    amount: latest.amount.negate(),
    purchaseOn: installment.purchaseOn,
    lastBilledOn: shiftDate(latest.bookedOn, number - installment.number),
    transactionIds: ordered.map(charge => charge.id),
    missing: Array.from(
      { length: number - first + 1 },
      (_, index) => first + index,
    ).filter(value => !seen.has(value)),
  }
}

export function groupInstallments(
  transactions: readonly Transaction[],
): InstallmentPlan[] {
  const charges = transactions.filter(isCharge)
  const groups: PlanGroup[] = []
  for (const transaction of charges) {
    const base = planBase(transaction)
    const cents = -transaction.amount.cents
    const group = joinableGroup(groups, transaction, base, cents)
    if (group) {
      group.charges.push(transaction)
      continue
    }
    const twins = groups.filter(
      item => item.base === base && item.cents === cents,
    ).length
    groups.push({
      key: twins === 0 ? `${base}|${cents}` : `${base}|${cents}|${twins + 1}`,
      base,
      cents,
      charges: [transaction],
    })
  }
  const billed = billedMonths(charges)
  return groups.map(group => toPlan(group, billed))
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
