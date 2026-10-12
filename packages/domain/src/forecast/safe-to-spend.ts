import {
  addDays,
  daysBetween,
  type LocalDate,
  shiftMonth,
} from '@/calendar/local-date'
import { Money } from '@/money/money'

// A credit into the personal checking accounts; the key tells one payer or
// kind of transfer from another, so each stream is judged on its own.
export type IncomeCredit = {
  readonly key: string
  readonly on: LocalDate
  readonly amount: Money
}

export type ExpectedIncome = { readonly on: LocalDate; readonly amount: Money }

const INCOME_MIN_MONTHS = 2
// A payer silent for longer than this has stopped paying.
const INCOME_STALE_DAYS = 45
// Cashback, yields and small refunds recur too, but do not end the window.
const INCOME_MIN_SHARE = 0.25

export const OBLIGATION_KINDS = [
  'BILL',
  'FIXED',
  'SUBSCRIPTION',
  'CARD',
] as const
export type ObligationKind = (typeof OBLIGATION_KINDS)[number]

// Something already owed before the next income. One paid from the reserve
// is covered by its balance first; the rest leaves the checking accounts.
export type Obligation = {
  readonly kind: ObligationKind
  readonly label: string
  readonly amount: Money
  readonly on: LocalDate
  readonly fromReserve: boolean
}

export type SafeToSpendLineKind = ObligationKind | 'RESERVE'

// Signed: a deduction is negative, the share the reserve covers is positive.
export type SafeToSpendLine = {
  readonly kind: SafeToSpendLineKind
  readonly label: string
  readonly amount: Money
  readonly on: LocalDate | null
}

export type SafeToSpendInput = {
  readonly today: LocalDate
  readonly cash: Money
  readonly reserve: Money
  readonly income: ExpectedIncome | null
  readonly obligations: readonly Obligation[]
}

export type SafeToSpend = {
  readonly total: Money
  readonly daily: Money
  readonly days: number
  // The last day an obligation counts: the income day, else the month end.
  readonly until: LocalDate
  readonly income: ExpectedIncome | null
  readonly shortBy: Money
  readonly lines: readonly SafeToSpendLine[]
}

const sum = (amounts: readonly Money[]) =>
  amounts.reduce((total, amount) => total.add(amount), Money.zero())

export function lastDayOfMonth(day: LocalDate): LocalDate {
  return addDays(`${shiftMonth(day.slice(0, 7), 1)}-01`, -1)
}

function dayIn(month: string, dayOfMonth: number): LocalDate {
  const wanted = `${month}-${String(dayOfMonth).padStart(2, '0')}`
  const last = lastDayOfMonth(`${month}-01`)
  return wanted < last ? wanted : last
}

// The first date on that day of the month strictly after `after`; a short
// month moves it to its last day.
export function nextMonthlyDate(
  after: LocalDate,
  dayOfMonth: number,
): LocalDate {
  const month = after.slice(0, 7)
  const same = dayIn(month, dayOfMonth)
  return same > after ? same : dayIn(shiftMonth(month, 1), dayOfMonth)
}

// Every date on that day of the month from `from` to `to`, both included.
export function monthlyDatesBetween(
  dayOfMonth: number,
  from: LocalDate,
  to: LocalDate,
): LocalDate[] {
  const dates: LocalDate[] = []
  for (
    let date = nextMonthlyDate(addDays(from, -1), dayOfMonth);
    date <= to;
    date = nextMonthlyDate(date, dayOfMonth)
  ) {
    dates.push(date)
  }
  return dates
}

type IncomeStream = { on: LocalDate; amount: Money }

// The largest credit of each month stands for the stream in that month, so a
// payer that also sends a second, smaller amount still reads as monthly.
function streamOf(
  credits: readonly IncomeCredit[],
  today: LocalDate,
): IncomeStream | null {
  const byMonth = new Map<string, IncomeCredit>()
  for (const credit of credits) {
    const month = credit.on.slice(0, 7)
    const known = byMonth.get(month)
    if (!known || credit.amount.cents > known.amount.cents) {
      byMonth.set(month, credit)
    }
  }
  const latest = [...byMonth.values()].sort((a, b) =>
    b.on.localeCompare(a.on),
  )[0] as IncomeCredit
  const recurring = byMonth.size >= INCOME_MIN_MONTHS
  const running = daysBetween(latest.on, today) <= INCOME_STALE_DAYS
  if (!recurring || !running) {
    return null
  }
  return {
    on: nextMonthlyDate(today, Number(latest.on.slice(8, 10))),
    amount: latest.amount,
  }
}

// The next salary, pro-labore or distribution: the soonest monthly stream
// among those at least a quarter of the largest, with every stream that day.
export function expectedIncome(
  credits: readonly IncomeCredit[],
  today: LocalDate,
): ExpectedIncome | null {
  const byKey = new Map<string, IncomeCredit[]>()
  for (const credit of credits.filter(credit => credit.amount.isPositive())) {
    byKey.set(credit.key, [...(byKey.get(credit.key) ?? []), credit])
  }
  const streams = [...byKey.values()].flatMap(group => {
    const stream = streamOf(group, today)
    return stream ? [stream] : []
  })
  const largest = Math.max(0, ...streams.map(stream => stream.amount.cents))
  const relevant = streams.filter(
    stream => stream.amount.cents >= largest * INCOME_MIN_SHARE,
  )
  const on = relevant
    .map(stream => stream.on)
    .sort()
    .at(0)
  if (on === undefined) {
    return null
  }
  return {
    on,
    amount: sum(
      relevant.filter(stream => stream.on === on).map(stream => stream.amount),
    ),
  }
}

// Days the money has to last: up to the day before the income arrives, or
// through the end of the month when no income is known.
export function spendingWindow(
  today: LocalDate,
  income: ExpectedIncome | null,
): { until: LocalDate; days: number } {
  if (income) {
    return {
      until: income.on,
      days: Math.max(1, daysBetween(today, income.on)),
    }
  }
  const until = lastDayOfMonth(today)
  return { until, days: daysBetween(today, until) + 1 }
}

const byDate = (a: Obligation, b: Obligation) =>
  a.on.localeCompare(b.on) || a.label.localeCompare(b.label)

// Checking balance minus what is owed until the next income; obligations
// paid from the reserve only count for what its balance does not cover.
export function safeToSpend(input: SafeToSpendInput): SafeToSpend {
  const { until, days } = spendingWindow(input.today, input.income)
  const due = input.obligations.filter(obligation => obligation.on <= until)
  const fromReserve = sum(
    due.filter(item => item.fromReserve).map(item => item.amount),
  )
  const available = Math.max(0, input.reserve.cents)
  const covered = Money.of(Math.min(available, fromReserve.cents))
  const lines: SafeToSpendLine[] = [...due].sort(byDate).map(item => ({
    kind: item.kind,
    label: item.label,
    amount: item.amount.negate(),
    on: item.on,
  }))
  if (covered.isPositive()) {
    lines.push({ kind: 'RESERVE', label: '', amount: covered, on: null })
  }
  const total = input.cash.add(sum(lines.map(line => line.amount)))
  return {
    total,
    daily: Money.of(total.isPositive() ? Math.floor(total.cents / days) : 0),
    days,
    until,
    income: input.income,
    shortBy: Money.of(total.isNegative() ? -total.cents : 0),
    lines,
  }
}
