import { addDays, daysBetween, type LocalDate } from '@/calendar/local-date'
import { Money } from '@/money/money'
import { ValidationError } from '@/shared/domain-error'
import { guard } from '@/shared/guard'

export const GOAL_STATUSES = ['DONE', 'ON_TRACK', 'BEHIND'] as const
export type GoalStatus = (typeof GOAL_STATUSES)[number]

// Where the saved amount comes from: what the user puts in by hand, or the
// balance of the account or investment the goal lives in.
export const GOAL_SOURCES = ['MANUAL', 'ACCOUNT', 'INVESTMENT'] as const
export type GoalSource = (typeof GOAL_SOURCES)[number]

export const GOAL_NAME_MAX = 60
const TAG_MAX = 40

export const AVERAGE_MONTH_DAYS = 30.4375
// The saving pace looks this far back, and never at less than a month, so a
// goal created yesterday does not project a whole target from one deposit.
export const PACE_WINDOW_DAYS = 90
export const MIN_PACE_DAYS = 30
const MAX_PROJECTION_DAYS = 365 * 50

export type Goal = {
  readonly id: string
  readonly tenantId: string
  readonly entityId: string
  readonly name: string
  readonly target: Money
  readonly deadline: LocalDate | null
  readonly accountId: string | null
  readonly investmentId: string | null
  // Names the app maps to its own icons and palette.
  readonly icon: string | null
  readonly color: string | null
  readonly createdAt: Date
  readonly archivedAt: Date | null
}

export type GoalContribution = {
  readonly id: string
  readonly tenantId: string
  readonly goalId: string
  // Negative when money left the goal.
  readonly amount: Money
  readonly on: LocalDate
  readonly note: string | null
  readonly createdAt: Date
}

export type CreateGoalInput = Omit<
  Goal,
  'deadline' | 'accountId' | 'investmentId' | 'icon' | 'color' | 'archivedAt'
> &
  Partial<
    Pick<
      Goal,
      | 'deadline'
      | 'accountId'
      | 'investmentId'
      | 'icon'
      | 'color'
      | 'archivedAt'
    >
  >

function tag(value: string | null | undefined, field: string): string | null {
  if (value === null || value === undefined) {
    return null
  }
  const trimmed = guard.notEmpty(value, field)
  if (trimmed.length > TAG_MAX) {
    throw new ValidationError(
      `${field} must have at most ${TAG_MAX} characters.`,
    )
  }
  return trimmed
}

export function goalName(value: string): string {
  const name = guard.notEmpty(value, 'Goal name')
  if (name.length > GOAL_NAME_MAX) {
    throw new ValidationError(
      `Goal name must have at most ${GOAL_NAME_MAX} characters.`,
    )
  }
  return name
}

export function createGoal(input: CreateGoalInput): Goal {
  if (!input.target.isPositive()) {
    throw new ValidationError('A goal needs a positive target.')
  }
  const accountId = input.accountId ?? null
  const investmentId = input.investmentId ?? null
  if (accountId !== null && investmentId !== null) {
    throw new ValidationError(
      'A goal follows an account or an investment, not both.',
    )
  }
  return {
    ...input,
    name: goalName(input.name),
    deadline: input.deadline ?? null,
    accountId,
    investmentId,
    icon: tag(input.icon, 'Goal icon'),
    color: tag(input.color, 'Goal color'),
    archivedAt: input.archivedAt ?? null,
  }
}

export function goalSource(goal: Goal): GoalSource {
  if (goal.accountId !== null) {
    return 'ACCOUNT'
  }
  return goal.investmentId === null ? 'MANUAL' : 'INVESTMENT'
}

export function createContribution(
  input: Omit<GoalContribution, 'note'> & { note?: string | null },
): GoalContribution {
  if (input.amount.isZero()) {
    throw new ValidationError('A contribution needs an amount.')
  }
  return { ...input, note: tag(input.note, 'Contribution note') }
}

export const contributedTotal = (
  contributions: readonly GoalContribution[],
): Money =>
  contributions.reduce((total, item) => total.add(item.amount), Money.zero())

// Days of history the pace is averaged over: the goal's age, kept between a
// month and the window.
export function paceWindowDays(since: LocalDate, today: LocalDate): number {
  const age = daysBetween(since, today)
  return Math.min(PACE_WINDOW_DAYS, Math.max(MIN_PACE_DAYS, age))
}

export function monthlyPace(saved: Money, windowDays: number): Money {
  return Money.of(
    Math.round((saved.cents * AVERAGE_MONTH_DAYS) / windowDays),
    saved.currency,
  )
}

export type GoalProgress = {
  readonly saved: Money
  readonly remaining: Money
  // 0 to 100, rounded down so 100 only shows once the target is met.
  readonly percent: number
  readonly status: GoalStatus
  // What each month still needs to meet the deadline; null without one.
  readonly requiredMonthly: Money | null
  // Null while the goal is too new to have a pace.
  readonly monthlyPace: Money | null
  // When the recent pace meets the target; null when it never does.
  readonly projectedOn: LocalDate | null
}

export type GoalProgressInput = {
  readonly target: Money
  readonly saved: Money
  readonly deadline: LocalDate | null
  readonly today: LocalDate
  readonly pace: Money | null
}

function percentOf(saved: Money, target: Money): number {
  const percent = Math.floor((saved.cents * 100) / target.cents)
  return Math.min(100, Math.max(0, percent))
}

function requiredMonthly(
  remaining: Money,
  deadline: LocalDate | null,
  today: LocalDate,
): Money | null {
  if (deadline === null) {
    return null
  }
  const months = Math.ceil(daysBetween(today, deadline) / AVERAGE_MONTH_DAYS)
  return Money.of(
    Math.ceil(remaining.cents / Math.max(1, months)),
    remaining.currency,
  )
}

function projectedOn(
  remaining: Money,
  pace: Money | null,
  today: LocalDate,
): LocalDate | null {
  if (pace === null || !pace.isPositive()) {
    return null
  }
  const days = Math.ceil((remaining.cents / pace.cents) * AVERAGE_MONTH_DAYS)
  return days > MAX_PROJECTION_DAYS ? null : addDays(today, days)
}

// Without a pace yet a goal is not behind until its deadline passes.
function statusOf(
  done: boolean,
  deadline: LocalDate | null,
  projected: LocalDate | null,
  input: GoalProgressInput,
): GoalStatus {
  if (done) {
    return 'DONE'
  }
  if (deadline === null) {
    return 'ON_TRACK'
  }
  if (deadline < input.today) {
    return 'BEHIND'
  }
  if (input.pace === null) {
    return 'ON_TRACK'
  }
  return projected !== null && projected <= deadline ? 'ON_TRACK' : 'BEHIND'
}

export function goalProgress(input: GoalProgressInput): GoalProgress {
  const { target, saved, deadline, today, pace } = input
  const done = saved.cents >= target.cents
  const remaining = done ? Money.zero(target.currency) : target.subtract(saved)
  const projected = done ? null : projectedOn(remaining, pace, today)
  return {
    saved,
    remaining,
    percent: percentOf(saved, target),
    status: statusOf(done, deadline, projected, input),
    requiredMonthly: done
      ? Money.zero(target.currency)
      : requiredMonthly(remaining, deadline, today),
    monthlyPace: pace,
    projectedOn: projected,
  }
}
