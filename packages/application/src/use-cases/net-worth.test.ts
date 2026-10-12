import { describe, expect, it } from 'vitest'
import { Money } from '@cashdeck/domain'
import { type InvestmentPosition } from '@/ports/investments'
import { NotFoundError } from '@/errors/errors'
import { account, fullDeps, transaction } from '@/testing/deps.test-helpers'
import { NOW, TENANT } from '@/testing/scenario.test-helpers'
import { makeNetWorthFromBalancesAndSnapshots } from '@/use-cases/net-worth'
import { InMemoryEntityRepository } from '@/testing/repositories'

function position(
  overrides: Partial<InvestmentPosition> & Pick<InvestmentPosition, 'id'>,
): InvestmentPosition {
  return {
    tenantId: TENANT,
    entityId: 'pf',
    connectionId: 'c1',
    institutionId: 'inst',
    externalId: overrides.id,
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
    balance: Money.of(510000),
    invested: null,
    profit: null,
    syncedAt: NOW,
    ...overrides,
  }
}

async function seed() {
  const deps = fullDeps()
  const accounts = [
    account({ id: 'chk', entityId: 'pf', balance: Money.of(300000) }),
    account({
      id: 'card',
      entityId: 'pf',
      type: 'CREDIT_CARD',
      balance: Money.of(-120000),
    }),
    account({ id: 'usd', entityId: 'pf', balance: Money.of(7000, 'USD') }),
    account({ id: 'pj-chk', entityId: 'pj', balance: Money.of(200000) }),
    account({
      id: 'broker',
      entityId: 'pj',
      type: 'INVESTMENT',
      balance: Money.of(50000),
    }),
  ]
  for (const row of accounts) {
    await deps.accounts.save(row)
  }
  const booked = [
    { id: 't1', accountId: 'chk', bookedOn: '2026-10-05', cents: 800000 },
    { id: 't2', accountId: 'chk', bookedOn: '2026-10-06', cents: -600000 },
    { id: 't3', accountId: 'chk', bookedOn: '2026-09-10', cents: -50000 },
    { id: 't4', accountId: 'card', bookedOn: '2026-09-15', cents: -40000 },
    { id: 't5', accountId: 'card', bookedOn: '2026-10-02', cents: 200000 },
    { id: 't6', accountId: 'chk', bookedOn: '2026-10-20', cents: -1000 },
    { id: 't7', accountId: 'chk', bookedOn: '2025-06-01', cents: -1000 },
  ]
  for (const row of booked) {
    await deps.transactions.save(
      transaction({ ...row, amount: Money.of(row.cents) }),
    )
  }
  await deps.transactions.save(
    transaction({
      id: 'ghost',
      accountId: 'chk',
      bookedOn: '2026-10-07',
      amount: Money.of(-999),
      provisional: true,
    }),
  )
  await deps.investments.saveAll([
    position({ id: 'cdb' }),
    position({ id: 'closed', status: 'CLOSED', balance: Money.of(1000) }),
    position({ id: 'abroad', balance: Money.of(9000, 'USD') }),
  ])
  await deps.investments.saveSnapshots([
    {
      tenantId: TENANT,
      investmentId: 'cdb',
      day: '2026-08-31',
      balanceCents: 500000,
      estimated: true,
    },
    {
      tenantId: TENANT,
      investmentId: 'cdb',
      day: '2026-09-30',
      balanceCents: 505000,
      estimated: false,
    },
    {
      tenantId: TENANT,
      investmentId: 'closed',
      day: '2026-09-30',
      balanceCents: 1000,
      estimated: false,
    },
  ])
  return deps
}

describe('net worth', () => {
  it('rolls balances back by month end and compares with last month and a year ago', async () => {
    const deps = await seed()
    const view = await makeNetWorthFromBalancesAndSnapshots(deps)(TENANT, {
      months: 6,
    })
    expect(view.asOf).toBe('2026-10-08')
    expect(view.current).toEqual({
      cash: { cents: 500000, currency: 'BRL' },
      investments: { cents: 560000, currency: 'BRL' },
      cardDebt: { cents: 120000, currency: 'BRL' },
      assets: { cents: 1060000, currency: 'BRL' },
      liabilities: { cents: 120000, currency: 'BRL' },
      total: { cents: 940000, currency: 'BRL' },
    })
    expect(view.fromLastMonth).toEqual({
      amount: { cents: 404000, currency: 'BRL' },
      percent: 75.4,
    })
    expect(view.fromYearAgo).toEqual({
      amount: { cents: 820000, currency: 'BRL' },
      percent: 683.3,
    })
    expect(view.series.map(point => point.on)).toEqual([
      '2026-04-30',
      '2026-05-31',
      '2026-06-30',
      '2026-07-31',
      '2026-08-31',
      '2026-09-30',
      '2026-10-08',
    ])
    expect(view.series.at(-2)).toEqual({
      on: '2026-09-30',
      assets: { cents: 856000, currency: 'BRL' },
      liabilities: { cents: 320000, currency: 'BRL' },
      total: { cents: 536000, currency: 'BRL' },
    })
    expect(
      view.entities.map(entity => [entity.kind, entity.current.total.cents]),
    ).toEqual([
      ['PF', 690000],
      ['PJ', 250000],
    ])
  })

  it('scopes to one entity and gives no percent from nothing', async () => {
    const deps = await seed()
    const view = await makeNetWorthFromBalancesAndSnapshots(deps)(TENANT, {
      entity: 'PJ',
      months: 12,
    })
    expect(view.series).toHaveLength(13)
    expect(view.current.total.cents).toBe(250000)
    expect(view.fromLastMonth.percent).toBe(0)
    expect(view.entities.map(entity => entity.kind)).toEqual(['PJ'])
    const empty = fullDeps()
    const nothing = await makeNetWorthFromBalancesAndSnapshots({
      ...empty,
      entities: new InMemoryEntityRepository([]),
    })(TENANT, { months: 12 })
    expect(nothing.fromYearAgo.percent).toBeNull()
    await expect(
      makeNetWorthFromBalancesAndSnapshots({
        ...empty,
        entities: new InMemoryEntityRepository([]),
      })(TENANT, { entity: 'PF', months: 12 }),
    ).rejects.toThrow(NotFoundError)
  })
})
