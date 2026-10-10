import { Money } from '@cashdeck/domain'
import { describe, expect, it } from 'vitest'
import { type InvestmentPosition } from '@/ports/investments'
import {
  InMemoryIndexRateRepository,
  InMemoryInvestmentRepository,
} from '@/testing/investments'

const row = (
  id: string,
  tenantId: string,
  connectionId: string,
): InvestmentPosition => ({
  id,
  tenantId,
  entityId: 'pf',
  connectionId,
  institutionId: 'bank',
  externalId: 'same',
  name: 'CDB',
  kind: 'FIXED_INCOME',
  subtype: 'CDB',
  issuer: null,
  status: 'ACTIVE',
  quantity: null,
  rate: null,
  lastMonthRate: null,
  lastTwelveMonthsRate: null,
  dueOn: null,
  valuedOn: null,
  balance: Money.of(100),
  invested: null,
  profit: null,
  syncedAt: new Date('2026-10-08T12:00:00Z'),
})

describe('InMemoryInvestmentRepository', () => {
  it('deletes only the positions of one tenant connection', async () => {
    const repo = new InMemoryInvestmentRepository()
    await repo.saveAll([
      row('a', 't1', 'c1'),
      row('b', 't1', 'c2'),
      row('c', 't2', 'c1'),
    ])
    await repo.deleteByConnection('t1', 'c1')
    expect((await repo.list('t1')).map(position => position.id)).toEqual(['b'])
    expect((await repo.list('t2')).map(position => position.id)).toEqual(['c'])
  })
})

const snapshot = (
  investmentId: string,
  day: string,
  balanceCents: number,
  estimated: boolean,
  tenantId = 't1',
) => ({ tenantId, investmentId, day, balanceCents, estimated })

describe('InMemoryInvestmentRepository history', () => {
  it('keeps a real snapshot over an estimated one and drops history with the connection', async () => {
    const repo = new InMemoryInvestmentRepository()
    await repo.saveAll([row('a', 't1', 'c1'), row('b', 't1', 'c2')])
    await repo.saveSnapshots([
      snapshot('a', '2026-10-01', 100, false),
      snapshot('a', '2026-10-01', 90, true),
      snapshot('a', '2026-09-01', 80, true),
      snapshot('a', '2026-09-01', 85, false),
      snapshot('b', '2026-08-01', 70, true),
      snapshot('x', '2026-07-01', 60, true, 't2'),
    ])
    await repo.saveMovements([
      {
        id: 'm1',
        tenantId: 't1',
        investmentId: 'a',
        externalId: 'e1',
        kind: 'BUY',
        occurredOn: '2026-09-01',
        amountCents: 80,
        quantity: null,
        unitPrice: null,
      },
      {
        id: 'm2',
        tenantId: 't1',
        investmentId: 'b',
        externalId: 'e1',
        kind: 'SELL',
        occurredOn: '2026-09-02',
        amountCents: 10,
        quantity: null,
        unitPrice: null,
      },
    ])
    expect(
      (
        await repo.listSnapshots('t1', { from: '2026-09-15', to: '2026-10-31' })
      ).map(row => [row.investmentId, row.day, row.balanceCents]),
    ).toEqual([
      ['b', '2026-08-01', 70],
      ['a', '2026-09-01', 85],
      ['a', '2026-10-01', 100],
    ])
    expect([...(await repo.firstSnapshotDays('t1'))]).toEqual([
      ['a', '2026-09-01'],
      ['b', '2026-08-01'],
    ])
    expect((await repo.listMovements('t1')).map(row => row.id)).toEqual([
      'm1',
      'm2',
    ])
    await repo.deleteByConnection('t1', 'c1')
    expect((await repo.listMovements('t1')).map(row => row.id)).toEqual(['m2'])
    expect(
      await repo.listSnapshots(
        't1',
        { from: '2026-01-01', to: '2026-12-31' },
        'a',
      ),
    ).toEqual([])
    expect(
      await repo.listSnapshots('t2', { from: '2026-01-01', to: '2026-12-31' }),
    ).toHaveLength(1)
  })
})

describe('InMemoryIndexRateRepository', () => {
  it('reads nothing for an index never stored', async () => {
    const repo = new InMemoryIndexRateRepository()
    expect(await repo.lastDay('CDI')).toBeNull()
    expect(
      await repo.list('CDI', { from: '2026-01-01', to: '2026-12-31' }),
    ).toEqual([])
  })
})
