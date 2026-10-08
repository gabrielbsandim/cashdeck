import { Money } from '@/money/money'

export type ForecastEvent = { readonly day: number; readonly amount: Money }

export type ForecastInput = {
  start: Money
  dailySpend: Money
  events: readonly ForecastEvent[]
  days: number
}

// One balance a day: today first, then each day spends the daily average and
// applies the events that fall on it.
export function projectBalances(input: ForecastInput): Money[] {
  const balances = [input.start]
  for (let day = 1; day <= input.days; day += 1) {
    const moved = input.events
      .filter(event => event.day === day)
      .reduce((sum, event) => sum.add(event.amount), input.dailySpend.negate())
    balances.push((balances.at(-1) as Money).add(moved))
  }
  return balances
}

export function averageDailySpend(
  expenses: readonly Money[],
  days: number,
): Money {
  const total = expenses.reduce(
    (sum, expense) => sum + Math.abs(expense.cents),
    0,
  )
  return Money.of(Math.round(total / days))
}

// How many days of bills, in due order, a balance pays before running out.
export function coverDays(
  balance: Money,
  bills: readonly ForecastEvent[],
  cap: number,
): number {
  let left = balance.cents
  const ordered = [...bills].sort((a, b) => a.day - b.day)
  for (const bill of ordered) {
    left -= Math.abs(bill.amount.cents)
    if (left < 0) {
      return Math.min(Math.max(bill.day, 0), cap)
    }
  }
  return cap
}
