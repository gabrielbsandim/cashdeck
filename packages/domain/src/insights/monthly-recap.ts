import { type LocalDate, shiftMonth } from '@/calendar/local-date'
import { isMonth } from '@/planning/budget'
import { ValidationError } from '@/shared/domain-error'

// Below this a category move is noise, not something worth a story card.
export const RECAP_SHIFT_MIN_CENTS = 5_000
export const RECAP_TOP_SHIFTS = 3

export type CentsChange = {
  readonly cents: number
  // Null when there is nothing to compare with.
  readonly percent: number | null
}

export type RecapFlow = {
  readonly income: number
  readonly expenses: number
  readonly net: number
}

export type CategorySpend = {
  readonly categoryId: string
  readonly cents: number
}

export type CategoryShift = {
  readonly categoryId: string
  readonly cents: number
  readonly previousCents: number
  readonly change: CentsChange
}

export type RecapSubscription = {
  readonly key: string
  readonly name: string
  readonly cents: number
  // YYYY-MM of every charge seen.
  readonly chargedMonths: readonly string[]
}

export type MonthlyRecapInput = {
  readonly month: string
  readonly flow: { readonly income: number; readonly expenses: number }
  readonly previousFlow: { readonly income: number; readonly expenses: number }
  readonly categories: readonly CategorySpend[]
  readonly previousCategories: readonly CategorySpend[]
  readonly subscriptions: readonly RecapSubscription[]
  readonly netWorth: {
    readonly end: number
    readonly previousEnd: number
  } | null
}

export type MonthlyRecapFacts = {
  readonly month: string
  readonly flow: RecapFlow
  readonly previousFlow: RecapFlow
  readonly incomeChange: CentsChange
  readonly expensesChange: CentsChange
  readonly savingsPercent: number | null
  readonly previousSavingsPercent: number | null
  readonly topCategory:
    | (CategorySpend & { readonly sharePercent: number })
    | null
  readonly rose: readonly CategoryShift[]
  readonly fell: readonly CategoryShift[]
  readonly started: readonly RecapSubscription[]
  readonly stopped: readonly RecapSubscription[]
  readonly netWorth: {
    readonly end: number
    readonly change: CentsChange
  } | null
}

// The month a recap covers on a given day: the last one that closed.
export function closedMonthOf(day: LocalDate): string {
  return shiftMonth(day.slice(0, 7), -1)
}

export function requireClosedMonth(month: string, day: LocalDate): string {
  if (!isMonth(month)) {
    throw new ValidationError(`"${month}" is not a YYYY-MM month.`)
  }
  if (month > closedMonthOf(day)) {
    throw new ValidationError('A recap covers a month that already closed.')
  }
  return month
}

export function centsChange(current: number, previous: number): CentsChange {
  const cents = current - previous
  if (previous === 0) {
    return { cents, percent: null }
  }
  return { cents, percent: Math.round((cents * 100) / Math.abs(previous)) }
}

// Share of the income kept; null without income, negative when it ran short.
export function savingsPercent(flow: RecapFlow): number | null {
  if (flow.income <= 0) {
    return null
  }
  return Math.round((flow.net * 100) / flow.income)
}

const flowOf = (flow: MonthlyRecapInput['flow']): RecapFlow => ({
  ...flow,
  net: flow.income - flow.expenses,
})

// The share is of everything spent in the month, uncategorized included.
export function topCategory(
  categories: readonly CategorySpend[],
  expenses: number,
): MonthlyRecapFacts['topCategory'] {
  const [top] = [...categories]
    .filter(item => item.cents > 0)
    .sort((a, b) => b.cents - a.cents)
  if (!top) {
    return null
  }
  const whole = Math.max(expenses, top.cents)
  return { ...top, sharePercent: Math.round((top.cents * 100) / whole) }
}

export function categoryShifts(
  current: readonly CategorySpend[],
  previous: readonly CategorySpend[],
): { rose: CategoryShift[]; fell: CategoryShift[] } {
  const now = new Map(current.map(item => [item.categoryId, item.cents]))
  const before = new Map(previous.map(item => [item.categoryId, item.cents]))
  const shifts = [...new Set([...now.keys(), ...before.keys()])]
    .map(categoryId => {
      const cents = now.get(categoryId) ?? 0
      const previousCents = before.get(categoryId) ?? 0
      return {
        categoryId,
        cents,
        previousCents,
        change: centsChange(cents, previousCents),
      }
    })
    .filter(shift => Math.abs(shift.change.cents) >= RECAP_SHIFT_MIN_CENTS)
  return {
    rose: shifts
      .filter(shift => shift.change.cents > 0)
      .sort((a, b) => b.change.cents - a.change.cents)
      .slice(0, RECAP_TOP_SHIFTS),
    fell: shifts
      .filter(shift => shift.change.cents < 0)
      .sort((a, b) => a.change.cents - b.change.cents)
      .slice(0, RECAP_TOP_SHIFTS),
  }
}

// Started: first charged this month. Stopped: charged the month before, not
// this one, and never since.
export function subscriptionShifts(
  subscriptions: readonly RecapSubscription[],
  month: string,
): { started: RecapSubscription[]; stopped: RecapSubscription[] } {
  const previous = shiftMonth(month, -1)
  const charged = (item: RecapSubscription, at: string) =>
    item.chargedMonths.includes(at)
  const earliest = (item: RecapSubscription) =>
    [...item.chargedMonths].sort()[0]
  const latest = (item: RecapSubscription) =>
    [...item.chargedMonths].sort().at(-1)
  return {
    started: subscriptions.filter(
      item => charged(item, month) && earliest(item) === month,
    ),
    stopped: subscriptions.filter(
      item =>
        charged(item, previous) &&
        !charged(item, month) &&
        latest(item) === previous,
    ),
  }
}

export function buildMonthlyRecap(input: MonthlyRecapInput): MonthlyRecapFacts {
  const flow = flowOf(input.flow)
  const previousFlow = flowOf(input.previousFlow)
  const netWorth = input.netWorth
  return {
    month: input.month,
    flow,
    previousFlow,
    incomeChange: centsChange(flow.income, previousFlow.income),
    expensesChange: centsChange(flow.expenses, previousFlow.expenses),
    savingsPercent: savingsPercent(flow),
    previousSavingsPercent: savingsPercent(previousFlow),
    topCategory: topCategory(input.categories, flow.expenses),
    ...categoryShifts(input.categories, input.previousCategories),
    ...subscriptionShifts(input.subscriptions, input.month),
    netWorth: netWorth && {
      end: netWorth.end,
      change: centsChange(netWorth.end, netWorth.previousEnd),
    },
  }
}
