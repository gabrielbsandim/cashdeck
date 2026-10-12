import { createBudget, createGoal, Money } from '@cashdeck/domain'
import { describe, expect, it } from 'vitest'
import { contributionInputSchema } from '@/dtos/goals'
import { InMemoryGoalRepository } from '@/testing/planning'
import { InMemoryBudgetRepository } from '@/testing/records'

const NOW = new Date('2026-10-08T12:00:00Z')

describe('planning fakes', () => {
  it('keeps goals and contributions per tenant', async () => {
    const goals = new InMemoryGoalRepository()
    const goal = createGoal({
      id: 'g1',
      tenantId: 't1',
      entityId: 'pf',
      name: 'Trip',
      target: Money.of(100),
      createdAt: NOW,
    })
    await goals.save(goal)
    const contribution = {
      id: 'c1',
      tenantId: 't1',
      goalId: 'g1',
      amount: Money.of(10),
      on: '2026-10-08',
      note: null,
      createdAt: NOW,
    }
    await goals.saveContribution(contribution)
    await goals.saveContribution({
      ...contribution,
      id: 'c0',
      createdAt: new Date(0),
    })
    expect(await goals.findById('t2', 'g1')).toBeNull()
    expect(await goals.list('t2')).toEqual([])
    await goals.delete('t2', 'g1')
    await goals.deleteContribution('t2', 'c1')
    expect(
      (await goals.listContributions('t1', 'g1')).map(item => item.id),
    ).toEqual(['c0', 'c1'])
    await goals.deleteContribution('t1', 'c0')
    await goals.delete('t1', 'g1')
    expect(await goals.list('t1')).toEqual([])
    expect(await goals.listContributions('t1', 'g1')).toEqual([])
  })

  it('keeps budgets per tenant', async () => {
    const budgets = new InMemoryBudgetRepository()
    const budget = createBudget({
      id: 'b1',
      tenantId: 't1',
      entityId: 'pf',
      categoryId: 'food',
      month: '2026-10',
      limit: Money.of(100),
      rollover: false,
    })
    await budgets.save(budget)
    expect(await budgets.findById('t2', 'b1')).toBeNull()
    await budgets.delete('t2', 'b1')
    expect(await budgets.findById('t1', 'b1')).toEqual(budget)
    expect(await budgets.list('t1', 'pf', '2026-10')).toEqual([
      { categoryId: 'food', categoryName: 'food', limit: Money.of(100) },
    ])
    expect(await budgets.listMonth('t1', 'pj', '2026-10')).toEqual([])
  })

  it('refuses a contribution of zero', () => {
    expect(contributionInputSchema.safeParse({ amountCents: 0 }).success).toBe(
      false,
    )
    expect(contributionInputSchema.safeParse({ amountCents: -1 }).success).toBe(
      true,
    )
  })
})
