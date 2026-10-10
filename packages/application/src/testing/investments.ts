import { type LocalDate } from '@cashdeck/domain'
import {
  type DailyValue,
  type IndexRateRepository,
  type InvestmentMovement,
  type InvestmentPosition,
  type InvestmentRepository,
  type InvestmentSnapshot,
  type MarketData,
} from '@/ports/investments'

const keyOf = (position: InvestmentPosition) =>
  `${position.tenantId}:${position.connectionId}:${position.externalId}`

const movementKey = (movement: InvestmentMovement) =>
  `${movement.investmentId}:${movement.externalId}`

const snapshotKey = (snapshot: InvestmentSnapshot) =>
  `${snapshot.investmentId}:${snapshot.day}`

const byDay = (a: { day: LocalDate }, b: { day: LocalDate }) =>
  a.day.localeCompare(b.day)

export class InMemoryInvestmentRepository implements InvestmentRepository {
  private readonly rows = new Map<string, InvestmentPosition>()
  private readonly movements = new Map<string, InvestmentMovement>()
  private readonly snapshots = new Map<string, InvestmentSnapshot>()

  async saveAll(positions: readonly InvestmentPosition[]): Promise<void> {
    for (const position of positions) {
      const known = this.rows.get(keyOf(position))
      this.rows.set(keyOf(position), {
        ...position,
        id: known?.id ?? position.id,
      })
    }
  }

  async list(tenantId: string): Promise<InvestmentPosition[]> {
    return [...this.rows.values()].filter(row => row.tenantId === tenantId)
  }

  async deleteByConnection(
    tenantId: string,
    connectionId: string,
  ): Promise<void> {
    for (const [key, row] of this.rows) {
      if (row.tenantId === tenantId && row.connectionId === connectionId) {
        this.rows.delete(key)
        this.dropHistory(row.id)
      }
    }
  }

  async saveMovements(movements: readonly InvestmentMovement[]): Promise<void> {
    for (const movement of movements) {
      const known = this.movements.get(movementKey(movement))
      this.movements.set(movementKey(movement), {
        ...movement,
        id: known?.id ?? movement.id,
      })
    }
  }

  async listMovements(
    tenantId: string,
    investmentId?: string,
  ): Promise<InvestmentMovement[]> {
    return [...this.movements.values()].filter(
      row =>
        row.tenantId === tenantId &&
        (investmentId === undefined || row.investmentId === investmentId),
    )
  }

  async saveSnapshots(snapshots: readonly InvestmentSnapshot[]): Promise<void> {
    for (const snapshot of snapshots) {
      if (snapshot.estimated && this.snapshots.has(snapshotKey(snapshot))) {
        continue
      }
      this.snapshots.set(snapshotKey(snapshot), snapshot)
    }
  }

  async listSnapshots(
    tenantId: string,
    range: { from: LocalDate; to: LocalDate },
    investmentId?: string,
  ): Promise<InvestmentSnapshot[]> {
    const owned = [...this.snapshots.values()]
      .filter(
        row =>
          row.tenantId === tenantId &&
          row.day <= range.to &&
          (investmentId === undefined || row.investmentId === investmentId),
      )
      .sort(byDay)
    const before = new Map<string, InvestmentSnapshot>()
    for (const row of owned.filter(row => row.day < range.from)) {
      before.set(row.investmentId, row)
    }
    return [...before.values(), ...owned.filter(row => row.day >= range.from)]
  }

  async firstSnapshotDays(tenantId: string): Promise<Map<string, LocalDate>> {
    const firsts = new Map<string, LocalDate>()
    for (const row of [...this.snapshots.values()].sort(byDay).reverse()) {
      if (row.tenantId === tenantId) {
        firsts.set(row.investmentId, row.day)
      }
    }
    return firsts
  }

  private dropHistory(investmentId: string) {
    for (const [key, row] of this.movements) {
      if (row.investmentId === investmentId) {
        this.movements.delete(key)
      }
    }
    for (const [key, row] of this.snapshots) {
      if (row.investmentId === investmentId) {
        this.snapshots.delete(key)
      }
    }
  }
}

export class InMemoryIndexRateRepository implements IndexRateRepository {
  private readonly rows = new Map<string, Map<LocalDate, number>>()

  async save(index: string, rates: readonly DailyValue[]): Promise<void> {
    const known = this.rows.get(index) ?? new Map<LocalDate, number>()
    for (const rate of rates) {
      known.set(rate.day, rate.value)
    }
    this.rows.set(index, known)
  }

  async list(
    index: string,
    range: { from: LocalDate; to: LocalDate },
  ): Promise<DailyValue[]> {
    return [...(this.rows.get(index) ?? new Map<LocalDate, number>())]
      .map(([day, value]) => ({ day, value }))
      .filter(rate => rate.day >= range.from && rate.day <= range.to)
      .sort(byDay)
  }

  async lastDay(index: string): Promise<LocalDate | null> {
    return [...(this.rows.get(index)?.keys() ?? [])].sort().at(-1) ?? null
  }
}

// Serves scripted closes and CDI rates, sliced to the range asked for.
export class FakeMarketData implements MarketData {
  closes = new Map<string, DailyValue[] | Error>()
  cdi: DailyValue[] | Error = []
  readonly requests: string[] = []

  async dailyCloses(
    ticker: string,
    from: LocalDate,
    to: LocalDate,
  ): Promise<DailyValue[]> {
    this.requests.push(`closes:${ticker}:${from}:${to}`)
    return within(this.closes.get(ticker) ?? [], from, to)
  }

  async cdiRates(from: LocalDate, to: LocalDate): Promise<DailyValue[]> {
    this.requests.push(`cdi:${from}:${to}`)
    return within(this.cdi, from, to)
  }
}

function within(values: DailyValue[] | Error, from: LocalDate, to: LocalDate) {
  if (values instanceof Error) {
    throw values
  }
  return values.filter(value => value.day >= from && value.day <= to)
}
