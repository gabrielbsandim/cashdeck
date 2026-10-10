import { type PrismaClient } from '@prisma/client'
import {
  type InvestmentKind,
  type InvestmentPosition,
  type InvestmentRepository,
  type InvestmentStatus,
} from '@cashdeck/application'
import { Money } from '@cashdeck/domain'
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
}
