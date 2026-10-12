import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createTransaction, Money, toLocalDate } from '@cashdeck/domain'
import { getContainer, resetContainer } from '@/server/container'
import { POST as createAccount } from '@/app/api/v1/accounts/route'
import { GET as listCategories } from '@/app/api/v1/categories/route'
import {
  GET as listRules,
  POST as createRule,
} from '@/app/api/v1/categories/rules/route'
import {
  DELETE as removeRule,
  PATCH as updateRule,
} from '@/app/api/v1/categories/rules/[id]/route'
import { GET as reviewQueue } from '@/app/api/v1/categories/review/route'
import { POST as categorizeGroup } from '@/app/api/v1/categories/review/groups/route'
import { POST as acceptSuggestion } from '@/app/api/v1/categories/review/suggestions/accept/route'
import { POST as dismissSuggestion } from '@/app/api/v1/categories/review/suggestions/dismiss/route'

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

beforeEach(() => {
  vi.stubEnv('CASHDECK_API_TOKEN', TOKEN)
})

afterEach(() => {
  resetContainer()
  vi.unstubAllEnvs()
})

async function seed() {
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
  const rows: Array<[string, string, Record<string, unknown>]> = [
    ['t1', 'COMPRA MERCADO SOL 01', {}],
    ['t2', 'COMPRA MERCADO SOL 02', {}],
    ['u1', 'Padaria Lua Centro', { merchant: 'Padaria Lua' }],
    ['u2', 'Padaria Lua Norte', { merchant: 'Padaria Lua' }],
  ]
  for (const [id, description, extra] of rows) {
    await deps.transactions.save(
      createTransaction({
        id,
        tenantId: 'local',
        accountId,
        amount: Money.of(-2500),
        bookedOn: toLocalDate(new Date()),
        description,
        ...extra,
      }),
    )
  }
  const categories = await call(listCategories, 'GET')
  const id = (key: string) =>
    categories.body.data.find(
      (category: { key: string }) => category.key === key,
    ).id as string
  for (const tx of ['u1', 'u2']) {
    const found = await deps.transactions.findById('local', tx)
    await deps.transactions.save({
      ...(found as NonNullable<typeof found>),
      categoryId: id('groceries'),
      categorizedBy: 'USER',
      categoryConfidence: 1,
    })
  }
  return { groceries: id('groceries'), restaurants: id('restaurants') }
}

describe('category review', () => {
  it('lists the queue, labels a group and learns its rule', async () => {
    const { groceries } = await seed()
    const queue = await call(reviewQueue, 'GET', { query: '?entity=PF' })
    expect(queue.status).toBe(200)
    expect(queue.body.data).toMatchObject({
      pending: 2,
      groups: [
        {
          pattern: 'mercado sol',
          count: 2,
          reasons: ['UNCATEGORIZED'],
          transactionIds: ['t1', 't2'],
        },
      ],
      suggestions: [{ pattern: 'padaria lua', categoryId: groceries }],
    })
    const done = await call(categorizeGroup, 'POST', {
      body: { transactionIds: ['t1', 't2'], categoryId: groceries },
    })
    expect(done.status).toBe(200)
    expect(done.body.data).toMatchObject({
      updated: 2,
      rule: { pattern: 'mercado sol', direction: 'OUT', entityKind: 'PF' },
    })
    const bad = await call(reviewQueue, 'GET', { query: '?entity=XX' })
    expect(bad.status).toBe(422)
    const empty = await call(categorizeGroup, 'POST', {
      body: { transactionIds: [], categoryId: groceries },
    })
    expect(empty.status).toBe(422)
  })

  it('accepts and dismisses rule suggestions', async () => {
    await seed()
    const queue = await call(reviewQueue, 'GET')
    const id = queue.body.data.suggestions[0].id as string
    const dismissed = await call(dismissSuggestion, 'POST', { body: { id } })
    expect(dismissed.body.data).toEqual({ id })
    const gone = await call(acceptSuggestion, 'POST', { body: { id } })
    expect(gone.status).toBe(404)
    resetContainer()
    await seed()
    const fresh = await call(reviewQueue, 'GET')
    const accepted = await call(acceptSuggestion, 'POST', {
      body: { id: fresh.body.data.suggestions[0].id },
    })
    expect(accepted.status).toBe(201)
    expect(accepted.body.data.rule).toMatchObject({ pattern: 'padaria lua' })
  })
})

describe('category rules', () => {
  it('lists, edits and deletes rules', async () => {
    const { groceries, restaurants } = await seed()
    await call(createRule, 'POST', {
      body: { pattern: 'Mercado Sol', categoryId: groceries, entity: 'PF' },
    })
    const listed = await call(listRules, 'GET')
    expect(listed.status).toBe(200)
    const rule = listed.body.data[0]
    expect(rule).toMatchObject({ pattern: 'mercado sol', entityKind: 'PF' })
    const edited = await call(updateRule, 'PATCH', {
      params: { id: rule.id },
      body: { categoryId: restaurants, direction: 'OUT' },
    })
    expect(edited.body.data).toMatchObject({
      rule: { categoryId: restaurants, direction: 'OUT' },
      updated: 2,
    })
    const invalid = await call(updateRule, 'PATCH', {
      params: { id: rule.id },
      body: { direction: 'UP' },
    })
    expect(invalid.status).toBe(422)
    const removed = await call(removeRule, 'DELETE', {
      params: { id: rule.id },
    })
    expect(removed.body.data).toEqual({ id: rule.id })
    const missing = await call(removeRule, 'DELETE', {
      params: { id: rule.id },
    })
    expect(missing.status).toBe(404)
  })
})
