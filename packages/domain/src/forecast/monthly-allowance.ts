import { daysBetween, type LocalDate } from '@/calendar/local-date'
import {
  type BudgetLeft,
  budgetLines,
  dailyOf,
  lastDayOfMonth,
  type Obligation,
  obligationLines,
  reserveLines,
  type SafeToSpend,
  type SafeToSpendLine,
  shortfallOf,
} from '@/forecast/safe-to-spend'
import { median } from '@/insights/anomalies'
import { Money } from '@/money/money'

// What came in and went out in one closed month, in cents.
export type MonthFlow = {
  readonly month: string
  readonly income: number
  readonly expenses: number
}

export type TypicalMonth = {
  readonly income: Money
  // What a month usually leaves over, the savings target until one is set.
  readonly saved: Money
  readonly months: number
}

export type MonthlyAllowanceInput = {
  readonly today: LocalDate
  readonly income: Money
  readonly savings: Money
  // Spent since the month began, by purchase date, card bills left out.
  readonly spentOnCards: Money
  readonly spentFromAccounts: Money
  // The part of that spending booked today.
  readonly spentToday?: Money
  // Still to be paid this month; one overdue and unpaid counts as well.
  readonly obligations: readonly Obligation[]
  readonly budgets?: readonly BudgetLeft[]
}

export type MonthlyAllowance = Omit<SafeToSpend, 'income'>

export type CashShortfallInput = {
  readonly until: LocalDate
  readonly cash: Money
  readonly reserve: Money
  readonly obligations: readonly Obligation[]
}

const sum = (amounts: readonly Money[]) =>
  amounts.reduce((total, amount) => total.add(amount), Money.zero())

// The median month, so a bonus or an unnamed move from an own account in one
// month moves nothing.
export function typicalMonth(
  history: readonly MonthFlow[],
): TypicalMonth | null {
  if (history.length === 0) {
    return null
  }
  const middle = (values: number[]) => Math.round(median(values) as number)
  const left = middle(history.map(month => month.income - month.expenses))
  return {
    income: Money.of(middle(history.map(month => month.income))),
    saved: Money.of(Math.max(0, left)),
    months: history.length,
  }
}

const planLine = (
  kind: SafeToSpendLine['kind'],
  amount: Money,
): SafeToSpendLine => ({ kind, label: '', amount, on: null })

// Today's share is set as the day began, so each purchase today takes its
// whole amount off what is left for today instead of a fraction of it.
function leftToday(total: Money, days: number, spentToday: Money) {
  const share = dailyOf(total.add(spentToday), days)
  return share.compare(spentToday) > 0
    ? share.subtract(spentToday)
    : Money.zero()
}

// The typical income less the savings target, what the month already spent
// and what it still owes; spread over the days left in the month.
export function monthlyAllowance(
  input: MonthlyAllowanceInput,
): MonthlyAllowance {
  const until = lastDayOfMonth(input.today)
  const days = daysBetween(input.today, until) + 1
  const due = input.obligations.filter(obligation => obligation.on <= until)
  const lines = [
    planLine('INCOME', input.income),
    planLine('SAVINGS', input.savings.negate()),
    planLine('SPENT_CARD', input.spentOnCards.negate()),
    planLine('SPENT_ACCOUNT', input.spentFromAccounts.negate()),
    ...obligationLines(due),
    ...budgetLines(input.budgets ?? [], input.today, days),
  ]
  const total = sum(lines.map(line => line.amount))
  return {
    total,
    daily: leftToday(total, days, input.spentToday ?? Money.zero()),
    days,
    until,
    shortBy: shortfallOf(total),
    lines,
  }
}

// What the checking balance and the reserve leave unpaid of what falls due by
// `until`, income left out since its day is not known.
export function cashShortfall(input: CashShortfallInput): Money {
  const due = input.obligations.filter(
    obligation => obligation.on <= input.until,
  )
  const lines = [...obligationLines(due), ...reserveLines(due, input.reserve)]
  return shortfallOf(input.cash.add(sum(lines.map(line => line.amount))))
}
