import { Money } from '@cashdeck/domain'
import { describe, expect, it } from 'vitest'
import {
  type InvestmentPosition,
  type ProviderInvestment,
} from '@/ports/investments'
import { type ProviderItem } from '@/ports/providers'
import { fullDeps } from '@/testing/deps.test-helpers'
import { FakeOpenFinanceProvider } from '@/testing/providers'
import { NOW, TENANT } from '@/testing/scenario.test-helpers'
import { makeListInvestments } from '@/use-cases/investments'
import { makeOpenFinance } from '@/use-cases/open-finance'

const ITEM = '5d1e2f3a-4b5c-4d6e-8f70-1a2b3c4d5e6f'

const cdb: ProviderInvestment = {
  externalId: 'inv-cdb',
  name: 'CDB Banco Exemplo',
  kind: 'FIXED_INCOME',
  subtype: 'CDB',
  issuer: 'BANCO EXEMPLO S.A.',
  status: 'ACTIVE',
  balanceCents: 105_000,
  investedCents: 100_000,
  profitCents: null,
  currency: 'BRL',
  code: null,
  unitPrice: null,
  quantity: 1,
  rate: { percent: 102, index: 'CDI', fixedAnnual: 0 },
  lastMonthRate: null,
  lastTwelveMonthsRate: null,
  dueOn: '2028-04-04',
  valuedOn: '2026-10-07',
}

const sold: ProviderInvestment = {
  ...cdb,
  externalId: 'inv-sold',
  name: 'FII Exemplo',
  kind: 'EQUITY',
  subtype: 'REAL_ESTATE_FUND',
  status: 'CLOSED',
  balanceCents: 0,
  investedCents: null,
  rate: null,
  dueOn: null,
}

function aggregated(item: Partial<ProviderItem> = {}) {
  const provider = new FakeOpenFinanceProvider(
    [
      {
        externalId: 'acc-1',
        name: 'BANCO EXEMPLO S.A.',
        type: 'CHECKING',
        balanceCents: 1_000,
        currency: 'BRL',
      },
    ],
    [],
    [
      {
        itemId: ITEM,
        institutionName: 'MeuPluggy',
        status: 'UPDATED',
        lastUpdatedAt: null,
        ...item,
      },
    ],
  )
  provider.connectors = [
    {
      id: 1,
      name: 'Banco Exemplo',
      imageUrl: 'https://logo.example/1.svg',
      primaryColor: 'FF0000',
    },
  ]
  provider.investments = [cdb, sold]
  return provider
}

async function connected(provider: FakeOpenFinanceProvider) {
  const deps = fullDeps({ openFinance: provider })
  const of = makeOpenFinance(deps)
  const { connectionId } = await of.connect(TENANT, {
    itemId: ITEM,
    entity: 'PF',
    accountIds: ['acc-1'],
  })
  return { deps, of, connectionId }
}

describe('investment sync', () => {
  it('stores the positions of an item under the bank of its accounts', async () => {
    const provider = aggregated()
    const { deps, of, connectionId } = await connected(provider)
    await of.sync(TENANT, connectionId)
    const [account] = await deps.accounts.list(TENANT)
    const stored = await deps.investments.list(TENANT)
    expect(stored).toHaveLength(2)
    expect(stored[0]).toMatchObject({
      entityId: 'pf',
      connectionId,
      institutionId: account?.institutionId,
      balance: Money.of(105_000),
      invested: Money.of(100_000),
      profit: null,
      syncedAt: NOW,
    })

    const [first] = stored
    provider.investments = [
      { ...cdb, balanceCents: 106_000, profitCents: 6_000 },
    ]
    await of.sync(TENANT, connectionId)
    const again = await deps.investments.list(TENANT)
    expect(again.map(row => [row.id, row.balance.cents])).toEqual([
      [first?.id, 106_000],
      [stored[1]?.id, 0],
    ])
    expect(again[0]?.profit?.cents).toBe(6_000)
  })

  it('keeps the last positions when the provider fails and drops them with the connection', async () => {
    const provider = aggregated()
    const { deps, of, connectionId } = await connected(provider)
    await of.sync(TENANT, connectionId)
    provider.investments = new Error('investments unavailable')
    await of.sync(TENANT, connectionId)
    expect(await deps.investments.list(TENANT)).toHaveLength(2)
    await of.remove(TENANT, connectionId)
    expect(await deps.investments.list(TENANT)).toEqual([])
  })

  it('files positions under the connection when no account names a bank', async () => {
    const provider = aggregated({ institutionName: 'Banco Direto' })
    const { deps, of, connectionId } = await connected(provider)
    await of.sync(TENANT, connectionId)
    const connection = await deps.connections.findById(TENANT, connectionId)
    const [position] = await deps.investments.list(TENANT)
    expect(position?.institutionId).toBe(connection?.institutionId)
  })
})

function position(
  overrides: Partial<InvestmentPosition> & { id: string },
): InvestmentPosition {
  return {
    tenantId: TENANT,
    entityId: 'pf',
    connectionId: 'conn',
    institutionId: 'bank-a',
    externalId: overrides.id,
    name: `Position ${overrides.id}`,
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
    balance: Money.of(10_000),
    invested: null,
    profit: null,
    syncedAt: NOW,
    ...overrides,
  }
}

async function listing(positions: InvestmentPosition[]) {
  const deps = fullDeps()
  await deps.institutions.ensure({
    id: 'bank-a',
    tenantId: TENANT,
    name: 'Banco A',
    manual: false,
    imageUrl: 'https://logo.example/a.svg',
    primaryColor: null,
  })
  await deps.institutions.ensure({
    id: 'bank-b',
    tenantId: TENANT,
    name: 'Corretora B',
    manual: false,
  })
  await deps.investments.saveAll(positions)
  return makeListInvestments(deps)
}

describe('list investments', () => {
  it('sums held positions by institution and kind', async () => {
    const later = new Date(NOW.getTime() + 60_000)
    const list = await listing([
      position({
        id: 'cdb',
        balance: Money.of(105_000),
        invested: Money.of(100_000),
        rate: { percent: 102, index: 'CDI', fixedAnnual: null },
        dueOn: '2028-04-04',
      }),
      position({
        id: 'fund',
        institutionId: 'bank-b',
        kind: 'FUND',
        subtype: 'MULTIMARKET_FUND',
        balance: Money.of(20_000),
        invested: Money.of(25_000),
        profit: Money.of(-5_000),
        lastTwelveMonthsRate: 8.5,
        syncedAt: later,
      }),
      position({
        id: 'stock',
        institutionId: 'bank-b',
        kind: 'EQUITY',
        subtype: 'STOCK',
        name: 'ABCD3',
        status: 'PENDING',
        balance: Money.of(20_000),
      }),
      position({ id: 'gone', status: 'CLOSED', balance: Money.of(0) }),
      position({ id: 'company', entityId: 'pj' }),
      position({
        id: 'abroad',
        kind: 'ETF',
        balance: Money.of(9_000, 'USD'),
      }),
    ])
    const view = await list(TENANT, 'PF')
    expect(view.total).toEqual({ cents: 145_000, currency: 'BRL' })
    expect(view.invested.cents).toBe(125_000)
    expect(view.profit.cents).toBe(0)
    expect(view.syncedAt).toBe(later.toISOString())
    expect(view.institutions).toEqual([
      {
        institutionId: 'bank-a',
        institution: 'Banco A',
        logo: { imageUrl: 'https://logo.example/a.svg', color: null },
        total: { cents: 105_000, currency: 'BRL' },
        count: 1,
      },
      {
        institutionId: 'bank-b',
        institution: 'Corretora B',
        logo: null,
        total: { cents: 40_000, currency: 'BRL' },
        count: 2,
      },
    ])
    expect(view.kinds.map(row => [row.kind, row.total.cents])).toEqual([
      ['FIXED_INCOME', 105_000],
      ['EQUITY', 20_000],
      ['FUND', 20_000],
    ])
    expect(view.positions.map(row => row.name)).toEqual([
      'Position cdb',
      'ABCD3',
      'Position fund',
      'Position abroad',
    ])
    expect(view.positions[0]).toMatchObject({
      entityKind: 'PF',
      profit: { cents: 5_000 },
      profitPercent: 5,
      rate: { percent: 102, index: 'CDI' },
      dueOn: '2028-04-04',
    })
    expect(view.positions[1]).toMatchObject({
      status: 'PENDING',
      invested: null,
      profit: null,
      profitPercent: null,
    })
    expect(view.positions[2]?.profitPercent).toBe(-20)
  })

  it('lists every entity, and nothing before the first sync', async () => {
    const list = await listing([
      position({ id: 'pf-cdb' }),
      position({ id: 'pj-cdb', entityId: 'pj', institutionId: 'unknown' }),
      position({ id: 'free', invested: Money.of(0), profit: Money.of(10) }),
    ])
    const view = await list(TENANT)
    expect(view.positions.map(row => row.entityKind).sort()).toEqual([
      'PF',
      'PF',
      'PJ',
    ])
    expect(view.positions.find(row => row.id === 'pj-cdb')).toMatchObject({
      institution: '',
      logo: null,
    })
    expect(view.positions.find(row => row.id === 'free')?.profitPercent).toBe(
      null,
    )
    expect(await (await listing([]))(TENANT)).toMatchObject({
      total: { cents: 0 },
      syncedAt: null,
      institutions: [],
      positions: [],
    })
  })
})
