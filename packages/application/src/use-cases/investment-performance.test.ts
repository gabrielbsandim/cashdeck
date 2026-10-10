import { addDays, Money } from '@cashdeck/domain'
import { describe, expect, it } from 'vitest'
import { NotFoundError } from '@/errors/errors'
import {
  type InvestmentMovement,
  type InvestmentPosition,
} from '@/ports/investments'
import { fullDeps } from '@/testing/deps.test-helpers'
import { NOW, TENANT } from '@/testing/scenario.test-helpers'
import { makeInvestmentPerformance } from '@/use-cases/investment-performance'
import { makeListInvestments } from '@/use-cases/investments'

const TODAY = '2026-10-08'
const day = (offset: number) => addDays(TODAY, offset)

function position(
  overrides: Partial<InvestmentPosition> & { id: string },
): InvestmentPosition {
  return {
    tenantId: TENANT,
    entityId: 'pf',
    connectionId: 'conn',
    institutionId: 'bank',
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

const movement = (
  overrides: Partial<InvestmentMovement> & { id: string },
): InvestmentMovement => ({
  tenantId: TENANT,
  investmentId: 'cdb',
  externalId: overrides.id,
  kind: 'BUY',
  occurredOn: day(-15),
  amountCents: 5_000,
  quantity: null,
  unitPrice: null,
  ...overrides,
})

async function portfolio() {
  const deps = fullDeps()
  await deps.institutions.ensure({
    id: 'bank',
    tenantId: TENANT,
    name: 'Banco Exemplo',
    manual: false,
    imageUrl: 'https://logo.example/bank.svg',
    primaryColor: null,
  })
  await deps.investments.saveAll([
    position({ id: 'cdb', balance: Money.of(110_000) }),
    position({ id: 'fund', kind: 'FUND', balance: Money.of(50_000) }),
    position({ id: 'company', entityId: 'pj', balance: Money.of(70_000) }),
    position({ id: 'abroad', kind: 'ETF', balance: Money.of(9_000, 'USD') }),
    position({ id: 'gone', status: 'CLOSED', balance: Money.of(0) }),
  ])
  await deps.investments.saveMovements([
    movement({ id: 'buy' }),
    movement({ id: 'first', occurredOn: day(-60), amountCents: 100_000 }),
    movement({
      id: 'sell',
      kind: 'SELL',
      occurredOn: day(-5),
      amountCents: 2_000,
      quantity: 2,
      unitPrice: 10,
    }),
    movement({ id: 'tax', kind: 'TAX', occurredOn: day(-3), amountCents: 100 }),
  ])
  await deps.investments.saveSnapshots([
    {
      tenantId: TENANT,
      investmentId: 'cdb',
      day: day(-40),
      balanceCents: 100_000,
      estimated: true,
    },
    {
      tenantId: TENANT,
      investmentId: 'cdb',
      day: day(-10),
      balanceCents: 104_000,
      estimated: false,
    },
    {
      tenantId: TENANT,
      investmentId: 'abroad',
      day: day(-40),
      balanceCents: 8_000,
      estimated: false,
    },
  ])
  await deps.indexRates.save('CDI', [
    { day: day(-30), value: 1 },
    { day: day(-29), value: 0.05 },
    { day: day(-1), value: 0.05 },
  ])
  return { deps, ...makeInvestmentPerformance(deps) }
}

const brl = (cents: number) => ({ cents, currency: 'BRL' })

describe('investment performance', () => {
  it('sums the month with Modified Dietz, flows and CDI', async () => {
    const { performance } = await portfolio()
    const view = await performance(TENANT, { entity: 'PF', period: 'MONTH' })
    expect(view).toMatchObject({
      period: 'MONTH',
      from: day(-30),
      to: TODAY,
      start: brl(100_000),
      end: brl(160_000),
      contributions: brl(5_000),
      withdrawals: brl(2_000),
      yield: brl(57_000),
      yieldPercent: 55.79,
      cdiPercent: 0.1,
      estimated: true,
    })
    expect(view.series).toHaveLength(31)
    expect(view.series[0]).toEqual({ day: day(-30), value: brl(100_000) })
    expect(view.series[20]).toEqual({ day: day(-10), value: brl(104_000) })
    expect(view.series.at(-1)).toEqual({ day: TODAY, value: brl(160_000) })
    expect(view.positions).toEqual([
      {
        id: 'fund',
        start: brl(0),
        end: brl(50_000),
        yield: brl(50_000),
        yieldPercent: null,
      },
      {
        id: 'cdb',
        start: brl(100_000),
        end: brl(110_000),
        yield: brl(7_000),
        yieldPercent: 6.85,
      },
    ])
  })

  it('steps a year by week and a week by day', async () => {
    const { performance } = await portfolio()
    const year = await performance(TENANT, { period: 'YEAR' })
    expect(year.from).toBe(day(-365))
    expect(year.series).toHaveLength(54)
    expect(year.series.at(-2)?.day).toBe(day(-1))
    expect(year.series.at(-1)).toEqual({ day: TODAY, value: brl(230_000) })
    expect(year.start).toEqual(brl(0))
    expect(year.estimated).toBe(false)
    const week = await performance(TENANT, { period: 'WEEK' })
    expect(week.series.map(point => point.day)).toEqual(
      [-7, -6, -5, -4, -3, -2, -1, 0].map(day),
    )
    expect(week.cdiPercent).toBe(0.05)
    expect(week.withdrawals).toEqual(brl(2_000))
  })

  it('leaves the CDI out before any rate is stored', async () => {
    const deps = fullDeps()
    const view = await makeInvestmentPerformance(deps).performance(TENANT, {
      period: 'MONTH',
    })
    expect(view).toMatchObject({
      start: brl(0),
      end: brl(0),
      yieldPercent: null,
      cdiPercent: null,
      estimated: false,
      positions: [],
    })
  })

  it('details one position with its movements, newest first', async () => {
    const { detail } = await portfolio()
    const view = await detail(TENANT, 'cdb', 'MONTH')
    expect(view.position).toMatchObject({
      id: 'cdb',
      entityKind: 'PF',
      institution: 'Banco Exemplo',
      invested: brl(103_000),
      profit: brl(7_000),
      profitPercent: 6.8,
    })
    expect(view.performance).toMatchObject({
      start: brl(100_000),
      end: brl(110_000),
      yield: brl(7_000),
      yieldPercent: 6.85,
    })
    expect(view.performance).not.toHaveProperty('positions')
    expect(view.movements.map(row => row.id)).toEqual([
      'tax',
      'sell',
      'buy',
      'first',
    ])
    expect(view.movements[1]).toEqual({
      id: 'sell',
      kind: 'SELL',
      occurredOn: day(-5),
      amount: brl(2_000),
      quantity: 2,
      unitPrice: 10,
    })
  })

  it('details a position abroad in its currency and refuses an unknown one', async () => {
    const { detail } = await portfolio()
    const view = await detail(TENANT, 'abroad', 'WEEK')
    expect(view.position.institution).toBe('Banco Exemplo')
    expect(view.movements).toEqual([])
    expect(view.performance).toMatchObject({
      start: { cents: 8_000, currency: 'USD' },
      yield: { cents: 1_000, currency: 'USD' },
      yieldPercent: 12.5,
    })
    await expect(detail(TENANT, 'missing', 'MONTH')).rejects.toThrow(
      NotFoundError,
    )
    await expect(detail('other-tenant', 'cdb', 'MONTH')).rejects.toThrow(
      NotFoundError,
    )
  })

  it('lists what the movements put in when the provider leaves it out', async () => {
    const { deps } = await portfolio()
    const view = await makeListInvestments(deps)(TENANT, 'PF')
    expect(view.positions.find(row => row.id === 'cdb')).toMatchObject({
      invested: brl(103_000),
      profit: brl(7_000),
      profitPercent: 6.8,
    })
    expect(view.positions.find(row => row.id === 'fund')?.invested).toBeNull()
  })
})
