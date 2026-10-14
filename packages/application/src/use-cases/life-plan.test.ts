import { describe, expect, it } from 'vitest'
import { Money } from '@cashdeck/domain'
import { planGoalInputSchema, type PlanGoalInput } from '@/dtos/life-plan'
import { NotFoundError } from '@/errors/errors'
import { account, fullDeps, transaction } from '@/testing/deps.test-helpers'
import { importLoan } from '@/testing/loans.test-helpers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { makeAssets } from '@/use-cases/assets'
import { makeGoals } from '@/use-cases/goals'
import { makeLifePlan } from '@/use-cases/life-plan'
import { makeSetSpendingPlan } from '@/use-cases/spending-plan'

const goal = (input: Record<string, unknown>): PlanGoalInput =>
  planGoalInputSchema.parse(input)

const trips = goal({ kind: 'YEARLY', name: 'Trips', yearly: 1_200_000 })

async function seed() {
  const deps = fullDeps()
  await deps.accounts.save(
    account({ id: 'chk', entityId: 'pf', balance: Money.of(500_000) }),
  )
  for (const [id, bookedOn] of [
    ['s1', '2026-08-25'],
    ['s2', '2026-09-25'],
  ] as const) {
    await deps.transactions.save(
      transaction({
        id,
        bookedOn,
        accountId: 'chk',
        amount: Money.of(800_000),
        description: 'Salary',
        counterparty: '12345678000195',
      }),
    )
  }
  await makeSetSpendingPlan(deps)(TENANT, {
    savings: { cents: 300_000, currency: 'BRL' },
  })
  const loanId = await importLoan(deps)
  const home = await makeAssets(deps).create(TENANT, {
    entity: 'PF',
    kind: 'PROPERTY',
    name: 'Apartment',
    acquiredOn: '2026-08-10',
    value: 900_000,
    loanId,
    rental: null,
  })
  return { deps, plan: makeLifePlan(deps), homeId: home.id }
}

describe('life plan', () => {
  it('starts from the monthly plan and the defaults', async () => {
    const { plan } = await seed()
    const view = await plan.view(TENANT)
    expect(view).toMatchObject({
      asOf: '2026-10',
      monthlySavings: { cents: 300_000 },
      savingsFromBudget: true,
      monthlySpending: { cents: 500_000 },
      reserveMonths: 6,
      reserve: { cents: 3_000_000 },
      yearlyYield: 6,
      keepInvested: 0,
      yearlyProvision: { cents: 0 },
      free: { cents: 300_000 },
      goals: [],
    })
    expect(view.timeline).toHaveLength(11)
  })

  it('needs no monthly plan to answer', async () => {
    const view = await makeLifePlan(fullDeps()).view(TENANT)
    expect(view).toMatchObject({
      monthlySavings: { cents: 0 },
      monthlySpending: { cents: 0 },
      reserve: { cents: 0 },
    })
  })

  it('schedules the goals and tells what each one costs a milestone', async () => {
    const { plan, homeId } = await seed()
    await plan.saveSettings(TENANT, {
      reserveMonths: 0,
      yearlyYield: 0,
      keepInvested: 0,
      monthlySavings: null,
    })
    const worth = (await plan.view(TENANT)).netWorth.cents
    await plan.create(
      TENANT,
      goal({
        kind: 'MILESTONE',
        name: 'Net worth',
        metric: 'NET_WORTH',
        target: worth + 3_600_000,
      }),
    )
    await plan.create(TENANT, trips)
    const view = await plan.create(
      TENANT,
      goal({
        kind: 'PURCHASE',
        name: 'House',
        price: 2_000_000,
        tradeIn: 5,
        tradeInAssetId: homeId,
        keepsValue: true,
      }),
    )
    const [milestone, yearly, house] = view.goals
    expect(milestone).toMatchObject({
      kind: 'MILESTONE',
      status: 'PLANNED',
      // 3.6M at 200k a month once the trips take their share.
      month: '2028-04',
      metric: 'NET_WORTH',
      target: { cents: worth + 3_600_000 },
      current: { cents: worth },
      price: null,
    })
    expect(yearly).toMatchObject({
      kind: 'YEARLY',
      cash: { cents: 100_000 },
      yearly: { cents: 1_200_000 },
      delays: [{ milestoneId: milestone?.id, name: 'Net worth', months: 6 }],
    })
    // The apartment's 9k less the 2k still owed on its loan.
    expect(house).toMatchObject({
      kind: 'PURCHASE',
      tradeIn: { cents: 700_000 },
      tradeInAssetId: homeId,
      tradeInAssetName: 'Apartment',
      cash: { cents: 1_300_000 },
      financed: { cents: 0 },
      monthlyCost: { cents: 0 },
      keepsValue: true,
      payment: 'CASH',
      installments: 1,
      cashDiscount: 0,
      goalId: null,
      notBefore: null,
      by: null,
      yearly: null,
      metric: null,
      current: null,
      delays: [],
    })
    expect(view.free).toEqual({ cents: 200_000, currency: 'BRL' })
    const invested = await plan.create(
      TENANT,
      goal({
        kind: 'MILESTONE',
        name: 'Invested',
        metric: 'INVESTED',
        target: 1,
      }),
    )
    expect(invested.goals[3]?.current).toEqual(view.invested)
  })

  it('reorders, edits and removes goals', async () => {
    const { deps, plan, homeId } = await seed()
    const first = await plan.create(TENANT, trips)
    const tripId = first.goals[0]?.id as string
    const car = goal({
      kind: 'PURCHASE',
      name: 'Car',
      price: 9_000_000,
      tradeIn: 400_000,
      tradeInAssetId: homeId,
    })
    const second = await plan.create(TENANT, car)
    const carId = second.goals[1]?.id as string
    const oldPhone = await makeAssets(deps).create(TENANT, {
      entity: 'PF',
      kind: 'OTHER',
      name: 'Old phone',
      acquiredOn: '2025-01-10',
      value: 80_000,
      loanId: null,
      rental: null,
    })
    await plan.create(
      TENANT,
      goal({
        kind: 'PURCHASE',
        name: 'Phone',
        price: 500_000,
        tradeInAssetId: oldPhone.id,
      }),
    )

    const reordered = await plan.reorder(TENANT, { ids: [carId] })
    expect(reordered.goals.map(item => item.name)).toEqual([
      'Car',
      'Trips',
      'Phone',
    ])

    await makeAssets(deps).update(TENANT, homeId, { soldOn: '2026-10-01' })
    const sold = await plan.view(TENANT)
    expect(sold.goals[0]).toMatchObject({
      tradeIn: { cents: 400_000 },
      tradeInAssetId: null,
      tradeInAssetName: null,
    })
    expect(sold.goals[2]?.tradeIn).toEqual({ cents: 80_000, currency: 'BRL' })

    const edited = await plan.update(TENANT, carId, { ...car, name: 'Truck' })
    expect(edited.goals.map(item => item.name)).toEqual([
      'Truck',
      'Trips',
      'Phone',
    ])
    const left = await plan.remove(TENANT, tripId)
    expect(left.goals.map(item => item.name)).toEqual(['Truck', 'Phone'])

    const custom = await plan.saveSettings(TENANT, {
      reserveMonths: 3,
      yearlyYield: 4,
      keepInvested: 50,
      monthlySavings: 100_000,
    })
    expect(custom).toMatchObject({
      monthlySavings: { cents: 100_000 },
      savingsFromBudget: false,
      reserveMonths: 3,
      reserve: { cents: 1_500_000 },
      yearlyYield: 4,
      keepInvested: 50,
    })
  })

  it('arranges the order and the waits, or previews them unwritten', async () => {
    const { plan } = await seed()
    await plan.create(TENANT, trips)
    await plan.create(
      TENANT,
      goal({ kind: 'PURCHASE', name: 'Car', price: 9_000_000, by: '2028-01' }),
    )
    const before = await plan.create(
      TENANT,
      goal({
        kind: 'PURCHASE',
        name: 'Phone',
        price: 500_000,
        notBefore: '2027-03',
      }),
    )
    const [tripId, carId, phoneId] = before.goals.map(item => item.id) as [
      string,
      string,
      string,
    ]
    const arrangement = {
      goals: [
        { id: phoneId, notBefore: '2027-06' },
        { id: carId, notBefore: '2029-01' },
        { id: tripId, notBefore: '2027-01' },
      ],
    }
    const waits = (view: Awaited<ReturnType<typeof plan.view>>) =>
      view.goals.map(item => [item.name, item.notBefore])

    expect(waits(await plan.preview(TENANT, arrangement))).toEqual([
      ['Phone', '2027-06'],
      ['Car', '2028-01'],
      ['Trips', null],
    ])
    expect(waits(await plan.view(TENANT))).toEqual([
      ['Trips', null],
      ['Car', null],
      ['Phone', '2027-03'],
    ])

    await plan.arrange(TENANT, arrangement)
    const reordered = await plan.reorder(TENANT, { ids: [tripId] })
    expect(waits(reordered)).toEqual([
      ['Trips', null],
      ['Phone', '2027-06'],
      ['Car', '2028-01'],
    ])
    expect(waits(await plan.view(TENANT))).toEqual(waits(reordered))
  })

  it('links a purchase to the caixinha saving for it', async () => {
    const { deps, plan } = await seed()
    const caixinhas = makeGoals(deps)
    const saving = await caixinhas.create(TENANT, {
      entity: 'PF',
      name: 'Phone',
      targetCents: 500_000,
    })
    const phone = goal({
      kind: 'PURCHASE',
      name: 'Phone',
      price: 500_000,
      payment: 'CARD',
      installments: 10,
      goalId: saving.id,
    })
    const linked = await plan.create(TENANT, phone)
    expect(linked.goals[0]).toMatchObject({
      payment: 'CARD',
      installments: 10,
      goalId: saving.id,
    })
    await caixinhas.update(TENANT, saving.id, { archived: true })
    expect((await plan.view(TENANT)).goals[0]?.goalId).toBeNull()
    await expect(
      plan.create(TENANT, goal({ ...phone, goalId: 'ghost' })),
    ).rejects.toThrow(NotFoundError)
  })

  it('reads goals stored before payment existed as cash', async () => {
    const { deps, plan } = await seed()
    await deps.documents.put(TENANT, 'plan-goals', 'old', {
      id: 'old',
      order: 0,
      createdAt: '2026-10-01T00:00:00.000Z',
      kind: 'PURCHASE',
      name: 'Car',
      price: 100,
    })
    expect((await plan.view(TENANT)).goals[0]).toMatchObject({
      id: 'old',
      payment: 'CASH',
      installments: 1,
      goalId: null,
    })
  })

  it('refuses unknown goals and assets', async () => {
    const { plan } = await seed()
    const ghost = goal({
      kind: 'PURCHASE',
      name: 'Car',
      price: 100,
      tradeInAssetId: 'ghost',
    })
    await expect(plan.create(TENANT, ghost)).rejects.toThrow(NotFoundError)
    await expect(plan.update(TENANT, 'ghost', trips)).rejects.toThrow(
      NotFoundError,
    )
    await expect(plan.remove(TENANT, 'ghost')).rejects.toThrow(NotFoundError)
  })

  it('fills the defaults and keeps the window in order', () => {
    expect(goal({ kind: 'PURCHASE', name: ' Phone ', price: 500 })).toEqual({
      kind: 'PURCHASE',
      name: 'Phone',
      icon: null,
      price: 500,
      tradeIn: 0,
      tradeInAssetId: null,
      financed: 0,
      monthlyCost: 0,
      keepsValue: false,
      payment: 'CASH',
      installments: 1,
      cashDiscount: 0,
      goalId: null,
      notBefore: null,
      by: null,
    })
    const backwards = planGoalInputSchema.safeParse({
      kind: 'PURCHASE',
      name: 'Kid',
      price: 500,
      notBefore: '2028-10',
      by: '2028-01',
    })
    expect(backwards.success).toBe(false)
    expect(
      planGoalInputSchema.safeParse({
        kind: 'PURCHASE',
        name: 'Kid',
        price: 500,
        notBefore: '2028-01',
        by: '2028-10',
      }).success,
    ).toBe(true)
  })
})
