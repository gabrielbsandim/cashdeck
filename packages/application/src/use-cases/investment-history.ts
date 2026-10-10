import { addDays, daysBetween, type LocalDate } from '@cashdeck/domain'
import {
  CDI_INDEX,
  type DailyValue,
  type InvestmentMovement,
  type InvestmentPosition,
  type InvestmentSnapshot,
  type MovementKind,
  type ProviderInvestment,
} from '@/ports/investments'
import { type OpenFinanceConnection } from '@/ports/providers'
import { type Connection } from '@/ports/records'
import { type Deps } from '@/use-cases/deps'
import { today } from '@/use-cases/shared'

type HistoryDeps = Pick<
  Deps,
  'investments' | 'indexRates' | 'marketData' | 'openFinance' | 'ids'
>

const BACKFILL_DAYS = 366
// A snapshot older than this means the history was already rebuilt once.
const HISTORY_GRACE_DAYS = 7
const CDI_LOOKBACK_DAYS = 400
const B3_TICKER = /^[A-Z]{4}\d{1,2}$/
const QUOTED_KINDS = new Set(['EQUITY', 'ETF'])
const UNIT_SIGNS: Partial<Record<MovementKind, number>> = { BUY: 1, SELL: -1 }

type Prices = { points: DailyValue[]; quoted: boolean }

function tickerOf(position: InvestmentPosition, provided: ProviderInvestment) {
  const code = provided.code?.trim().toUpperCase() ?? ''
  if (code === '') {
    return null
  }
  return QUOTED_KINDS.has(position.kind) || B3_TICKER.test(code) ? code : null
}

function daysBack(day: LocalDate, count: number): LocalDate[] {
  return Array.from({ length: count }, (_, index) =>
    addDays(day, index - count),
  )
}

// One price per day, sorted; the last one given for a day wins.
function pricePoints(points: readonly DailyValue[]): DailyValue[] {
  const byDay = new Map<LocalDate, number>()
  for (const point of points.filter(point => point.value > 0)) {
    byDay.set(point.day, point.value)
  }
  return [...byDay]
    .map(([day, value]) => ({ day, value }))
    .sort((a, b) => a.day.localeCompare(b.day))
}

// A quote holds until the next trading day; before the first, the first.
function quotedPrice(points: readonly DailyValue[], day: LocalDate) {
  const known = points.filter(point => point.day <= day).at(-1)
  return (known ?? (points[0] as DailyValue)).value
}

// Fixed income grows at a steady rate between two known unit prices.
function interpolatedPrice(points: readonly DailyValue[], day: LocalDate) {
  const next = points.findIndex(point => point.day > day)
  if (next === 0) {
    return (points[0] as DailyValue).value
  }
  if (next === -1) {
    return (points.at(-1) as DailyValue).value
  }
  const before = points[next - 1] as DailyValue
  const after = points[next] as DailyValue
  const share =
    daysBetween(before.day, day) / daysBetween(before.day, after.day)
  return before.value * (after.value / before.value) ** share
}

function unitsOn(
  quantity: number,
  movements: readonly InvestmentMovement[],
  day: LocalDate,
) {
  const later = movements
    .filter(movement => movement.occurredOn > day)
    .reduce(
      (sum, movement) =>
        sum + (UNIT_SIGNS[movement.kind] ?? 0) * (movement.quantity ?? 0),
      0,
    )
  return Math.max(0, quantity - later)
}

export function makeInvestmentHistory(deps: HistoryDeps) {
  async function pricesOf(
    position: InvestmentPosition,
    provided: ProviderInvestment,
    movements: readonly InvestmentMovement[],
    day: LocalDate,
  ): Promise<Prices | null> {
    const ticker = tickerOf(position, provided)
    const points = ticker
      ? await deps.marketData.dailyCloses(
          ticker,
          addDays(day, -BACKFILL_DAYS - HISTORY_GRACE_DAYS),
          day,
        )
      : [
          ...movements.flatMap(movement =>
            movement.unitPrice === null
              ? []
              : [{ day: movement.occurredOn, value: movement.unitPrice }],
          ),
          ...(provided.unitPrice === null
            ? []
            : [{ day, value: provided.unitPrice }]),
        ]
    const sorted = pricePoints(points)
    return sorted.length > 0
      ? { points: sorted, quoted: ticker !== null }
      : null
  }

  // Units held each day times the price of that day. Without units or a
  // price the current balance stands flat, so totals do not jump.
  async function rebuild(
    position: InvestmentPosition,
    provided: ProviderInvestment,
    movements: readonly InvestmentMovement[],
    day: LocalDate,
  ): Promise<InvestmentSnapshot[]> {
    const prices = await pricesOf(position, provided, movements, day)
    const quantity = position.quantity
    const valueOn = (past: LocalDate) => {
      if (!prices || quantity === null) {
        return position.balance.cents
      }
      const price = prices.quoted
        ? quotedPrice(prices.points, past)
        : interpolatedPrice(prices.points, past)
      return Math.round(unitsOn(quantity, movements, past) * price * 100)
    }
    return daysBack(day, BACKFILL_DAYS).map(past => ({
      tenantId: position.tenantId,
      investmentId: position.id,
      day: past,
      balanceCents: valueOn(past),
      estimated: true,
    }))
  }

  // A provider that fails to list the movements leaves the stored ones.
  async function movementsOf(
    link: OpenFinanceConnection,
    position: InvestmentPosition,
  ) {
    const fetched = await deps.openFinance
      .listInvestmentMovements(link, position.externalId)
      .catch(() => [])
    await deps.investments.saveMovements(
      fetched.map(movement => ({
        ...movement,
        id: deps.ids.next(),
        tenantId: position.tenantId,
        investmentId: position.id,
      })),
    )
    return deps.investments.listMovements(position.tenantId, position.id)
  }

  async function recordPosition(
    link: OpenFinanceConnection,
    position: InvestmentPosition,
    provided: ProviderInvestment,
    day: LocalDate,
    firstDay: LocalDate | undefined,
  ) {
    const movements = await movementsOf(link, position)
    await deps.investments.saveSnapshots([
      {
        tenantId: position.tenantId,
        investmentId: position.id,
        day,
        balanceCents: position.balance.cents,
        estimated: false,
      },
    ])
    if (
      firstDay !== undefined &&
      firstDay < addDays(day, -HISTORY_GRACE_DAYS)
    ) {
      return
    }
    await deps.investments.saveSnapshots(
      await rebuild(position, provided, movements, day),
    )
  }

  async function refreshCdi(day: LocalDate) {
    const last = await deps.indexRates.lastDay(CDI_INDEX)
    const from = last ? addDays(last, 1) : addDays(day, -CDI_LOOKBACK_DAYS)
    if (from > day) {
      return
    }
    await deps.indexRates.save(
      CDI_INDEX,
      await deps.marketData.cdiRates(from, day),
    )
  }

  // Movements, today's balance and, once, a year rebuilt from market
  // prices, for the positions just fetched; a failure skips that position.
  async function record(
    connection: Connection,
    link: OpenFinanceConnection,
    fetched: readonly ProviderInvestment[],
    now: Date,
  ): Promise<void> {
    const day = today(now)
    const provided = new Map(fetched.map(row => [row.externalId, row]))
    const firstDays = await deps.investments.firstSnapshotDays(
      connection.tenantId,
    )
    const held = (await deps.investments.list(connection.tenantId)).filter(
      position =>
        position.connectionId === connection.id && position.status !== 'CLOSED',
    )
    for (const position of held) {
      const source = provided.get(position.externalId)
      if (!source) {
        continue
      }
      await recordPosition(
        link,
        position,
        source,
        day,
        firstDays.get(position.id),
      ).catch(() => undefined)
    }
    await refreshCdi(day).catch(() => undefined)
  }

  return { record }
}
