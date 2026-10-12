import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createTransaction, Money, toLocalDate } from '@cashdeck/domain'
import { getContainer, resetContainer } from '@/server/container'
import { POST as createAccount } from '@/app/api/v1/accounts/route'
import { GET as listGoals, POST as createGoal } from '@/app/api/v1/goals/route'
import {
  DELETE as removeGoal,
  GET as getGoal,
  PATCH as updateGoal,
} from '@/app/api/v1/goals/[id]/route'
import { POST as contribute } from '@/app/api/v1/goals/[id]/contributions/route'
import { DELETE as removeContribution } from '@/app/api/v1/goals/[id]/contributions/[contributionId]/route'
import {
  GET as budgetMonth,
  POST as createBudget,
} from '@/app/api/v1/budgets/route'
import {
  DELETE as removeBudget,
  PATCH as updateBudget,
} from '@/app/api/v1/budgets/[id]/route'
import { POST as copyBudgets } from '@/app/api/v1/budgets/copy/route'
import {
  GET as suggestBudgets,
  POST as acceptSuggestions,
} from '@/app/api/v1/budgets/suggestions/route'

const TOKEN = 'test-token-0123456789'

type Handler = (request: Request, context: never) => Promise<Response>

async function call(
  handler: unknown,
  method: string,
  options: {
    body?: unknown
    params?: Record<string, string>
    query?: string
  } = {},
) {
  const request = new Request(
    `http://localhost/api/v1/test${options.query ?? ''}`,
    {
      method,
      headers: { authorization: `Bearer ${TOKEN}` },
      body:
        options.body === undefined ? undefined : JSON.stringify(options.body),
    },
  )
  const context = { params: Promise.resolve(options.params ?? {}) }
  const response = await (handler as Handler)(request, context as never)
  return { status: response.status, body: await response.json() }
}

function shiftMonth(month: string, by: number): string {
  const [year, number] = month.split('-').map(Number) as [number, number]
  const index = year * 12 + number - 1 + by
  return `${Math.floor(index / 12)}-${String((index % 12) + 1).padStart(2, '0')}`
}

beforeEach(() => {
  vi.stubEnv('CASHDECK_API_TOKEN', TOKEN)
})

afterEach(() => {
  resetContainer()
  vi.unstubAllEnvs()
})

async function categoryId(key: string): Promise<string> {
  const categories = await getContainer().listCategories('local')
  const found = categories.find(category => category.key === key)
  return found?.id as string
}

async function seedSpending(entries: [string, string, number][]) {
  const created = await call(createAccount, 'POST', {
    body: {
      entity: 'PF',
      institution: 'Bank',
      name: 'Checking',
      type: 'CHECKING',
    },
  })
  const accountId = created.body.data.id as string
  const { deps } = getContainer()
  for (const [index, [bookedOn, key, cents]] of entries.entries()) {
    await deps.transactions.save({
      ...createTransaction({
        id: `t${index}`,
        tenantId: 'local',
        accountId,
        amount: Money.of(-cents),
        bookedOn,
        description: `Purchase ${index}`,
      }),
      categoryId: await categoryId(key),
    })
  }
  return accountId
}

describe('goals', () => {
  it('creates a goal, takes contributions and celebrates the target', async () => {
    const created = await call(createGoal, 'POST', {
      body: {
        name: 'Reserva',
        targetCents: 100_000,
        icon: 'shield',
        initialCents: 40_000,
      },
    })
    expect(created.status).toBe(201)
    expect(created.body.data).toMatchObject({
      name: 'Reserva',
      source: 'MANUAL',
      percent: 40,
      status: 'ON_TRACK',
    })
    const id = created.body.data.id as string
    const added = await call(contribute, 'POST', {
      params: { id },
      body: { amountCents: 60_000, note: 'Bonus' },
    })
    expect(added.status).toBe(201)
    expect(added.body.data).toMatchObject({ percent: 100, status: 'DONE' })
    const contributionId = added.body.data.contributions[0].id as string
    const undone = await call(removeContribution, 'DELETE', {
      params: { id, contributionId },
    })
    expect(undone.body.data.percent).toBe(40)
    const listed = await call(listGoals, 'GET', { query: '?entity=PF' })
    expect(listed.body.data.map((goal: { id: string }) => goal.id)).toEqual([
      id,
    ])
    const fetched = await call(getGoal, 'GET', { params: { id } })
    expect(fetched.body.data.contributions).toHaveLength(1)
    const archived = await call(updateGoal, 'PATCH', {
      params: { id },
      body: { archived: true },
    })
    expect(archived.body.data.archivedAt).not.toBeNull()
    expect((await call(listGoals, 'GET')).body.data).toEqual([])
    const removed = await call(removeGoal, 'DELETE', { params: { id } })
    expect(removed.body.data).toEqual({ id })
    expect((await call(getGoal, 'GET', { params: { id } })).status).toBe(404)
  })

  it('follows a linked account and refuses bad input', async () => {
    const accountId = await seedSpending([])
    const linked = await call(createGoal, 'POST', {
      body: { name: 'Viagem', targetCents: 50_000, accountId },
    })
    expect(linked.body.data).toMatchObject({
      source: 'ACCOUNT',
      linkedName: 'Checking',
    })
    const manualOnly = await call(contribute, 'POST', {
      params: { id: linked.body.data.id },
      body: { amountCents: 100 },
    })
    expect(manualOnly.status).toBe(422)
    const invalid = await call(createGoal, 'POST', {
      body: { name: '', targetCents: 0 },
    })
    expect(invalid.status).toBe(422)
    const zero = await call(contribute, 'POST', {
      params: { id: linked.body.data.id },
      body: { amountCents: 0 },
    })
    expect(zero.status).toBe(422)
  })
})

describe('budgets', () => {
  it('sets, edits, copies and drops the budgets of a month', async () => {
    const today = toLocalDate(new Date())
    const month = today.slice(0, 7)
    await seedSpending([[today, 'groceries', 45_000]])
    const groceries = await categoryId('groceries')
    const created = await call(createBudget, 'POST', {
      body: { categoryId: groceries, limitCents: 50_000, rollover: true },
    })
    expect(created.status).toBe(201)
    expect(created.body.data).toMatchObject({
      month,
      total: { percent: 90, level: 'NEAR' },
    })
    const id = created.body.data.items[0].id as string
    const duplicate = await call(createBudget, 'POST', {
      body: { categoryId: groceries, limitCents: 10_000 },
    })
    expect(duplicate.status).toBe(409)
    const raised = await call(updateBudget, 'PATCH', {
      params: { id },
      body: { limitCents: 60_000 },
    })
    expect(raised.body.data.items[0]).toMatchObject({
      limit: { cents: 60_000 },
      remaining: { cents: 15_000 },
    })
    const copied = await call(copyBudgets, 'POST', {
      body: { entity: 'PF', month },
    })
    expect(copied.body.data).toMatchObject({
      month: shiftMonth(month, 1),
      items: [{ carried: { cents: 15_000 }, available: { cents: 75_000 } }],
    })
    const fetched = await call(budgetMonth, 'GET', {
      query: `?entity=PF&month=${month}`,
    })
    expect(fetched.body.data.items).toHaveLength(1)
    const dropped = await call(removeBudget, 'DELETE', { params: { id } })
    expect(dropped.body.data.items).toEqual([])
    const missing = await call(updateBudget, 'PATCH', {
      params: { id },
      body: { limitCents: 1 },
    })
    expect(missing.status).toBe(404)
  })

  it('suggests limits from the last three months and accepts them', async () => {
    const month = toLocalDate(new Date()).slice(0, 7)
    await seedSpending([
      [`${shiftMonth(month, -3)}-10`, 'groceries', 40_000],
      [`${shiftMonth(month, -2)}-10`, 'groceries', 52_000],
      [`${shiftMonth(month, -1)}-10`, 'groceries', 61_000],
    ])
    const suggested = await call(suggestBudgets, 'GET')
    expect(suggested.status).toBe(200)
    expect(suggested.body.data.items).toMatchObject([
      { key: 'groceries', suggested: { cents: 55_000 }, current: null },
    ])
    const item = suggested.body.data.items[0]
    const accepted = await call(acceptSuggestions, 'POST', {
      body: {
        items: [{ categoryId: item.categoryId, limitCents: 55_000 }],
      },
    })
    expect(accepted.body.data.items).toMatchObject([
      { key: 'groceries', limit: { cents: 55_000 } },
    ])
    const empty = await call(acceptSuggestions, 'POST', { body: { items: [] } })
    expect(empty.status).toBe(422)
  })
})
