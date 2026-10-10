import { Money } from '@cashdeck/domain'
import { describe, expect, it } from 'vitest'
import { type InvestmentPosition } from '@/ports/investments'
import { InMemoryInvestmentRepository } from '@/testing/investments'

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
