import { type PrismaClient } from '@prisma/client'
import { describe, expect, it, vi } from 'vitest'
import { type InvestmentPosition } from '@cashdeck/application'
import { Money } from '@cashdeck/domain'
import {
  investmentFromRow,
  investmentToRow,
  PrismaIndexRateRepository,
  PrismaInvestmentRepository,
} from '@/repositories/prisma-investments'

const TENANT = 't1'
const NOW = new Date('2026-10-08T12:00:00.000Z')

const cdb: InvestmentPosition = {
  id: 'inv1',
  tenantId: TENANT,
  entityId: 'pf',
  connectionId: 'conn1',
  institutionId: 'bank',
  externalId: 'ext1',
  name: 'CDB Banco Exemplo',
  kind: 'FIXED_INCOME',
  subtype: 'CDB',
  issuer: 'BANCO EXEMPLO S.A.',
  status: 'ACTIVE',
  balance: Money.of(105_000),
  invested: Money.of(100_000),
  profit: null,
  quantity: 1,
  rate: { percent: 102, index: 'CDI', fixedAnnual: null },
  lastMonthRate: null,
  lastTwelveMonthsRate: null,
  dueOn: '2028-04-04',
  valuedOn: '2026-10-07',
  syncedAt: NOW,
}

const stock: InvestmentPosition = {
  ...cdb,
  id: 'inv2',
  externalId: 'ext2',
  name: 'ABCD3',
  kind: 'EQUITY',
  subtype: 'STOCK',
  invested: null,
  profit: Money.of(-1_000),
  rate: null,
  dueOn: null,
  valuedOn: null,
}

const delegate = () => ({
  upsert: vi.fn(),
  findMany: vi.fn(),
  findFirst: vi.fn(),
  deleteMany: vi.fn(),
  createMany: vi.fn(),
  groupBy: vi.fn(),
})

function mockClient() {
  const db = {
    investment: delegate(),
    investmentMovement: delegate(),
    investmentSnapshot: delegate(),
    indexRate: delegate(),
  }
  const client = db as unknown as PrismaClient
  return {
    ...db,
    repo: new PrismaInvestmentRepository(client),
    rates: new PrismaIndexRateRepository(client),
  }
}

const day = (value: string) => new Date(`${value}T00:00:00.000Z`)

describe('PrismaInvestmentRepository', () => {
  it('upserts each position by connection and external id', async () => {
    const { investment, repo } = mockClient()
    await repo.saveAll([cdb])
    const [call] = investment.upsert.mock.calls.map(args => args[0])
    expect(call.where).toEqual({
      tenantId_connectionId_externalId: {
        tenantId: TENANT,
        connectionId: 'conn1',
        externalId: 'ext1',
      },
    })
    expect(call.create).toMatchObject({
      id: 'inv1',
      balanceCents: 105_000n,
      investedCents: 100_000n,
      profitCents: null,
      ratePercent: 102,
      rateIndex: 'CDI',
      fixedAnnualRate: null,
      dueOn: new Date('2028-04-04T00:00:00.000Z'),
    })
    expect(call.update).not.toHaveProperty('id')
  })

  it('reads positions back, rate and dates included', async () => {
    const { investment, repo } = mockClient()
    investment.findMany.mockResolvedValueOnce(
      [cdb, stock].map(position => ({
        id: position.id,
        tenantId: position.tenantId,
        connectionId: position.connectionId,
        externalId: position.externalId,
        ...investmentToRow(position),
      })),
    )
    expect(await repo.list(TENANT)).toEqual([cdb, stock])
    expect(investment.findMany.mock.calls[0]?.[0]).toEqual({
      where: { tenantId: TENANT },
      orderBy: { balanceCents: 'desc' },
    })
  })

  it('keeps a rate that only names its index', () => {
    const row = {
      id: 'inv3',
      tenantId: TENANT,
      connectionId: 'conn1',
      externalId: 'ext3',
      ...investmentToRow({
        ...cdb,
        rate: { percent: null, index: 'IPCA', fixedAnnual: null },
      }),
    }
    expect(investmentFromRow(row).rate).toEqual({
      percent: null,
      index: 'IPCA',
      fixedAnnual: null,
    })
    expect(
      investmentFromRow({ ...row, rateIndex: null, fixedAnnualRate: 6.5 }).rate,
    ).toEqual({ percent: null, index: null, fixedAnnual: 6.5 })
  })

  it('drops the positions of a removed connection', async () => {
    const { investment, repo } = mockClient()
    await repo.deleteByConnection(TENANT, 'conn1')
    expect(investment.deleteMany).toHaveBeenCalledWith({
      where: { tenantId: TENANT, connectionId: 'conn1' },
    })
  })
})

describe('PrismaInvestmentRepository history', () => {
  it('upserts movements by position and external id and reads them back', async () => {
    const { investmentMovement, repo } = mockClient()
    await repo.saveMovements([
      {
        id: 'm1',
        tenantId: TENANT,
        investmentId: 'inv1',
        externalId: 'tx1',
        kind: 'BUY',
        occurredOn: '2026-03-04',
        amountCents: 1_000_000,
        quantity: 10_000,
        unitPrice: 1,
      },
    ])
    const [call] = investmentMovement.upsert.mock.calls.map(args => args[0])
    expect(call.where).toEqual({
      investmentId_externalId: { investmentId: 'inv1', externalId: 'tx1' },
    })
    expect(call.create).toMatchObject({
      id: 'm1',
      occurredOn: day('2026-03-04'),
      amountCents: 1_000_000n,
    })
    expect(call.update).not.toHaveProperty('id')

    investmentMovement.findMany.mockResolvedValueOnce([
      {
        id: 'm1',
        tenantId: TENANT,
        investmentId: 'inv1',
        externalId: 'tx1',
        kind: 'SELL',
        occurredOn: day('2026-08-01'),
        amountCents: 2_500n,
        quantity: null,
        unitPrice: null,
      },
    ])
    expect(await repo.listMovements(TENANT, 'inv1')).toEqual([
      {
        id: 'm1',
        tenantId: TENANT,
        investmentId: 'inv1',
        externalId: 'tx1',
        kind: 'SELL',
        occurredOn: '2026-08-01',
        amountCents: 2_500,
        quantity: null,
        unitPrice: null,
      },
    ])
    expect(investmentMovement.findMany.mock.calls[0]?.[0]).toEqual({
      where: { tenantId: TENANT, investmentId: 'inv1' },
      orderBy: { occurredOn: 'asc' },
    })
  })

  it('lets a real snapshot replace any and an estimated one fill a gap', async () => {
    const { investmentSnapshot, repo } = mockClient()
    const snapshot = {
      tenantId: TENANT,
      investmentId: 'inv1',
      day: '2026-10-08',
      balanceCents: 105_000,
      estimated: false,
    }
    await repo.saveSnapshots([
      snapshot,
      { ...snapshot, day: '2026-10-07', estimated: true },
    ])
    expect(investmentSnapshot.upsert).toHaveBeenCalledWith({
      where: {
        investmentId_day: { investmentId: 'inv1', day: day('2026-10-08') },
      },
      create: { ...snapshot, day: day('2026-10-08'), balanceCents: 105_000n },
      update: { balanceCents: 105_000n, estimated: false },
    })
    expect(investmentSnapshot.createMany).toHaveBeenCalledWith({
      data: [
        {
          ...snapshot,
          day: day('2026-10-07'),
          balanceCents: 105_000n,
          estimated: true,
        },
      ],
      skipDuplicates: true,
    })
    await repo.saveSnapshots([snapshot])
    expect(investmentSnapshot.createMany).toHaveBeenCalledTimes(1)
  })

  it('reads a range with the last snapshot before it, and the first days', async () => {
    const { investmentSnapshot, repo } = mockClient()
    const row = {
      tenantId: TENANT,
      investmentId: 'inv1',
      balanceCents: 100_000n,
      estimated: true,
    }
    investmentSnapshot.findMany
      .mockResolvedValueOnce([{ ...row, day: day('2026-08-01') }])
      .mockResolvedValueOnce([
        { ...row, day: day('2026-09-10'), estimated: false },
      ])
    expect(
      await repo.listSnapshots(TENANT, {
        from: '2026-09-08',
        to: '2026-10-08',
      }),
    ).toEqual([
      { ...row, day: '2026-08-01', balanceCents: 100_000 },
      { ...row, day: '2026-09-10', balanceCents: 100_000, estimated: false },
    ])
    const [before, within] = investmentSnapshot.findMany.mock.calls.map(
      args => args[0],
    )
    expect(before).toEqual({
      where: {
        tenantId: TENANT,
        investmentId: undefined,
        day: { lt: day('2026-09-08') },
      },
      orderBy: [{ investmentId: 'asc' }, { day: 'desc' }],
      distinct: ['investmentId'],
    })
    expect(within.where.day).toEqual({
      gte: day('2026-09-08'),
      lte: day('2026-10-08'),
    })

    investmentSnapshot.groupBy.mockResolvedValueOnce([
      { investmentId: 'inv1', _min: { day: day('2025-10-07') } },
      { investmentId: 'inv2', _min: { day: null } },
    ])
    expect([...(await repo.firstSnapshotDays(TENANT))]).toEqual([
      ['inv1', '2025-10-07'],
    ])
  })
})

describe('PrismaIndexRateRepository', () => {
  it('inserts new daily rates and reads a range and the last day', async () => {
    const { indexRate, rates } = mockClient()
    await rates.save('CDI', [])
    expect(indexRate.createMany).not.toHaveBeenCalled()
    await rates.save('CDI', [{ day: '2026-10-07', value: 0.050788 }])
    expect(indexRate.createMany).toHaveBeenCalledWith({
      data: [{ index: 'CDI', day: day('2026-10-07'), rate: 0.050788 }],
      skipDuplicates: true,
    })

    indexRate.findMany.mockResolvedValueOnce([
      { index: 'CDI', day: day('2026-10-07'), rate: 0.050788 },
    ])
    expect(
      await rates.list('CDI', { from: '2026-10-01', to: '2026-10-08' }),
    ).toEqual([{ day: '2026-10-07', value: 0.050788 }])

    indexRate.findFirst
      .mockResolvedValueOnce({ index: 'CDI', day: day('2026-10-07'), rate: 1 })
      .mockResolvedValueOnce(null)
    expect(await rates.lastDay('CDI')).toBe('2026-10-07')
    expect(await rates.lastDay('CDI')).toBeNull()
  })
})
