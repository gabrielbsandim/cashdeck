import { addDays, Money } from '@cashdeck/domain'
import { describe, expect, it } from 'vitest'
import {
  type InvestmentPosition,
  type ProviderInvestment,
  type ProviderMovement,
} from '@/ports/investments'
import { fullDeps } from '@/testing/deps.test-helpers'
import { FakeMarketData } from '@/testing/investments'
import { FakeOpenFinanceProvider } from '@/testing/providers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { makeOpenFinance } from '@/use-cases/open-finance'

const ITEM = '7a1e2f3a-4b5c-4d6e-8f70-1a2b3c4d5e6f'
const TODAY = '2026-10-08'
const day = (offset: number) => addDays(TODAY, offset)
const ALL = { from: '2000-01-01', to: '2100-01-01' }

const base: ProviderInvestment = {
  externalId: 'cdb',
  name: 'CDB Banco Exemplo',
  kind: 'FIXED_INCOME',
  subtype: 'CDB',
  issuer: 'BANCO EXEMPLO S.A.',
  status: 'ACTIVE',
  balanceCents: 120_000,
  investedCents: null,
  profitCents: null,
  currency: 'BRL',
  code: 'CDB0123ABC',
  unitPrice: 1.2,
  quantity: 1000,
  rate: { percent: 100, index: 'CDI', fixedAnnual: null },
  lastMonthRate: null,
  lastTwelveMonthsRate: null,
  dueOn: '2028-04-04',
  valuedOn: TODAY,
}

const movement = (
  overrides: Partial<ProviderMovement> & { externalId: string },
): ProviderMovement => ({
  kind: 'BUY',
  occurredOn: day(-180),
  amountCents: 100_000,
  quantity: null,
  unitPrice: null,
  ...overrides,
})

async function synced(
  investments: ProviderInvestment[],
  movements: Record<string, ProviderMovement[] | Error> = {},
  market = new FakeMarketData(),
) {
  const provider = new FakeOpenFinanceProvider(
    [
      {
        externalId: 'acc-1',
        name: 'Banco Exemplo',
        type: 'CHECKING',
        balanceCents: 1_000,
        currency: 'BRL',
      },
    ],
    [],
    [
      {
        itemId: ITEM,
        institutionName: 'Banco Exemplo',
        status: 'UPDATED',
        lastUpdatedAt: null,
      },
    ],
  )
  provider.investments = investments
  provider.movements = new Map(Object.entries(movements))
  const deps = fullDeps({ openFinance: provider, marketData: market })
  const of = makeOpenFinance(deps)
  const { connectionId } = await of.connect(TENANT, {
    itemId: ITEM,
    entity: 'PF',
    accountIds: ['acc-1'],
  })
  await of.sync(TENANT, connectionId)
  const idOf = async (externalId: string) =>
    (await deps.investments.list(TENANT)).find(
      row => row.externalId === externalId,
    )?.id ?? ''
  const snapshots = async (externalId: string) =>
    deps.investments.listSnapshots(TENANT, ALL, await idOf(externalId))
  const valueOn = async (externalId: string, offset: number) =>
    (await snapshots(externalId)).find(row => row.day === day(offset))
  return { deps, of, provider, market, connectionId, snapshots, valueOn }
}

describe('investment history on sync', () => {
  it('stores movements and rebuilds a year between known unit prices', async () => {
    const { deps, snapshots, valueOn } = await synced([base], {
      cdb: [
        movement({ externalId: 'm1', quantity: 1000, unitPrice: 1 }),
        movement({ externalId: 'm2', kind: 'TAX', amountCents: 500 }),
      ],
    })
    const movements = await deps.investments.listMovements(TENANT)
    expect(movements.map(row => [row.externalId, row.kind])).toEqual([
      ['m1', 'BUY'],
      ['m2', 'TAX'],
    ])
    const rows = await snapshots('cdb')
    expect(rows).toHaveLength(367)
    expect(rows.filter(row => !row.estimated).map(row => row.day)).toEqual([
      TODAY,
    ])
    expect(await valueOn('cdb', 0)).toMatchObject({ balanceCents: 120_000 })
    expect((await valueOn('cdb', -366))?.balanceCents).toBe(0)
    expect((await valueOn('cdb', -181))?.balanceCents).toBe(0)
    expect((await valueOn('cdb', -180))?.balanceCents).toBe(100_000)
    expect((await valueOn('cdb', -90))?.balanceCents).toBe(
      Math.round(1000 * 1.2 ** 0.5 * 100),
    )
    expect(await valueOn('cdb', -1)).toMatchObject({
      balanceCents: Math.round(1000 * 1.2 ** (179 / 180) * 100),
      estimated: true,
    })
  })

  it('counts units through buys and sells and holds the last price', async () => {
    const { valueOn } = await synced(
      [
        {
          ...base,
          externalId: 'fund',
          kind: 'FUND',
          code: '12.345.678/0001-90',
          unitPrice: null,
          quantity: 10,
        },
      ],
      {
        fund: [
          movement({
            externalId: 'buy',
            occurredOn: day(-200),
            quantity: 15,
            unitPrice: 50,
          }),
          movement({
            externalId: 'sell',
            kind: 'SELL',
            occurredOn: day(-100),
            quantity: 5,
            unitPrice: 60,
          }),
        ],
      },
    )
    expect((await valueOn('fund', -201))?.balanceCents).toBe(0)
    expect((await valueOn('fund', -200))?.balanceCents).toBe(75_000)
    expect((await valueOn('fund', -150))?.balanceCents).toBe(
      Math.round(15 * 50 * (60 / 50) ** 0.5 * 100),
    )
    expect((await valueOn('fund', -100))?.balanceCents).toBe(60_000)
    expect((await valueOn('fund', -1))?.balanceCents).toBe(60_000)
  })

  it('prices tickers by the last close and falls back to a flat balance', async () => {
    const market = new FakeMarketData()
    market.closes.set('ABCD11', [
      { day: day(-300), value: 90 },
      { day: day(-200), value: 100 },
      { day: day(-1), value: 0 },
      { day: day(-1), value: 104 },
    ])
    const { valueOn } = await synced(
      [
        {
          ...base,
          externalId: 'etf',
          kind: 'OTHER',
          code: ' abcd11 ',
          quantity: 100,
          balanceCents: 1_050_000,
        },
        {
          ...base,
          externalId: 'stock',
          kind: 'EQUITY',
          code: 'EFGH3',
          quantity: 10,
          balanceCents: 30_000,
        },
        {
          ...base,
          externalId: 'c6',
          code: null,
          quantity: null,
          balanceCents: 50_000,
        },
      ],
      {
        etf: [
          movement({ externalId: 'b1', occurredOn: day(-200), quantity: 40 }),
        ],
      },
      market,
    )
    expect(market.requests).toContain(`closes:ABCD11:${day(-373)}:${TODAY}`)
    expect((await valueOn('etf', -366))?.balanceCents).toBe(60 * 90 * 100)
    expect((await valueOn('etf', -201))?.balanceCents).toBe(60 * 90 * 100)
    expect((await valueOn('etf', -200))?.balanceCents).toBe(100 * 100 * 100)
    expect((await valueOn('etf', -1))?.balanceCents).toBe(100 * 104 * 100)
    expect((await valueOn('stock', -300))?.balanceCents).toBe(30_000)
    expect((await valueOn('c6', -300))?.balanceCents).toBe(50_000)
    expect((await valueOn('c6', -300))?.estimated).toBe(true)
  })

  it('rebuilds only once, keeps real snapshots and refreshes CDI from the last day', async () => {
    const market = new FakeMarketData()
    market.cdi = [
      { day: day(-2), value: 0.05 },
      { day: day(-1), value: 0.051 },
    ]
    const { deps, of, provider, connectionId, valueOn } = await synced(
      [{ ...base, unitPrice: null, quantity: null }],
      {},
      market,
    )
    expect(market.requests).toContain(`cdi:${day(-400)}:${TODAY}`)
    expect(await deps.indexRates.lastDay('CDI')).toBe(day(-1))

    provider.investments = [{ ...base, balanceCents: 121_000 }]
    await of.sync(TENANT, connectionId)
    expect(market.requests.filter(row => row.startsWith('cdi'))).toEqual([
      `cdi:${day(-400)}:${TODAY}`,
      `cdi:${TODAY}:${TODAY}`,
    ])
    expect(await valueOn('cdb', 0)).toMatchObject({
      balanceCents: 121_000,
      estimated: false,
    })
    expect((await valueOn('cdb', -300))?.balanceCents).toBe(120_000)

    await deps.indexRates.save('CDI', [{ day: TODAY, value: 0.05 }])
    await of.sync(TENANT, connectionId)
    expect(market.requests.filter(row => row.startsWith('cdi'))).toHaveLength(2)
  })

  it('skips a position that fails and closed or stale ones', async () => {
    const market = new FakeMarketData()
    market.closes.set('ABCD11', new Error('quotes unavailable'))
    market.cdi = new Error('central bank down')
    const provider = [
      { ...base, externalId: 'etf', kind: 'ETF' as const, code: 'ABCD11' },
      { ...base, externalId: 'gone', status: 'CLOSED' as const },
      { ...base, externalId: 'kept' },
    ]
    const { snapshots } = await synced(provider, {
      kept: new Error('movements unavailable'),
    })
    expect(await snapshots('gone')).toEqual([])
    expect(await snapshots('kept')).toHaveLength(367)

    const failing = await synced(provider, {}, market)
    expect(
      (await failing.snapshots('etf')).map(row => [row.day, row.estimated]),
    ).toEqual([[TODAY, false]])
    expect(await failing.snapshots('kept')).toHaveLength(367)
    expect(await failing.deps.indexRates.lastDay('CDI')).toBeNull()

    const [held] = await failing.deps.investments.list(TENANT)
    await failing.deps.investments.saveAll([
      {
        ...(held as InvestmentPosition),
        id: 'stale-id',
        externalId: 'stale',
        status: 'ACTIVE',
        balance: Money.of(1),
      },
    ])
    await failing.of.sync(TENANT, failing.connectionId)
    expect(await failing.snapshots('stale')).toEqual([])
  })
})
