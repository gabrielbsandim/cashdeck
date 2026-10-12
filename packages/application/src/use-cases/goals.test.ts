import { createGoal, Money, ValidationError } from '@cashdeck/domain'
import { describe, expect, it } from 'vitest'
import { NotFoundError } from '@/errors/errors'
import { type InvestmentPosition } from '@/ports/investments'
import { account, fullDeps, transaction } from '@/testing/deps.test-helpers'
import { NOW, TENANT } from '@/testing/scenario.test-helpers'
import { FixedClock } from '@/testing/system'
import { makeGoals } from '@/use-cases/goals'

const LATER = new Date('2026-11-07T12:00:00Z')

function setup() {
  const deps = fullDeps()
  const clock = new FixedClock(NOW)
  const all = { ...deps, clock }
  return { deps: all, goals: makeGoals(all), clock }
}

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
    balance: Money.of(2_000_00),
    invested: null,
    profit: null,
    syncedAt: NOW,
    ...overrides,
  }
}

describe('manual goals', () => {
  it('starts from what is already saved and waits a month to judge the pace', async () => {
    const { deps, goals } = setup()
    const created = await goals.create(TENANT, {
      entity: 'PF',
      name: ' Trip ',
      targetCents: 1_200_00,
      deadline: '2027-04-08',
      icon: 'flight',
      color: 'teal',
      initialCents: 300_00,
    })
    expect(created).toMatchObject({
      entity: 'PF',
      name: 'Trip',
      icon: 'flight',
      color: 'teal',
      saved: { cents: 300_00 },
      remaining: { cents: 900_00 },
      percent: 25,
      status: 'ON_TRACK',
      requiredMonthly: { cents: 150_00 },
      monthlyPace: null,
      projectedOn: null,
      source: 'MANUAL',
      linkedName: null,
      archivedAt: null,
    })
    expect(created.contributions).toHaveLength(1)
    expect(deps.audit.events.map(event => event.action)).toEqual([
      'goal.create',
    ])
  })

  it('projects from the contributions after the start and celebrates at 100%', async () => {
    const { goals, clock } = setup()
    const { id } = await goals.create(TENANT, {
      entity: 'PF',
      name: 'Trip',
      targetCents: 1_200_00,
      deadline: '2027-04-08',
      initialCents: 300_00,
    })
    clock.set(LATER)
    await goals.contribute(TENANT, id, {
      amountCents: 300_00,
      on: '2026-11-01',
      note: 'bonus',
    })
    const paced = await goals.get(TENANT, id)
    expect(paced).toMatchObject({
      saved: { cents: 600_00 },
      percent: 50,
      status: 'ON_TRACK',
      requiredMonthly: { cents: 120_00 },
      monthlyPace: { cents: 30_438 },
      projectedOn: '2027-01-06',
    })
    expect(paced.contributions.map(item => item.note)).toEqual(['bonus', null])

    const withdrawn = await goals.contribute(TENANT, id, {
      amountCents: -100_00,
    })
    expect(withdrawn.saved.cents).toBe(500_00)
    expect(withdrawn.contributions[0]?.on).toBe('2026-11-07')

    const done = await goals.contribute(TENANT, id, { amountCents: 700_00 })
    expect(done).toMatchObject({ percent: 100, status: 'DONE' })
  })

  it('removes a contribution of its own goal only', async () => {
    const { deps, goals } = setup()
    const goal = await goals.create(TENANT, {
      entity: 'PF',
      name: 'Car',
      targetCents: 10_000_00,
      initialCents: 1_000_00,
    })
    const contributionId = goal.contributions[0]?.id as string
    await expect(
      goals.removeContribution(TENANT, goal.id, 'nope'),
    ).rejects.toBeInstanceOf(NotFoundError)
    const after = await goals.removeContribution(
      TENANT,
      goal.id,
      contributionId,
    )
    expect(after).toMatchObject({ saved: { cents: 0 }, contributions: [] })
    expect(deps.audit.events.at(-1)?.action).toBe('goal.contribution.delete')
  })
})

describe('linked goals', () => {
  it('reads an account balance and paces by its net flow', async () => {
    const { deps, goals } = setup()
    await deps.accounts.save(
      account({
        id: 'savings',
        entityId: 'pf',
        type: 'SAVINGS',
        balance: Money.of(5_000_00),
      }),
    )
    await deps.transactions.save(
      transaction({
        id: 'in',
        accountId: 'savings',
        amount: Money.of(1_000_00),
        bookedOn: '2026-09-01',
      }),
    )
    await deps.transactions.save(
      transaction({
        id: 'out',
        accountId: 'savings',
        amount: Money.of(-100_00),
        bookedOn: '2026-10-01',
      }),
    )
    await deps.transactions.save(
      transaction({
        id: 'old',
        accountId: 'savings',
        amount: Money.of(9_000_00),
        bookedOn: '2026-06-01',
      }),
    )
    const goal = await goals.create(TENANT, {
      entity: 'PF',
      name: 'Emergency fund',
      targetCents: 10_000_00,
      accountId: 'savings',
    })
    expect(goal).toMatchObject({
      saved: { cents: 5_000_00 },
      percent: 50,
      status: 'ON_TRACK',
      requiredMonthly: null,
      monthlyPace: { cents: 30_438 },
      source: 'ACCOUNT',
      accountId: 'savings',
      linkedName: 'Account savings',
      contributions: [],
    })
    await expect(
      goals.contribute(TENANT, goal.id, { amountCents: 100 }),
    ).rejects.toBeInstanceOf(ValidationError)
  })

  it('refuses an account it cannot follow', async () => {
    const { deps, goals } = setup()
    await deps.accounts.save(
      account({ id: 'card', entityId: 'pf', type: 'CREDIT_CARD' }),
    )
    await deps.accounts.save(account({ id: 'company', entityId: 'pj' }))
    await deps.accounts.save(
      account({ id: 'usd', entityId: 'pf', balance: Money.of(100, 'USD') }),
    )
    const input = { entity: 'PF' as const, name: 'Goal', targetCents: 100 }
    for (const accountId of ['card', 'company', 'usd']) {
      await expect(
        goals.create(TENANT, { ...input, accountId }),
      ).rejects.toBeInstanceOf(ValidationError)
    }
    await expect(
      goals.create(TENANT, { ...input, accountId: 'gone' }),
    ).rejects.toBeInstanceOf(NotFoundError)
    await deps.accounts.save(account({ id: 'checking', entityId: 'pf' }))
    await expect(
      goals.create(TENANT, {
        ...input,
        accountId: 'checking',
        initialCents: 1,
      }),
    ).rejects.toThrow('reads its balance')
  })

  it('reads an investment and paces by its snapshots', async () => {
    const { deps, goals } = setup()
    await deps.investments.saveAll([
      position({ id: 'cdb' }),
      position({ id: 'fresh' }),
      position({ id: 'pj-fund', entityId: 'pj' }),
    ])
    await deps.investments.saveSnapshots([
      {
        tenantId: TENANT,
        investmentId: 'cdb',
        day: '2026-08-09',
        balanceCents: 1_500_00,
        estimated: false,
      },
      {
        tenantId: TENANT,
        investmentId: 'cdb',
        day: '2026-09-09',
        balanceCents: 1_800_00,
        estimated: false,
      },
    ])
    const goal = await goals.create(TENANT, {
      entity: 'PF',
      name: 'House',
      targetCents: 2_400_00,
      deadline: '2026-12-08',
      investmentId: 'cdb',
    })
    expect(goal).toMatchObject({
      saved: { cents: 2_000_00 },
      status: 'ON_TRACK',
      monthlyPace: { cents: 25_365 },
      source: 'INVESTMENT',
      linkedName: 'Position cdb',
    })
    const fresh = await goals.create(TENANT, {
      entity: 'PF',
      name: 'Fresh',
      targetCents: 4_000_00,
      investmentId: 'fresh',
    })
    expect(fresh.monthlyPace).toBeNull()
    await expect(
      goals.create(TENANT, {
        entity: 'PF',
        name: 'Other',
        targetCents: 100,
        investmentId: 'pj-fund',
      }),
    ).rejects.toBeInstanceOf(ValidationError)
    await expect(
      goals.create(TENANT, {
        entity: 'PF',
        name: 'Other',
        targetCents: 100,
        investmentId: 'gone',
      }),
    ).rejects.toBeInstanceOf(NotFoundError)
  })

  it('shows nothing saved once the account or investment is gone', async () => {
    const { deps, goals } = setup()
    for (const [id, links] of [
      ['a', { accountId: 'gone' }],
      ['i', { investmentId: 'gone' }],
    ] as const) {
      await deps.goals.save(
        createGoal({
          id,
          tenantId: TENANT,
          entityId: 'pf',
          name: 'Lost',
          target: Money.of(100),
          createdAt: NOW,
          ...links,
        }),
      )
      expect(await goals.get(TENANT, id)).toMatchObject({
        saved: { cents: 0 },
        monthlyPace: null,
        linkedName: null,
      })
    }
  })
})

describe('goal changes', () => {
  it('edits, archives, relinks and deletes a goal', async () => {
    const { deps, goals, clock } = setup()
    await deps.accounts.save(account({ id: 'checking', entityId: 'pf' }))
    const goal = await goals.create(TENANT, {
      entity: 'PF',
      name: 'Bike',
      targetCents: 2_000_00,
      initialCents: 100_00,
    })
    const renamed = await goals.update(TENANT, goal.id, {
      name: 'Road bike',
      targetCents: 3_000_00,
      deadline: '2027-01-31',
      icon: null,
    })
    expect(renamed).toMatchObject({
      name: 'Road bike',
      target: { cents: 3_000_00 },
      deadline: '2027-01-31',
      icon: null,
    })
    const archived = await goals.update(TENANT, goal.id, { archived: true })
    expect(archived.archivedAt).toBe(NOW.toISOString())
    clock.set(LATER)
    const still = await goals.update(TENANT, goal.id, { archived: true })
    expect(still.archivedAt).toBe(NOW.toISOString())
    expect(
      (await goals.update(TENANT, goal.id, { archived: false })).archivedAt,
    ).toBeNull()
    const linked = await goals.update(TENANT, goal.id, {
      accountId: 'checking',
    })
    expect(linked).toMatchObject({ source: 'ACCOUNT', contributions: [] })
    await expect(
      goals.update(TENANT, goal.id, { investmentId: 'cdb' }),
    ).rejects.toThrow('not both')
    await expect(goals.update(TENANT, 'nope', {})).rejects.toBeInstanceOf(
      NotFoundError,
    )

    expect(await goals.remove(TENANT, goal.id)).toEqual({ id: goal.id })
    await expect(goals.get(TENANT, goal.id)).rejects.toBeInstanceOf(
      NotFoundError,
    )
    expect(await deps.goals.listContributions(TENANT, goal.id)).toEqual([])
    expect(deps.audit.events.at(-1)).toMatchObject({
      action: 'goal.delete',
      actor: 'USER',
      subjectId: goal.id,
    })
  })

  it('lists the active goals of an entity, or the archived ones', async () => {
    const { goals } = setup()
    const first = await goals.create(TENANT, {
      entity: 'PF',
      name: 'First',
      targetCents: 100,
    })
    const company = await goals.create(TENANT, {
      entity: 'PJ',
      name: 'Company',
      targetCents: 100,
    })
    const old = await goals.create(TENANT, {
      entity: 'PF',
      name: 'Old',
      targetCents: 100,
    })
    await goals.update(TENANT, old.id, { archived: true })

    const names = async (query: Parameters<typeof goals.list>[1]) =>
      (await goals.list(TENANT, query)).map(goal => goal.name)
    expect(await names({})).toEqual([first.name, company.name])
    expect(await names({ entity: 'PF' })).toEqual(['First'])
    expect(await names({ entity: 'PJ', archived: 'false' })).toEqual([
      'Company',
    ])
    expect(await names({ archived: 'true' })).toEqual(['Old'])
  })
})
