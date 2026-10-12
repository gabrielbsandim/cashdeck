import { type PrismaClient } from '@prisma/client'
import { describe, expect, it, vi } from 'vitest'
import { createBudget, createGoal, Money } from '@cashdeck/domain'
import {
  createPrismaPlanning,
  goalFromRow,
  goalToRow,
} from '@/repositories/prisma-planning'

const TENANT = 't1'
const NOW = new Date('2026-10-08T12:00:00.000Z')

const DELEGATES = ['goal', 'goalContribution', 'budget', 'category'] as const
const METHODS = [
  'upsert',
  'findFirst',
  'findMany',
  'create',
  'deleteMany',
] as const

type Delegate = Record<(typeof METHODS)[number], ReturnType<typeof vi.fn>>

function mockClient() {
  const db = Object.fromEntries(
    DELEGATES.map(name => [
      name,
      Object.fromEntries(METHODS.map(method => [method, vi.fn()])),
    ]),
  ) as Record<(typeof DELEGATES)[number], Delegate>
  return { db, repos: createPrismaPlanning(db as unknown as PrismaClient) }
}

const goal = createGoal({
  id: 'g1',
  tenantId: TENANT,
  entityId: 'pf',
  name: 'Trip',
  target: Money.of(500_000),
  deadline: '2027-06-30',
  icon: 'plane',
  createdAt: NOW,
})

const budget = createBudget({
  id: 'b1',
  tenantId: TENANT,
  entityId: 'pf',
  categoryId: 'food',
  month: '2026-10',
  limit: Money.of(80_000),
  carried: Money.of(5_000),
  rollover: true,
})

const budgetRow = {
  id: 'b1',
  tenantId: TENANT,
  entityId: 'pf',
  categoryId: 'food',
  month: '2026-10',
  limitCents: 80_000n,
  carriedCents: 5_000n,
  rollover: true,
}

describe('PrismaGoalRepository', () => {
  it('maps a goal both ways, with and without a deadline', () => {
    expect(goalFromRow(goalToRow(goal))).toEqual(goal)
    const open = { ...goal, deadline: null }
    expect(goalFromRow(goalToRow(open))).toEqual(open)
  })

  it('lists, finds, saves and deletes goals by tenant', async () => {
    const { db, repos } = mockClient()
    db.goal.findMany.mockResolvedValueOnce([goalToRow(goal)])
    db.goal.findFirst
      .mockResolvedValueOnce(goalToRow(goal))
      .mockResolvedValueOnce(null)
    expect(await repos.goals.list(TENANT)).toEqual([goal])
    expect(await repos.goals.findById(TENANT, 'g1')).toEqual(goal)
    expect(await repos.goals.findById(TENANT, 'gone')).toBeNull()
    await repos.goals.save(goal)
    expect(db.goal.upsert.mock.calls[0]?.[0]).toEqual({
      where: { id: 'g1' },
      create: goalToRow(goal),
      update: goalToRow(goal),
    })
    await repos.goals.delete(TENANT, 'g1')
    expect(db.goalContribution.deleteMany).toHaveBeenCalledWith({
      where: { tenantId: TENANT, goalId: 'g1' },
    })
    expect(db.goal.deleteMany).toHaveBeenCalledWith({
      where: { tenantId: TENANT, id: 'g1' },
    })
  })

  it('stores signed contributions by day', async () => {
    const { db, repos } = mockClient()
    const contribution = {
      id: 'c1',
      tenantId: TENANT,
      goalId: 'g1',
      amount: Money.of(-1_500),
      on: '2026-10-08',
      note: 'Back to checking',
      createdAt: NOW,
    }
    await repos.goals.saveContribution(contribution)
    const data = db.goalContribution.create.mock.calls[0]?.[0].data
    expect(data).toEqual({
      id: 'c1',
      tenantId: TENANT,
      goalId: 'g1',
      amountCents: -1_500n,
      on: new Date('2026-10-08T00:00:00.000Z'),
      note: 'Back to checking',
      createdAt: NOW,
    })
    db.goalContribution.findMany.mockResolvedValueOnce([data])
    expect(await repos.goals.listContributions(TENANT, 'g1')).toEqual([
      contribution,
    ])
    await repos.goals.deleteContribution(TENANT, 'c1')
    expect(db.goalContribution.deleteMany).toHaveBeenCalledWith({
      where: { tenantId: TENANT, id: 'c1' },
    })
  })
})

describe('PrismaBudgetRepository', () => {
  it('names each budget by its category, with the carry in the limit', async () => {
    const { db, repos } = mockClient()
    db.budget.findMany.mockResolvedValueOnce([
      budgetRow,
      { ...budgetRow, id: 'b2', categoryId: 'gone', carriedCents: 0n },
    ])
    db.category.findMany.mockResolvedValueOnce([{ id: 'food', name: 'Food' }])
    expect(await repos.budgets.list(TENANT, 'pf', '2026-10')).toEqual([
      { categoryId: 'food', categoryName: 'Food', limit: Money.of(85_000) },
      { categoryId: 'gone', categoryName: 'gone', limit: Money.of(80_000) },
    ])
    expect(db.category.findMany.mock.calls[0]?.[0].where).toEqual({
      tenantId: TENANT,
      id: { in: ['food', 'gone'] },
    })
  })

  it('finds, saves and deletes a budget by tenant', async () => {
    const { db, repos } = mockClient()
    db.budget.findFirst
      .mockResolvedValueOnce(budgetRow)
      .mockResolvedValueOnce(null)
    expect(await repos.budgets.findById(TENANT, 'b1')).toEqual(budget)
    expect(await repos.budgets.findById(TENANT, 'b9')).toBeNull()
    await repos.budgets.save(budget)
    expect(db.budget.upsert.mock.calls[0]?.[0]).toEqual({
      where: { id: 'b1' },
      create: budgetRow,
      update: budgetRow,
    })
    await repos.budgets.delete(TENANT, 'b1')
    expect(db.budget.deleteMany).toHaveBeenCalledWith({
      where: { tenantId: TENANT, id: 'b1' },
    })
  })
})
