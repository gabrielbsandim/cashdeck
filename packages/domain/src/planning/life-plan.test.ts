import { describe, expect, it } from 'vitest'
import {
  lifePlan,
  type MilestoneGoal,
  type PlanStart,
  type PurchaseGoal,
  purchaseCash,
  type YearlyGoal,
} from '@/planning/life-plan'

// No yield keeps the arithmetic readable: savings of 10k a month on 100k.
const start: PlanStart = {
  month: '2026-10',
  cashCents: 0,
  investedCents: 100_000,
  netWorthCents: 300_000,
  monthlySavingsCents: 10_000,
  monthlySpendingCents: 5_000,
  reserveMonths: 2,
  keepShare: 0,
  monthlyYield: 0,
}

const purchase = (overrides: Partial<PurchaseGoal>): PurchaseGoal => ({
  id: 'p',
  kind: 'PURCHASE',
  name: 'Phone',
  priceCents: 50_000,
  tradeInCents: 0,
  financedCents: 0,
  monthlyCostCents: 0,
  keepsValue: false,
  payment: 'CASH',
  installments: 1,
  notBefore: null,
  by: null,
  ...overrides,
})

const milestone = (overrides: Partial<MilestoneGoal>): MilestoneGoal => ({
  id: 'm',
  kind: 'MILESTONE',
  name: 'Net worth',
  metric: 'NET_WORTH',
  targetCents: 400_000,
  by: null,
  ...overrides,
})

const trips: YearlyGoal = {
  id: 'y',
  kind: 'YEARLY',
  name: 'Trips',
  yearlyCents: 24_000,
}

const byId = (plan: ReturnType<typeof lifePlan>) =>
  Object.fromEntries(plan.goals.map(goal => [goal.id, goal]))

describe('lifePlan', () => {
  it('projects milestones from the savings alone', () => {
    const plan = lifePlan(start, [
      milestone({}),
      milestone({ id: 'now', metric: 'INVESTED', targetCents: 100_000 }),
      milestone({ id: 'far', metric: 'INVESTED', targetCents: 10 ** 9 }),
      milestone({ id: 'late', by: '2027-03' }),
    ])
    expect(plan.reserveCents).toBe(10_000)
    expect(plan.yearlyProvisionCents).toBe(0)
    expect(plan.goals).toEqual([
      {
        id: 'm',
        status: 'PLANNED',
        month: '2027-08',
        cashCents: 0,
        delays: [],
      },
      { id: 'now', status: 'NOW', month: '2026-10', cashCents: 0, delays: [] },
      {
        id: 'far',
        status: 'OUT_OF_REACH',
        month: null,
        cashCents: 0,
        delays: [],
      },
      {
        id: 'late',
        status: 'LATE',
        month: '2027-08',
        cashCents: 0,
        delays: [],
      },
    ])
    expect(plan.timeline).toHaveLength(11)
    expect(plan.timeline[1]).toEqual({
      month: '2027-10',
      netWorthCents: 420_000,
      investedCents: 220_000,
    })
  })

  it('places each purchase after the ones before it and keeps the reserve', () => {
    const plan = byId(
      lifePlan(start, [
        milestone({}),
        purchase({}),
        purchase({
          id: 'car',
          priceCents: 200_000,
          tradeInCents: 40_000,
          keepsValue: true,
        }),
      ]),
    )
    expect(plan.p).toEqual({
      id: 'p',
      status: 'NOW',
      month: '2026-10',
      cashCents: 50_000,
      delays: [{ milestoneId: 'm', months: 5 }],
    })
    // 50k left grows 10k a month; 160k out must leave 10k behind.
    expect(plan.car).toMatchObject({
      status: 'PLANNED',
      month: '2027-10',
      cashCents: 160_000,
      delays: [],
    })
    expect(plan.m?.month).toBe('2028-01')
  })

  it('waits for the earliest month and counts the monthly cost after it', () => {
    const plan = byId(
      lifePlan(start, [
        purchase({
          id: 'kid',
          priceCents: 10_000,
          monthlyCostCents: 2_000,
          notBefore: '2028-01',
        }),
        purchase({ id: 'early', notBefore: '2020-01', priceCents: 1_000 }),
        purchase({ id: 'late', priceCents: 400_000, by: '2027-01' }),
        purchase({ id: 'never', priceCents: 10 ** 12 }),
      ]),
    )
    expect(plan.kid?.month).toBe('2028-01')
    expect(plan.early?.status).toBe('NOW')
    // 99k at the start, 10k a month until the kid, 8k after, 14k reserve.
    expect(plan.late).toMatchObject({ status: 'LATE', month: '2029-11' })
    expect(plan.never).toMatchObject({
      status: 'OUT_OF_REACH',
      month: null,
      delays: [],
    })
  })

  it('holds a purchase back until the savings rebuild the reserve', () => {
    const plan = byId(
      lifePlan({ ...start, investedCents: 0, netWorthCents: 0 }, [
        purchase({ priceCents: 5_000 }),
      ]),
    )
    expect(plan.p?.month).toBe('2026-12')
  })

  it('sets aside the yearly goals and tells what each costs a milestone', () => {
    const plan = lifePlan(start, [milestone({}), trips])
    expect(plan.yearlyProvisionCents).toBe(2_000)
    expect(byId(plan).y).toEqual({
      id: 'y',
      status: 'PLANNED',
      month: null,
      cashCents: 2_000,
      delays: [{ milestoneId: 'm', months: 3 }],
    })
    const stuck = lifePlan(start, [
      milestone({}),
      trips,
      purchase({ id: 'stop', priceCents: 0, monthlyCostCents: 8_000 }),
    ])
    expect(byId(stuck).stop).toMatchObject({
      status: 'NOW',
      delays: [{ milestoneId: 'm', months: null }],
    })
  })

  it('grows the savings by the yield and skips delays without milestones', () => {
    const plan = lifePlan({ ...start, monthlyYield: 0.01, cashCents: 5_000 }, [
      purchase({ priceCents: 1_000 }),
    ])
    expect(plan.goals[0]?.delays).toEqual([])
    expect(plan.timeline[0]).toEqual({
      month: '2026-10',
      netWorthCents: 299_000,
      investedCents: 99_000,
    })
    expect(plan.timeline[1]?.investedCents).toBeGreaterThan(220_000)
  })

  it('keeps a share of the savings through every purchase', () => {
    const plan = byId(
      lifePlan({ ...start, keepShare: 0.5 }, [
        purchase({ priceCents: 60_000 }),
        purchase({ id: 'small', priceCents: 1_000 }),
      ]),
    )
    // 60k needs 120k saved: two months of 10k on top of 100k.
    expect(plan.p?.month).toBe('2026-12')
    // Bought earlier, the 1k would leave the 60k one short of its share.
    expect(plan.small?.month).toBe('2027-01')
  })

  it('pays a card purchase with the bills after it', () => {
    const monthOf = (installments: number) =>
      lifePlan({ ...start, keepShare: 0.5 }, [
        purchase({ priceCents: 60_000, payment: 'CARD', installments }),
      ]).goals[0]?.month
    // The bill comes a month later, when the savings have grown by 10k.
    expect(monthOf(1)).toBe('2026-11')
    expect(monthOf(10)).toBe('2026-10')
    const plan = lifePlan(start, [
      purchase({ payment: 'CARD', installments: 1 }),
    ])
    expect(plan.timeline[0]).toEqual({
      month: '2026-10',
      netWorthCents: 250_000,
      investedCents: 100_000,
    })
  })

  it('takes the trade-in and the loan off the price', () => {
    expect(
      purchaseCash(
        purchase({ priceCents: 900, tradeInCents: 100, financedCents: 600 }),
      ),
    ).toBe(200)
  })
})
