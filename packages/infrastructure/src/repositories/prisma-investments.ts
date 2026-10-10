import { type PrismaClient } from '@prisma/client'
import {
  type DailyValue,
  type IndexRateRepository,
  type InvestmentKind,
  type InvestmentMovement,
  type InvestmentPosition,
  type InvestmentRepository,
  type InvestmentSnapshot,
  type InvestmentStatus,
  type MovementKind,
} from '@cashdeck/application'
import { type LocalDate, Money } from '@cashdeck/domain'
import { fromDbDate, toDbDate } from '@/repositories/mappers'

type InvestmentRow = {
  id: string
  tenantId: string
  entityId: string
  connectionId: string
  institutionId: string
  externalId: string
  name: string
  kind: InvestmentKind
  subtype: string | null
  issuer: string | null
  status: InvestmentStatus
  balanceCents: bigint
  investedCents: bigint | null
  profitCents: bigint | null
  currency: string
  quantity: number | null
  ratePercent: number | null
  rateIndex: string | null
  fixedAnnualRate: number | null
  lastMonthRate: number | null
  lastTwelveMonthsRate: number | null
  dueOn: Date | null
  valuedOn: Date | null
  syncedAt: Date
}

const centsOf = (value: Money | null) =>
  value === null ? null : BigInt(value.cents)

const moneyOf = (cents: bigint | null, currency: string) =>
  cents === null ? null : Money.of(Number(cents), currency)

const dayOf = (value: Date | null) => (value ? fromDbDate(value) : null)

const dbDayOf = (day: string | null) => (day ? toDbDate(day) : null)

export function investmentFromRow(row: InvestmentRow): InvestmentPosition {
  const rated =
    row.ratePercent !== null ||
    row.rateIndex !== null ||
    row.fixedAnnualRate !== null
  return {
    id: row.id,
    tenantId: row.tenantId,
    entityId: row.entityId,
    connectionId: row.connectionId,
    institutionId: row.institutionId,
    externalId: row.externalId,
    name: row.name,
    kind: row.kind,
    subtype: row.subtype,
    issuer: row.issuer,
    status: row.status,
    balance: Money.of(Number(row.balanceCents), row.currency),
    invested: moneyOf(row.investedCents, row.currency),
    profit: moneyOf(row.profitCents, row.currency),
    quantity: row.quantity,
    rate: rated
      ? {
          percent: row.ratePercent,
          index: row.rateIndex,
          fixedAnnual: row.fixedAnnualRate,
        }
      : null,
    lastMonthRate: row.lastMonthRate,
    lastTwelveMonthsRate: row.lastTwelveMonthsRate,
    dueOn: dayOf(row.dueOn),
    valuedOn: dayOf(row.valuedOn),
    syncedAt: row.syncedAt,
  }
}

export function investmentToRow(
  position: InvestmentPosition,
): Omit<InvestmentRow, 'id' | 'tenantId' | 'connectionId' | 'externalId'> {
  return {
    entityId: position.entityId,
    institutionId: position.institutionId,
    name: position.name,
    kind: position.kind,
    subtype: position.subtype,
    issuer: position.issuer,
    status: position.status,
    balanceCents: BigInt(position.balance.cents),
    investedCents: centsOf(position.invested),
    profitCents: centsOf(position.profit),
    currency: position.balance.currency,
    quantity: position.quantity,
    ratePercent: position.rate?.percent ?? null,
    rateIndex: position.rate?.index ?? null,
    fixedAnnualRate: position.rate?.fixedAnnual ?? null,
    lastMonthRate: position.lastMonthRate,
    lastTwelveMonthsRate: position.lastTwelveMonthsRate,
    dueOn: dbDayOf(position.dueOn),
    valuedOn: dbDayOf(position.valuedOn),
    syncedAt: position.syncedAt,
  }
}

type MovementRow = {
  id: string
  tenantId: string
  investmentId: string
  externalId: string
  kind: MovementKind
  occurredOn: Date
  amountCents: bigint
  quantity: number | null
  unitPrice: number | null
}

type SnapshotRow = {
  tenantId: string
  investmentId: string
  day: Date
  balanceCents: bigint
  estimated: boolean
}

export const movementFromRow = (row: MovementRow): InvestmentMovement => ({
  ...row,
  occurredOn: fromDbDate(row.occurredOn),
  amountCents: Number(row.amountCents),
})

const movementFields = (movement: InvestmentMovement) => ({
  kind: movement.kind,
  occurredOn: toDbDate(movement.occurredOn),
  amountCents: BigInt(movement.amountCents),
  quantity: movement.quantity,
  unitPrice: movement.unitPrice,
})

export const snapshotFromRow = (row: SnapshotRow): InvestmentSnapshot => ({
  ...row,
  day: fromDbDate(row.day),
  balanceCents: Number(row.balanceCents),
})

export const snapshotToRow = (snapshot: InvestmentSnapshot): SnapshotRow => ({
  ...snapshot,
  day: toDbDate(snapshot.day),
  balanceCents: BigInt(snapshot.balanceCents),
})

export class PrismaInvestmentRepository implements InvestmentRepository {
  constructor(private readonly db: PrismaClient) {}

  async saveAll(positions: readonly InvestmentPosition[]): Promise<void> {
    for (const position of positions) {
      const row = investmentToRow(position)
      await this.db.investment.upsert({
        where: {
          tenantId_connectionId_externalId: {
            tenantId: position.tenantId,
            connectionId: position.connectionId,
            externalId: position.externalId,
          },
        },
        create: {
          id: position.id,
          tenantId: position.tenantId,
          connectionId: position.connectionId,
          externalId: position.externalId,
          ...row,
        },
        update: row,
      })
    }
  }

  async list(tenantId: string): Promise<InvestmentPosition[]> {
    const rows = await this.db.investment.findMany({
      where: { tenantId },
      orderBy: { balanceCents: 'desc' },
    })
    return rows.map(investmentFromRow)
  }

  async deleteByConnection(
    tenantId: string,
    connectionId: string,
  ): Promise<void> {
    await this.db.investment.deleteMany({ where: { tenantId, connectionId } })
  }

  async saveMovements(movements: readonly InvestmentMovement[]): Promise<void> {
    for (const movement of movements) {
      await this.db.investmentMovement.upsert({
        where: {
          investmentId_externalId: {
            investmentId: movement.investmentId,
            externalId: movement.externalId,
          },
        },
        create: {
          id: movement.id,
          tenantId: movement.tenantId,
          investmentId: movement.investmentId,
          externalId: movement.externalId,
          ...movementFields(movement),
        },
        update: movementFields(movement),
      })
    }
  }

  async listMovements(
    tenantId: string,
    investmentId?: string,
  ): Promise<InvestmentMovement[]> {
    const rows = await this.db.investmentMovement.findMany({
      where: { tenantId, investmentId },
      orderBy: { occurredOn: 'asc' },
    })
    return rows.map(movementFromRow)
  }

  // Estimated days go in one insert that skips the days already stored.
  async saveSnapshots(snapshots: readonly InvestmentSnapshot[]): Promise<void> {
    for (const snapshot of snapshots.filter(row => !row.estimated)) {
      const row = snapshotToRow(snapshot)
      await this.db.investmentSnapshot.upsert({
        where: {
          investmentId_day: { investmentId: row.investmentId, day: row.day },
        },
        create: row,
        update: { balanceCents: row.balanceCents, estimated: false },
      })
    }
    const estimated = snapshots.filter(row => row.estimated)
    if (estimated.length === 0) {
      return
    }
    await this.db.investmentSnapshot.createMany({
      data: estimated.map(snapshotToRow),
      skipDuplicates: true,
    })
  }

  async listSnapshots(
    tenantId: string,
    range: { from: LocalDate; to: LocalDate },
    investmentId?: string,
  ): Promise<InvestmentSnapshot[]> {
    const from = toDbDate(range.from)
    const before = await this.db.investmentSnapshot.findMany({
      where: { tenantId, investmentId, day: { lt: from } },
      orderBy: [{ investmentId: 'asc' }, { day: 'desc' }],
      distinct: ['investmentId'],
    })
    const within = await this.db.investmentSnapshot.findMany({
      where: {
        tenantId,
        investmentId,
        day: { gte: from, lte: toDbDate(range.to) },
      },
      orderBy: { day: 'asc' },
    })
    return [...before, ...within].map(snapshotFromRow)
  }

  async firstSnapshotDays(tenantId: string): Promise<Map<string, LocalDate>> {
    const groups = await this.db.investmentSnapshot.groupBy({
      by: ['investmentId'],
      where: { tenantId },
      _min: { day: true },
    })
    return new Map(
      groups.flatMap(group =>
        group._min.day
          ? [[group.investmentId, fromDbDate(group._min.day)]]
          : [],
      ),
    )
  }
}

export class PrismaIndexRateRepository implements IndexRateRepository {
  constructor(private readonly db: PrismaClient) {}

  // A published rate does not change, so a day already stored is kept.
  async save(index: string, rates: readonly DailyValue[]): Promise<void> {
    if (rates.length === 0) {
      return
    }
    await this.db.indexRate.createMany({
      data: rates.map(rate => ({
        index,
        day: toDbDate(rate.day),
        rate: rate.value,
      })),
      skipDuplicates: true,
    })
  }

  async list(
    index: string,
    range: { from: LocalDate; to: LocalDate },
  ): Promise<DailyValue[]> {
    const rows = await this.db.indexRate.findMany({
      where: {
        index,
        day: { gte: toDbDate(range.from), lte: toDbDate(range.to) },
      },
      orderBy: { day: 'asc' },
    })
    return rows.map(row => ({ day: fromDbDate(row.day), value: row.rate }))
  }

  async lastDay(index: string): Promise<LocalDate | null> {
    const last = await this.db.indexRate.findFirst({
      where: { index },
      orderBy: { day: 'desc' },
    })
    return last ? fromDbDate(last.day) : null
  }
}
