import { type PrismaClient } from '@prisma/client'
import { describe, expect, it, vi } from 'vitest'
import { type InvestmentPosition } from '@cashdeck/application'
import { Money } from '@cashdeck/domain'
import {
  investmentFromRow,
  investmentToRow,
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

function mockClient() {
  const investment = {
    upsert: vi.fn(),
    findMany: vi.fn(),
    deleteMany: vi.fn(),
  }
  const repo = new PrismaInvestmentRepository({
    investment,
  } as unknown as PrismaClient)
  return { investment, repo }
}

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
