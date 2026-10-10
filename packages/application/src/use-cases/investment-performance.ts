import { addDays, daysBetween, type LocalDate, Money } from '@cashdeck/domain'
import { money } from '@/dtos/common'
import {
  type InvestmentDetailView,
  type InvestmentPerformanceQuery,
  type InvestmentPerformanceView,
  type InvestmentPeriod,
  type InvestmentPeriodView,
} from '@/dtos/investments'
import {
  CDI_INDEX,
  type InvestmentMovement,
  type InvestmentPosition,
  type InvestmentSnapshot,
} from '@/ports/investments'
import { type Deps } from '@/use-cases/deps'
import {
  groupByPosition,
  heldPositions,
  positionView,
  signedFlow,
  TOTAL_CURRENCY,
} from '@/use-cases/investments'
import { required, requireEntityById, today } from '@/use-cases/shared'

type PerformanceDeps = Pick<
  Deps,
  'entities' | 'institutions' | 'investments' | 'indexRates' | 'clock'
>

const PERIOD_DAYS: Record<InvestmentPeriod, number> = {
  WEEK: 7,
  MONTH: 30,
  YEAR: 365,
}

const SERIES_STEP_DAYS: Record<InvestmentPeriod, number> = {
  WEEK: 1,
  MONTH: 1,
  YEAR: 7,
}

type Window = {
  period: InvestmentPeriod
  from: LocalDate
  to: LocalDate
  days: number
}

type History = {
  snapshots: Map<string, InvestmentSnapshot[]>
  movements: Map<string, InvestmentMovement[]>
}

// Cents of each part of a period; `weighted` is the Modified Dietz sum of
// each flow times the share of the period left after it.
type Figures = {
  start: number
  end: number
  contributions: number
  withdrawals: number
  weighted: number
  estimated: boolean
}

const EMPTY: Figures = {
  start: 0,
  end: 0,
  contributions: 0,
  withdrawals: 0,
  weighted: 0,
  estimated: false,
}

const round2 = (value: number) => Math.round(value * 100) / 100

const yieldCents = (figures: Figures) =>
  figures.end - figures.start - figures.contributions + figures.withdrawals

function yieldPercent(figures: Figures) {
  const base = figures.start + figures.weighted
  return base > 0 ? round2((yieldCents(figures) / base) * 100) : null
}

function windowOf(period: InvestmentPeriod, now: Date): Window {
  const to = today(now)
  const days = PERIOD_DAYS[period]
  return { period, from: addDays(to, -days), to, days }
}

const lastOn = (snapshots: readonly InvestmentSnapshot[], day: LocalDate) =>
  snapshots.filter(snapshot => snapshot.day <= day).at(-1)

// Today is the current balance; a past day is its last snapshot, or 0.
function valueOn(
  position: InvestmentPosition,
  snapshots: readonly InvestmentSnapshot[],
  day: LocalDate,
  window: Window,
) {
  if (day >= window.to) {
    return position.balance.cents
  }
  return lastOn(snapshots, day)?.balanceCents ?? 0
}

function figuresOf(
  position: InvestmentPosition,
  history: History,
  window: Window,
): Figures {
  const snapshots = history.snapshots.get(position.id) ?? []
  const flows = (history.movements.get(position.id) ?? [])
    .filter(
      movement =>
        movement.occurredOn > window.from && movement.occurredOn <= window.to,
    )
    .map(movement => ({
      cents: signedFlow(movement),
      weight: daysBetween(movement.occurredOn, window.to) / window.days,
    }))
  return {
    start: valueOn(position, snapshots, window.from, window),
    end: position.balance.cents,
    contributions: flows
      .filter(flow => flow.cents > 0)
      .reduce((sum, flow) => sum + flow.cents, 0),
    withdrawals: flows
      .filter(flow => flow.cents < 0)
      .reduce((sum, flow) => sum - flow.cents, 0),
    weighted: flows.reduce((sum, flow) => sum + flow.cents * flow.weight, 0),
    estimated: lastOn(snapshots, window.from)?.estimated ?? false,
  }
}

const added = (a: Figures, b: Figures): Figures => ({
  start: a.start + b.start,
  end: a.end + b.end,
  contributions: a.contributions + b.contributions,
  withdrawals: a.withdrawals + b.withdrawals,
  weighted: a.weighted + b.weighted,
  estimated: a.estimated || b.estimated,
})

function seriesDays(window: Window): LocalDate[] {
  const step = SERIES_STEP_DAYS[window.period]
  const days: LocalDate[] = []
  for (let day = window.from; day < window.to; day = addDays(day, step)) {
    days.push(day)
  }
  return [...days, window.to]
}

export function makeInvestmentPerformance(deps: PerformanceDeps) {
  async function historyOf(
    tenantId: string,
    window: Window,
    investmentId?: string,
  ): Promise<History> {
    const range = { from: window.from, to: window.to }
    return {
      snapshots: groupByPosition(
        await deps.investments.listSnapshots(tenantId, range, investmentId),
      ),
      movements: groupByPosition(
        await deps.investments.listMovements(tenantId, investmentId),
      ),
    }
  }

  // Compounded daily CDI over the days after `from`, in percent.
  async function cdiPercent(window: Window) {
    const rates = await deps.indexRates.list(CDI_INDEX, {
      from: addDays(window.from, 1),
      to: window.to,
    })
    if (rates.length === 0) {
      return null
    }
    const growth = rates.reduce((sum, rate) => sum * (1 + rate.value / 100), 1)
    return round2((growth - 1) * 100)
  }

  async function periodView(
    positions: readonly InvestmentPosition[],
    history: History,
    window: Window,
    currency: string,
  ): Promise<InvestmentPeriodView> {
    const figures = positions
      .map(position => figuresOf(position, history, window))
      .reduce(added, EMPTY)
    const cash = (cents: number) => money(Money.of(cents, currency))
    return {
      period: window.period,
      from: window.from,
      to: window.to,
      start: cash(figures.start),
      end: cash(figures.end),
      contributions: cash(figures.contributions),
      withdrawals: cash(figures.withdrawals),
      yield: cash(yieldCents(figures)),
      yieldPercent: yieldPercent(figures),
      cdiPercent: await cdiPercent(window),
      estimated: figures.estimated,
      series: seriesDays(window).map(day => ({
        day,
        value: cash(
          positions.reduce(
            (sum, position) =>
              sum +
              valueOn(
                position,
                history.snapshots.get(position.id) ?? [],
                day,
                window,
              ),
            0,
          ),
        ),
      })),
    }
  }

  async function performance(
    tenantId: string,
    query: InvestmentPerformanceQuery,
  ): Promise<InvestmentPerformanceView> {
    const window = windowOf(query.period, deps.clock.now())
    const { held } = await heldPositions(deps, tenantId, query.entity)
    const counted = held.filter(
      position => position.balance.currency === TOTAL_CURRENCY,
    )
    const history = await historyOf(tenantId, window)
    const cash = (cents: number) => money(Money.of(cents, TOTAL_CURRENCY))
    const positions = counted
      .map(position => {
        const figures = figuresOf(position, history, window)
        return {
          id: position.id,
          start: cash(figures.start),
          end: cash(figures.end),
          yield: cash(yieldCents(figures)),
          yieldPercent: yieldPercent(figures),
        }
      })
      .sort((a, b) => b.yield.cents - a.yield.cents)
    return {
      ...(await periodView(counted, history, window, TOTAL_CURRENCY)),
      positions,
    }
  }

  async function detail(
    tenantId: string,
    id: string,
    period: InvestmentPeriod,
  ): Promise<InvestmentDetailView> {
    const position = required(
      (await deps.investments.list(tenantId)).find(row => row.id === id) ??
        null,
      'Investment',
    )
    const window = windowOf(period, deps.clock.now())
    const owner = await requireEntityById(
      deps.entities,
      tenantId,
      position.entityId,
    )
    const institution = await deps.institutions.findById(
      tenantId,
      position.institutionId,
    )
    const history = await historyOf(tenantId, window, position.id)
    const movements = [...(history.movements.get(position.id) ?? [])].sort(
      (a, b) => b.occurredOn.localeCompare(a.occurredOn),
    )
    return {
      position: positionView(position, owner.kind, institution, movements),
      performance: await periodView(
        [position],
        history,
        window,
        position.balance.currency,
      ),
      movements: movements.map(movement => ({
        id: movement.id,
        kind: movement.kind,
        occurredOn: movement.occurredOn,
        amount: money(
          Money.of(movement.amountCents, position.balance.currency),
        ),
        quantity: movement.quantity,
        unitPrice: movement.unitPrice,
      })),
    }
  }

  return { performance, detail }
}
