import { shiftMonth } from '@/calendar/local-date'

export const PLAN_GOAL_KINDS = ['PURCHASE', 'YEARLY', 'MILESTONE'] as const
export type PlanGoalKind = (typeof PLAN_GOAL_KINDS)[number]

export const MILESTONE_METRICS = ['NET_WORTH', 'INVESTED'] as const
export type MilestoneMetric = (typeof MILESTONE_METRICS)[number]

export const PLAN_PAYMENTS = ['CASH', 'CARD'] as const
export type PlanPayment = (typeof PLAN_PAYMENTS)[number]

export const PLAN_STATUSES = ['NOW', 'PLANNED', 'LATE', 'OUT_OF_REACH'] as const
export type PlanStatus = (typeof PLAN_STATUSES)[number]

// Forty years: far enough for a house, short enough to stay cheap to search.
export const PLAN_HORIZON_MONTHS = 480
const TIMELINE_YEARS = 10

type PlanGoalBase = {
  readonly id: string
  readonly name: string
}

export type PurchaseGoal = PlanGoalBase & {
  readonly kind: 'PURCHASE'
  readonly priceCents: number
  // What the one it replaces sells for, net of what is still owed on it.
  readonly tradeInCents: number
  readonly financedCents: number
  // Spent every month once it happens; negative when it saves money.
  readonly monthlyCostCents: number
  // A car or a house stays in net worth; a trip or a phone is spent.
  readonly keepsValue: boolean
  // On the card the cash leaves with the bills that follow, one per installment.
  readonly payment: PlanPayment
  readonly installments: number
  readonly notBefore: string | null
  readonly by: string | null
}

export type YearlyGoal = PlanGoalBase & {
  readonly kind: 'YEARLY'
  readonly yearlyCents: number
}

export type MilestoneGoal = PlanGoalBase & {
  readonly kind: 'MILESTONE'
  readonly metric: MilestoneMetric
  readonly targetCents: number
  readonly by: string | null
}

export type PlanGoal = PurchaseGoal | YearlyGoal | MilestoneGoal

// Amounts are in today's money and the yield is real, so prices need no
// inflation of their own.
export type PlanStart = {
  readonly month: string
  readonly cashCents: number
  readonly investedCents: number
  readonly netWorthCents: number
  readonly monthlySavingsCents: number
  readonly monthlySpendingCents: number
  readonly reserveMonths: number
  // Share of the savings, 0 to 1, a month's purchases must leave in place.
  readonly keepShare: number
  readonly monthlyYield: number
}

export type MilestoneDelay = {
  readonly milestoneId: string
  // Null when the goal keeps the milestone out of reach.
  readonly months: number | null
}

export type PlannedGoal = {
  readonly id: string
  readonly status: PlanStatus
  // The month it happens or is reached; null when out of reach.
  readonly month: string | null
  // What leaves savings for it: once for a purchase, per month for a yearly one.
  readonly cashCents: number
  readonly delays: readonly MilestoneDelay[]
}

export type PlanPoint = {
  readonly month: string
  readonly netWorthCents: number
  readonly investedCents: number
}

export type LifePlan = {
  readonly reserveCents: number
  readonly yearlyProvisionCents: number
  readonly goals: readonly PlannedGoal[]
  readonly timeline: readonly PlanPoint[]
}

type Schedule = ReadonlyMap<string, number>

type MonthState = {
  invested: number
  netWorth: number
  belowReserve: boolean
  // What the month paid took more than the share allowed.
  overspent: boolean
}

export const purchaseCash = (goal: PurchaseGoal): number =>
  goal.priceCents - goal.tradeInCents - goal.financedCents

const monthsFrom = (start: string, month: string): number => {
  const [fromYear, fromMonth] = start.split('-').map(Number) as [number, number]
  const [year, value] = month.split('-').map(Number) as [number, number]
  return (year - fromYear) * 12 + (value - fromMonth)
}

function purchasesOf(goals: readonly PlanGoal[]): PurchaseGoal[] {
  return goals.filter((goal): goal is PurchaseGoal => goal.kind === 'PURCHASE')
}

function yearlyProvision(goals: readonly PlanGoal[]): number {
  return goals.reduce(
    (total, goal) =>
      goal.kind === 'YEARLY' ? total + goal.yearlyCents / 12 : total,
    0,
  )
}

// What leaves savings each month: a cash purchase in full in its month, a
// card one in equal bills from the month after.
function outflowsOf(
  purchases: readonly PurchaseGoal[],
  schedule: Schedule,
): Map<number, number> {
  const outflows = new Map<number, number>()
  for (const goal of purchases.filter(item => schedule.has(item.id))) {
    const card = goal.payment === 'CARD'
    const parts = card ? goal.installments : 1
    const first = (schedule.get(goal.id) as number) + (card ? 1 : 0)
    for (let part = 0; part < parts; part++) {
      const month = first + part
      outflows.set(
        month,
        (outflows.get(month) ?? 0) + purchaseCash(goal) / parts,
      )
    }
  }
  return outflows
}

// Month by month: the yield, the savings less the yearly provisions, then the
// purchases of that month, what they cost from then on and the bills due.
function simulate(
  start: PlanStart,
  goals: readonly PlanGoal[],
  schedule: Schedule,
): MonthState[] {
  const purchases = purchasesOf(goals)
  const provision = yearlyProvision(goals)
  const outflows = outflowsOf(purchases, schedule)
  let pot = start.cashCents + start.investedCents
  let kept = start.netWorthCents - pot
  let owed = 0
  let savings = start.monthlySavingsCents
  let spending = start.monthlySpendingCents
  const states: MonthState[] = []
  for (let index = 0; index <= PLAN_HORIZON_MONTHS; index++) {
    if (index > 0) {
      pot = pot * (1 + start.monthlyYield) + savings - provision
    }
    const before = pot
    const due = purchases.filter(goal => schedule.get(goal.id) === index)
    for (const goal of due) {
      const cash = purchaseCash(goal)
      owed += cash
      kept += goal.keepsValue ? cash : 0
      savings -= goal.monthlyCostCents
      spending += goal.monthlyCostCents
    }
    const paid = outflows.get(index) ?? 0
    pot -= paid
    owed -= paid
    states.push({
      invested: pot - start.cashCents,
      netWorth: kept + pot - owed,
      belowReserve: pot < start.reserveMonths * spending,
      overspent: paid > 0 && pot < before * start.keepShare,
    })
  }
  return states
}

// Once the first purchase happens the savings never dip below the reserve,
// and no month's purchases take more than the share allowed.
function fits(states: readonly MonthState[], schedule: Schedule): boolean {
  const first = Math.min(...schedule.values())
  return states
    .slice(first)
    .every(state => !state.belowReserve && !state.overspent)
}

function earliest(
  start: PlanStart,
  goals: readonly PlanGoal[],
  schedule: Schedule,
  goal: PurchaseGoal,
  floor: number,
): number | null {
  const from = goal.notBefore
    ? Math.max(floor, monthsFrom(start.month, goal.notBefore))
    : floor
  for (let index = from; index <= PLAN_HORIZON_MONTHS; index++) {
    const tried = new Map(schedule).set(goal.id, index)
    if (fits(simulate(start, goals, tried), tried)) {
      return index
    }
  }
  return null
}

// Purchases take their turn in the order given, each at the first month that
// leaves every earlier one where it was. A milestone holds the purchases below
// it until the month after it is reached, unless it is out of reach.
function scheduleOf(start: PlanStart, goals: readonly PlanGoal[]): Schedule {
  const schedule = new Map<string, number>()
  let floor = 0
  for (const goal of goals) {
    if (goal.kind === 'MILESTONE') {
      const reached = reachedAt(simulate(start, goals, schedule), goal)
      floor = reached === null ? floor : Math.max(floor, reached + 1)
      continue
    }
    if (goal.kind !== 'PURCHASE') {
      continue
    }
    const index = earliest(start, goals, schedule, goal, floor)
    if (index !== null) {
      schedule.set(goal.id, index)
    }
  }
  return schedule
}

function reachedAt(
  states: readonly MonthState[],
  goal: MilestoneGoal,
): number | null {
  const index = states.findIndex(state =>
    goal.metric === 'NET_WORTH'
      ? state.netWorth >= goal.targetCents
      : state.invested >= goal.targetCents,
  )
  return index < 0 ? null : index
}

function statusOf(
  start: PlanStart,
  index: number | null,
  by: string | null,
): PlanStatus {
  if (index === null) {
    return 'OUT_OF_REACH'
  }
  if (index === 0) {
    return 'NOW'
  }
  if (by !== null && shiftMonth(start.month, index) > by) {
    return 'LATE'
  }
  return 'PLANNED'
}

function delaysOf(
  start: PlanStart,
  goals: readonly PlanGoal[],
  schedule: Schedule,
  goal: PurchaseGoal | YearlyGoal,
): MilestoneDelay[] {
  const milestones = goals.filter(
    (item): item is MilestoneGoal => item.kind === 'MILESTONE',
  )
  if (milestones.length === 0) {
    return []
  }
  const others = goals.filter(item => item.id !== goal.id)
  const without = new Map(schedule)
  without.delete(goal.id)
  const withIt = simulate(start, goals, schedule)
  const withoutIt = simulate(start, others, without)
  return milestones.flatMap(milestone => {
    const late = reachedAt(withIt, milestone)
    const early = reachedAt(withoutIt, milestone)
    if (late === early) {
      return []
    }
    const months = late === null || early === null ? null : late - early
    return [{ milestoneId: milestone.id, months }]
  })
}

function timelineOf(
  start: PlanStart,
  states: readonly MonthState[],
): PlanPoint[] {
  return Array.from({ length: TIMELINE_YEARS + 1 }, (_, year) => {
    const state = states[year * 12] as MonthState
    return {
      month: shiftMonth(start.month, year * 12),
      netWorthCents: Math.round(state.netWorth),
      investedCents: Math.round(state.invested),
    }
  })
}

export function lifePlan(
  start: PlanStart,
  goals: readonly PlanGoal[],
): LifePlan {
  const schedule = scheduleOf(start, goals)
  const states = simulate(start, goals, schedule)
  const monthOf = (index: number | null) =>
    index === null ? null : shiftMonth(start.month, index)
  const planned = goals.map((goal): PlannedGoal => {
    switch (goal.kind) {
      case 'PURCHASE': {
        const index = schedule.get(goal.id) ?? null
        return {
          id: goal.id,
          status: statusOf(start, index, goal.by),
          month: monthOf(index),
          cashCents: purchaseCash(goal),
          delays: index === null ? [] : delaysOf(start, goals, schedule, goal),
        }
      }
      case 'YEARLY':
        return {
          id: goal.id,
          status: 'PLANNED',
          month: null,
          cashCents: Math.round(goal.yearlyCents / 12),
          delays: delaysOf(start, goals, schedule, goal),
        }
      case 'MILESTONE': {
        const index = reachedAt(states, goal)
        return {
          id: goal.id,
          status: statusOf(start, index, goal.by),
          month: monthOf(index),
          cashCents: 0,
          delays: [],
        }
      }
    }
  })
  return {
    reserveCents: Math.round(start.reserveMonths * start.monthlySpendingCents),
    yearlyProvisionCents: Math.round(yearlyProvision(goals)),
    goals: planned,
    timeline: timelineOf(start, states),
  }
}
