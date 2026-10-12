import { Money } from '@/money/money'
import { ValidationError } from '@/shared/domain-error'

export type Budget = {
  readonly id: string
  readonly tenantId: string
  readonly entityId: string
  readonly categoryId: string
  // YYYY-MM.
  readonly month: string
  readonly limit: Money
  // Leftover of the month before, added on top of the limit by a rollover.
  readonly carried: Money
  readonly rollover: boolean
}

export const BUDGET_LEVELS = ['OK', 'NEAR', 'REACHED'] as const
export type BudgetLevel = (typeof BUDGET_LEVELS)[number]

export const BUDGET_NEAR_PERCENT = 80
export const BUDGET_REACHED_PERCENT = 100

const MONTH_PATTERN = /^\d{4}-(0[1-9]|1[0-2])$/

export function isMonth(value: string): boolean {
  return MONTH_PATTERN.test(value)
}

export function createBudget(
  input: Omit<Budget, 'carried'> & { carried?: Money },
): Budget {
  if (!isMonth(input.month)) {
    throw new ValidationError(`"${input.month}" is not a YYYY-MM month.`)
  }
  if (!input.limit.isPositive()) {
    throw new ValidationError('A budget needs a positive limit.')
  }
  const carried = input.carried ?? Money.zero(input.limit.currency)
  if (carried.isNegative()) {
    throw new ValidationError('A budget cannot carry a negative leftover.')
  }
  return { ...input, carried }
}

export const budgetAvailable = (budget: Budget): Money =>
  budget.limit.add(budget.carried)

export type BudgetUsage = {
  readonly available: Money
  // Negative once the spending passes the limit.
  readonly remaining: Money
  readonly percent: number
  readonly level: BudgetLevel
}

export function budgetLevel(percent: number): BudgetLevel {
  if (percent >= BUDGET_REACHED_PERCENT) {
    return 'REACHED'
  }
  return percent >= BUDGET_NEAR_PERCENT ? 'NEAR' : 'OK'
}

// Nothing available reads as nothing used, so an empty month shows no alarm.
export function spendingUsage(available: Money, spent: Money): BudgetUsage {
  const percent = available.isPositive()
    ? Math.max(0, Math.floor((spent.cents * 100) / available.cents))
    : 0
  return {
    available,
    remaining: available.subtract(spent),
    percent,
    level: budgetLevel(percent),
  }
}

export const budgetUsage = (budget: Budget, spent: Money): BudgetUsage =>
  spendingUsage(budgetAvailable(budget), spent)

// The highest threshold the spending crossed: one alert per step, never two
// for the same jump.
export function crossedThreshold(percent: number): 80 | 100 | null {
  if (percent >= BUDGET_REACHED_PERCENT) {
    return BUDGET_REACHED_PERCENT
  }
  return percent >= BUDGET_NEAR_PERCENT ? BUDGET_NEAR_PERCENT : null
}

// The same limit a month later; a rollover carries what was left, never an
// overspend.
export function rolloverInto(
  budget: Budget,
  spent: Money,
  next: { id: string; month: string },
): Budget {
  const left = budgetAvailable(budget).subtract(spent)
  const carried =
    budget.rollover && left.isPositive()
      ? left
      : Money.zero(budget.limit.currency)
  return createBudget({ ...budget, ...next, carried })
}

export function medianCents(values: readonly number[]): number {
  if (values.length === 0) {
    return 0
  }
  const sorted = [...values].sort((a, b) => a - b)
  const middle = Math.floor(sorted.length / 2)
  if (sorted.length % 2 === 1) {
    return sorted[middle] as number
  }
  return Math.round(
    ((sorted[middle - 1] as number) + (sorted[middle] as number)) / 2,
  )
}

// Rounded up to a step that reads well: R$ 10 under R$ 100, R$ 50 under
// R$ 1.000, R$ 100 above.
const FRIENDLY_STEPS = [
  { below: 10_000, step: 1_000 },
  { below: 100_000, step: 5_000 },
  { below: Number.POSITIVE_INFINITY, step: 10_000 },
] as const

export function friendlyCents(cents: number): number {
  if (cents <= 0) {
    return 0
  }
  const { step } = FRIENDLY_STEPS.find(
    candidate => cents < candidate.below,
  ) as (typeof FRIENDLY_STEPS)[number]
  return Math.ceil(cents / step) * step
}

// A limit from the spending of past months: their median, rounded up.
export function suggestLimit(monthTotals: readonly number[]): Money {
  return Money.of(friendlyCents(medianCents(monthTotals)))
}
