import { Money } from '@cashdeck/domain'
import { describe, expect, it } from 'vitest'
import {
  account,
  bill,
  fullDeps,
  transaction,
} from '@/testing/deps.test-helpers'
import { NOW, TENANT } from '@/testing/scenario.test-helpers'
import { makeMonthlyInsights } from '@/use-cases/monthly-insights'
import { makeSubscriptions } from '@/use-cases/subscriptions'

const CREDIT = {
  limit: Money.of(100_000),
  available: Money.of(75_000),
  closesOn: '2026-10-20',
  dueOn: '2026-10-27',
  brand: 'VISA',
}

const CATEGORIES = [
  ['food', 'restaurants'],
  ['fun', 'leisure'],
  ['gift', 'gifts'],
  ['travel', 'travel'],
  ['tax', 'taxes'],
] as const

type Line = {
  id: string
  accountId?: string
  cents: number
  on: string
  categoryId?: string
  description?: string
}

const routine = (month: string): Line[] => [
  { id: `salary-${month}`, cents: 500_000, on: `${month}-01` },
  {
    id: `food-${month}`,
    cents: -10_000,
    on: `${month}-02`,
    categoryId: 'food',
  },
  { id: `fun-${month}`, cents: -6_000, on: `${month}-03`, categoryId: 'fun' },
  {
    id: `stream-${month}`,
    cents: -3_000,
    on: `${month}-10`,
    description: 'Streaming',
  },
]

const LINES: Line[] = [
  ...routine('2026-07'),
  ...routine('2026-08'),
  ...routine('2026-09'),
  { id: 'trip', cents: -3_000, on: '2026-08-15', categoryId: 'travel' },
  { id: 'salary-10', cents: 500_000, on: '2026-10-01' },
  { id: 'feast', cents: -130_000, on: '2026-10-02', categoryId: 'food' },
  { id: 'movie', cents: -1_000, on: '2026-10-03', categoryId: 'fun' },
  { id: 'ghost', cents: -500, on: '2026-10-03', categoryId: 'deleted' },
  { id: 'misc', cents: -2_000, on: '2026-10-04' },
  { id: 'present', cents: -6_000, on: '2026-10-04', categoryId: 'gift' },
  {
    id: 'stream-10',
    cents: -3_500,
    on: '2026-10-07',
    description: 'Streaming',
  },
  {
    id: 'das',
    accountId: 'company',
    cents: -4_000,
    on: '2026-10-04',
    categoryId: 'tax',
  },
  { id: 'office', accountId: 'company', cents: -1_000, on: '2026-10-04' },
]

async function seeded() {
  const deps = fullDeps()
  for (const [id, key] of CATEGORIES) {
    await deps.categories.save({
      id,
      tenantId: TENANT,
      key,
      name: key,
      icon: null,
      parentId: null,
    })
  }
  await deps.accounts.save(account({ id: 'checking', entityId: 'pf' }))
  await deps.accounts.save(
    account({
      id: 'reserve',
      entityId: 'pf',
      type: 'SAVINGS',
      isReserve: true,
      balance: Money.of(50_000),
    }),
  )
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
    account({
      id: 'plain-card',
      entityId: 'pf',
      type: 'CREDIT_CARD',
      balance: Money.of(-1_000),
    }),
  )
  await deps.accounts.save(
    account({
      id: 'later-card',
      entityId: 'pf',
      type: 'CREDIT_CARD',
      balance: Money.of(-2_000),
      credit: { ...CREDIT, dueOn: '2026-11-05' },
    }),
  )
  await deps.accounts.save(
    account({ id: 'company', entityId: 'pj', balance: Money.of(30_000) }),
  )
  for (const line of LINES) {
    await deps.transactions.save(
      transaction({
        id: line.id,
        accountId: line.accountId ?? 'checking',
        amount: Money.of(line.cents),
        bookedOn: line.on,
        description: line.description ?? line.id,
        categoryId: line.categoryId ?? null,
      }),
    )
  }
  await deps.transactions.save(
    transaction({
      id: 'sofa',
      accountId: 'card',
      amount: Money.of(-5_000),
      bookedOn: '2026-10-05',
      description: 'Sofa',
      installment: { number: 2, count: 4, purchaseOn: '2026-09-05' },
    }),
  )
  await deps.bills.save(bill({ id: 'open', dueDate: '2026-10-20' }))
  await deps.bills.save({
    ...bill({ id: 'paid', amount: Money.of(1_000), dueDate: '2026-10-05' }),
    status: 'PAID',
  })
  await deps.bills.save({
    ...bill({ id: 'cancelled', dueDate: '2026-10-15' }),
    status: 'CANCELLED',
  })
  await deps.bills.save(bill({ id: 'november', dueDate: '2026-11-02' }))
  await deps.transfers.save({
    id: 'pro-labore',
    tenantId: TENANT,
    kind: 'PRO_LABORE',
    amount: Money.of(20_000),
    at: NOW,
    rail: 'PIX',
    fromAccountId: 'company',
    toAccountId: 'checking',
    document: null,
  })
  await makeSubscriptions(deps).confirm(TENANT, 'stream-10')
  return deps
}

const cents = (value: number) => expect.objectContaining({ cents: value })

describe('monthly insights', () => {
  it('reads the current month against the usual one', async () => {
    const deps = await seeded()
    const insights = await makeMonthlyInsights(deps)(TENANT, { months: 6 })
    expect(insights.month).toBe('2026-10')
    expect(insights.months.map(item => item.month)).toEqual([
      '2026-05',
      '2026-06',
      '2026-07',
      '2026-08',
      '2026-09',
      '2026-10',
    ])
    expect(insights.months.at(-1)).toEqual({
      month: '2026-10',
      income: cents(500_000),
      expenses: cents(153_000),
      result: cents(347_000),
    })
    expect(insights.savings).toEqual({
      percent: 69,
      averagePercent: 96,
      trend: [
        { month: '2026-05', percent: null },
        { month: '2026-06', percent: null },
        { month: '2026-07', percent: 96 },
        { month: '2026-08', percent: 96 },
        { month: '2026-09', percent: 96 },
        { month: '2026-10', percent: 69 },
      ],
    })
    expect(
      insights.changes.rose.map(change => [change.categoryId, change.delta]),
    ).toEqual([
      ['food', cents(120_000)],
      ['gift', cents(6_000)],
      ['tax', cents(4_000)],
    ])
    expect(insights.changes.fell).toEqual([
      expect.objectContaining({
        categoryId: 'fun',
        total: cents(1_000),
        average: cents(6_000),
        delta: cents(-5_000),
      }),
      expect.objectContaining({ categoryId: 'travel', delta: cents(-1_000) }),
    ])
    expect(insights.fixedCost).toEqual({
      subscriptions: cents(3_500),
      installments: cents(5_000),
      bills: cents(13_345),
      total: cents(21_845),
      income: cents(500_000),
      sharePercent: 4,
    })
    expect(insights.leftThisMonth).toEqual({
      balance: cents(40_000),
      billsDue: cents(12_345),
      cardBill: cents(26_000),
      left: cents(1_655),
    })
    expect(insights.companyToPersonal).toEqual({
      transfers: cents(20_000),
      taxes: cents(4_000),
    })
    expect(insights.insights).toEqual([
      {
        type: 'CATEGORY_ABOVE_AVERAGE',
        tone: 'NEGATIVE',
        categoryId: 'food',
        name: 'restaurants',
        percent: 1200,
        amount: cents(120_000),
      },
      {
        type: 'INSTALLMENTS_COMMITTED',
        tone: 'NEUTRAL',
        month: '2026-11',
        amount: cents(5_000),
      },
      {
        type: 'SAVINGS_RATE',
        tone: 'NEGATIVE',
        percent: 69,
        averagePercent: 96,
      },
    ])
  })

  it('looks back at a past month of one entity', async () => {
    const deps = await seeded()
    const insights = await makeMonthlyInsights(deps)(TENANT, {
      entity: 'PF',
      month: '2026-09',
      months: 12,
    })
    expect(insights.months).toHaveLength(12)
    expect(insights.savings.percent).toBe(96)
    expect(insights.leftThisMonth).toBeNull()
    expect(insights.companyToPersonal).toBeNull()
    expect(insights.insights).toEqual([
      {
        type: 'SUBSCRIPTION_PRICE_UP',
        tone: 'NEGATIVE',
        name: 'Streaming',
        amount: cents(3_500),
        previousAmount: cents(3_000),
      },
    ])
  })

  it('answers zeros for a company without history', async () => {
    const deps = fullDeps()
    const insights = await makeMonthlyInsights(deps)(TENANT, {
      entity: 'PJ',
      months: 6,
    })
    expect(insights.savings).toMatchObject({
      percent: null,
      averagePercent: null,
    })
    expect(insights.fixedCost.sharePercent).toBeNull()
    expect(insights.leftThisMonth?.left.cents).toBe(0)
    expect(insights.companyToPersonal).toEqual({
      transfers: cents(0),
      taxes: cents(0),
    })
    expect(insights.insights).toEqual([])
  })

  it('lets a better savings month show as good news', async () => {
    const deps = fullDeps()
    await deps.accounts.save(account({ id: 'checking', entityId: 'pf' }))
    const lines: Line[] = [
      ...routine('2026-09'),
      { id: 'big', cents: -200_000, on: '2026-09-20' },
      { id: 'salary-10', cents: 500_000, on: '2026-10-01' },
    ]
    for (const line of lines) {
      await deps.transactions.save(
        transaction({
          id: line.id,
          accountId: 'checking',
          amount: Money.of(line.cents),
          bookedOn: line.on,
          description: line.description ?? line.id,
        }),
      )
    }
    const insights = await makeMonthlyInsights(deps)(TENANT, {
      entity: 'PF',
      months: 6,
    })
    expect(insights.insights).toEqual([
      {
        type: 'SAVINGS_RATE',
        tone: 'POSITIVE',
        percent: 100,
        averagePercent: 56,
      },
    ])
  })
})
