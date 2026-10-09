import { Money } from '@cashdeck/domain'
import { describe, expect, it } from 'vitest'
import {
  account,
  bill,
  fullDeps,
  transaction,
} from '@/testing/deps.test-helpers'
import { TENANT } from '@/testing/scenario.test-helpers'
import {
  cardsSummary,
  flowEntries,
  makeInsightsOverview,
  percentChange,
  periodRanges,
} from '@/use-cases/insights'

const CREDIT = {
  limit: Money.of(100_000),
  available: Money.of(75_000),
  closesOn: '2026-10-20',
  dueOn: '2026-10-27',
  brand: 'VISA',
  openBill: null,
}

async function seeded() {
  const deps = fullDeps()
  await deps.categories.save({
    id: 'food',
    tenantId: TENANT,
    key: 'restaurants',
    name: 'Restaurants',
    icon: 'restaurant',
    parentId: null,
  })
  await deps.accounts.save(account({ id: 'checking', entityId: 'pf' }))
  await deps.accounts.save(
    account({
      id: 'card',
      entityId: 'pf',
      type: 'CREDIT_CARD',
      balance: Money.of(-25_000),
      credit: CREDIT,
    }),
  )
  await deps.accounts.save(
    account({ id: 'broker', entityId: 'pf', type: 'INVESTMENT' }),
  )
  await deps.accounts.save(
    account({ id: 'usd', entityId: 'pf', balance: Money.of(100, 'USD') }),
  )
  await deps.accounts.save(account({ id: 'company', entityId: 'pj' }))
  const lines = [
    { id: 'salary', accountId: 'checking', cents: 500_000, on: '2026-10-01' },
    {
      id: 'market',
      accountId: 'checking',
      cents: -2_000,
      on: '2026-10-02',
      categoryId: 'food',
      description: 'Mercado',
    },
    {
      id: 'shop',
      accountId: 'card',
      cents: -3_000,
      on: '2026-10-05',
      merchant: 'Loja',
    },
    {
      id: 'paid-bill',
      accountId: 'checking',
      cents: -10_000,
      on: '2026-10-06',
      description: 'PAGAMENTO FATURA',
    },
    { id: 'invest', accountId: 'broker', cents: -9_999, on: '2026-10-03' },
    { id: 'abroad', accountId: 'usd', cents: -50, on: '2026-10-03' },
    {
      id: 'september',
      accountId: 'checking',
      cents: -1_000,
      on: '2026-09-03',
      categoryId: 'food',
    },
    { id: 'late-sept', accountId: 'card', cents: -9_000, on: '2026-09-20' },
    {
      id: 'company-buy',
      accountId: 'company',
      cents: -7_000,
      on: '2026-10-04',
    },
  ]
  for (const line of lines) {
    await deps.transactions.save(
      transaction({
        id: line.id,
        accountId: line.accountId,
        amount: Money.of(line.cents, line.accountId === 'usd' ? 'USD' : 'BRL'),
        bookedOn: line.on,
        description: line.description ?? line.id,
        categoryId: line.categoryId ?? null,
        merchant: line.merchant ?? null,
      }),
    )
  }
  await deps.bills.save(
    bill({ id: 'soon', amount: Money.of(1_500), dueDate: '2026-10-10' }),
  )
  await deps.bills.save(bill({ id: 'later', dueDate: '2026-10-30' }))
  await deps.bills.save({
    ...bill({ id: 'settled', dueDate: '2026-10-09' }),
    status: 'PAID',
  })
  return deps
}

const cents = (value: number) => expect.objectContaining({ cents: value })

describe('insights overview', () => {
  it('compares this month with the same days of the last one', async () => {
    const deps = await seeded()
    const overview = await makeInsightsOverview(deps)(TENANT, {
      entity: 'PF',
      period: '1m',
    })
    expect(overview.range).toEqual({ from: '2026-10-01', to: '2026-10-08' })
    expect(overview.previousRange).toEqual({
      from: '2026-09-01',
      to: '2026-09-30',
    })
    expect(overview.spend).toMatchObject({
      total: cents(5_000),
      previous: cents(1_000),
      changePercent: 400,
      topMerchants: [
        { name: 'Loja', total: cents(3_000), count: 1 },
        { name: 'Mercado', total: cents(2_000), count: 1 },
      ],
    })
    expect(overview.spend.series).toHaveLength(8)
    expect(overview.spend.series.at(-1)).toEqual({
      day: '2026-10-08',
      cumulative: cents(5_000),
    })
    expect(overview.spend.previousSeries).toHaveLength(30)
    expect(overview.spend.previousSeries.at(-1)?.cumulative.cents).toBe(10_000)
    expect(overview.categories).toEqual({
      total: cents(5_000),
      items: [
        {
          categoryId: null,
          key: null,
          name: null,
          icon: null,
          total: cents(3_000),
          sharePercent: 60,
          changePercent: null,
        },
        {
          categoryId: 'food',
          key: 'restaurants',
          name: 'Restaurants',
          icon: 'restaurant',
          total: cents(2_000),
          sharePercent: 40,
          changePercent: 100,
        },
      ],
    })
    expect(overview.flow).toEqual({
      income: cents(500_000),
      expenses: cents(5_000),
      result: cents(495_000),
    })
    expect(overview.cards).toEqual({
      bill: cents(25_000),
      dueOn: '2026-10-27',
      count: 1,
      limit: cents(100_000),
      used: cents(25_000),
      usedPercent: 25,
    })
    expect(overview.billsDue).toEqual({
      days: 7,
      total: cents(1_500),
      count: 1,
    })
  })

  it('adds every entity when none is picked', async () => {
    const deps = await seeded()
    const overview = await makeInsightsOverview(deps)(TENANT, {
      period: '1w',
    })
    expect(overview.range).toEqual({ from: '2026-10-02', to: '2026-10-08' })
    expect(overview.spend.total.cents).toBe(12_000)
    expect(overview.spend.changePercent).toBeNull()
  })

  it('compares nothing when history starts inside the previous period', async () => {
    const deps = await seeded()
    await deps.transactions.save(
      transaction({
        id: 'first-synced',
        accountId: 'checking',
        amount: Money.of(-500),
        bookedOn: '2025-10-20',
        categoryId: 'food',
      }),
    )
    const overview = await makeInsightsOverview(deps)(TENANT, {
      entity: 'PF',
      period: '1y',
    })
    expect(overview.spend.previous.cents).toBe(0)
    expect(overview.spend.changePercent).toBeNull()
    expect(overview.spend.previousSeries).toEqual([])
    expect(overview.categories.items.map(item => item.changePercent)).toEqual([
      null,
      null,
    ])
  })

  it('answers an entity without accounts with zeros', async () => {
    const deps = fullDeps()
    const overview = await makeInsightsOverview(deps)(TENANT, {
      entity: 'PJ',
      period: '6m',
    })
    expect(overview.spend.total.cents).toBe(0)
    expect(overview.categories.items).toEqual([])
    expect(overview.cards).toBeNull()
    expect(
      await flowEntries(deps, TENANT, [], new Map(), overview.range),
    ).toEqual([])
  })
})

describe('insight helpers', () => {
  it('builds the ranges of each period', () => {
    expect(periodRanges('6m', '2026-10-08')).toEqual({
      range: { from: '2026-05-01', to: '2026-10-08' },
      previousRange: { from: '2025-11-01', to: '2026-04-30' },
    })
    expect(periodRanges('1y', '2026-10-08')).toEqual({
      range: { from: '2025-11-01', to: '2026-10-08' },
      previousRange: { from: '2024-11-01', to: '2025-10-31' },
    })
  })

  it('reads the change only against a previous amount', () => {
    expect(percentChange(150, 100)).toBe(50)
    expect(percentChange(50, 100)).toBe(-50)
    expect(percentChange(50, 0)).toBeNull()
  })

  it('sums cards without a credit line and past due dates', () => {
    const plain = account({
      id: 'plain',
      type: 'CREDIT_CARD',
      balance: Money.of(500),
    })
    expect(cardsSummary([plain], new Map(), '2026-10-08')).toEqual({
      bill: cents(0),
      dueOn: null,
      count: 1,
      limit: null,
      used: null,
      usedPercent: null,
    })
    const past = account({
      id: 'past',
      type: 'CREDIT_CARD',
      credit: { ...CREDIT, dueOn: '2026-09-27' },
    })
    const dues = new Map([['past', '2026-09-27']])
    expect(cardsSummary([past, plain], dues, '2026-10-08')?.dueOn).toBe(
      '2026-09-27',
    )
  })
})
