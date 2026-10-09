import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { type FakeLlmProvider } from '@cashdeck/application'
import { createCategoryRule, createTransaction, Money } from '@cashdeck/domain'
import {
  buildContainer,
  chatConfig,
  getContainer,
  resetContainer,
} from '@/server/container'
import { readEnv } from '@/server/env'
import { POST as createAccount } from '@/app/api/v1/accounts/route'
import { GET as listTransactions } from '@/app/api/v1/transactions/route'
import { PATCH as updateTransaction } from '@/app/api/v1/transactions/[id]/route'
import { GET as listCategories } from '@/app/api/v1/categories/route'
import {
  GET as listThreads,
  POST as createThread,
} from '@/app/api/v1/chat/threads/route'
import {
  GET as listMessages,
  POST as sendMessage,
} from '@/app/api/v1/chat/threads/[id]/messages/route'
import { POST as confirmAction } from '@/app/api/v1/chat/actions/[id]/confirm/route'
import { POST as cancelAction } from '@/app/api/v1/chat/actions/[id]/cancel/route'
import { POST as syncConnection } from '@/app/api/v1/open-finance/connections/[id]/sync/route'

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

const llm = () => getContainer().deps.llm as FakeLlmProvider

const usage = { inputTokens: 1, outputTokens: 1, costMillicents: 10 }

beforeEach(() => {
  vi.stubEnv('CASHDECK_API_TOKEN', TOKEN)
})

afterEach(() => {
  resetContainer()
  vi.unstubAllEnvs()
})

async function seedTransactions() {
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
  for (const [id, description] of [
    ['t1', 'COMPRA MERCADO SOL 01'],
    ['t2', 'COMPRA MERCADO SOL 02'],
    ['t3', 'Posto Azul'],
  ]) {
    await deps.transactions.save(
      createTransaction({
        id: id as string,
        tenantId: 'local',
        accountId,
        amount: Money.of(-2500),
        bookedOn: new Date().toISOString().slice(0, 10),
        description: description as string,
      }),
    )
  }
  return accountId
}

describe('transactions and categories', () => {
  it('lists categories and corrects a transaction for similar ones', async () => {
    await seedTransactions()
    const categories = await call(listCategories, 'GET')
    expect(categories.status).toBe(200)
    const groceries = categories.body.data.find(
      (category: { key: string }) => category.key === 'groceries',
    )
    const patched = await call(updateTransaction, 'PATCH', {
      params: { id: 't1' },
      body: { categoryId: groceries.id, note: 'weekly', applyToSimilar: true },
    })
    expect(patched.status).toBe(200)
    expect(patched.body.data).toMatchObject({
      similarUpdated: 1,
      transaction: {
        id: 't1',
        note: 'weekly',
        categorizedBy: 'USER',
        categoryConfidence: 1,
      },
    })
    const uncategorized = await call(listTransactions, 'GET', {
      query: '?uncategorized=true',
    })
    expect(uncategorized.body.data.map((tx: { id: string }) => tx.id)).toEqual([
      't3',
    ])
    const searched = await call(listTransactions, 'GET', {
      query: `?search=weekly&categoryId=${groceries.id}`,
    })
    expect(searched.body.data).toHaveLength(1)
    const invalid = await call(updateTransaction, 'PATCH', {
      params: { id: 't1' },
      body: { note: 'x'.repeat(501) },
    })
    expect(invalid.status).toBe(422)
    const missing = await call(updateTransaction, 'PATCH', {
      params: { id: 'nope' },
      body: {},
    })
    expect(missing.status).toBe(404)
  })

  it('categorizes with the learned rules after a sync', async () => {
    await seedTransactions()
    const container = getContainer()
    const fuel = (await container.listCategories('local')).find(
      category => category.key === 'fuel',
    )
    await container.deps.categories.saveRule(
      createCategoryRule({
        id: 'r1',
        tenantId: 'local',
        entityId: null,
        pattern: 'Posto Azul',
        categoryId: fuel?.id as string,
        createdAt: new Date(),
      }),
    )
    const missing = await call(syncConnection, 'POST', { params: { id: 'x' } })
    expect(missing.status).toBe(404)
    expect(await container.openFinance.syncAll('local')).toMatchObject({
      connections: 0,
    })
    expect(
      await container.deps.transactions.findById('local', 't3'),
    ).toMatchObject({ categoryId: fuel?.id, categorizedBy: 'RULE' })
  })
})

describe('chat', () => {
  it('runs a turn with a proposal and confirms it', async () => {
    await seedTransactions()
    const thread = await call(createThread, 'POST', { body: { scope: 'PF' } })
    expect(thread.status).toBe(201)
    const threadId = thread.body.data.id as string
    llm()
      .enqueue({
        text: '',
        toolCalls: [
          {
            id: 'c1',
            name: 'create_categorization_rule',
            arguments: { pattern: 'Posto Azul', category: 'Fuel' },
          },
        ],
        usage,
        stopReason: 'tool_use',
      })
      .enqueue({
        text: 'Confirme a regra.',
        toolCalls: [],
        usage,
        stopReason: 'end',
      })
    const sent = await call(sendMessage, 'POST', {
      params: { id: threadId },
      body: { text: 'Posto Azul é combustível' },
    })
    expect(sent.status).toBe(201)
    const [user, assistant] = sent.body.data.messages
    expect(user.text).toBe('Posto Azul é combustível')
    expect(assistant.text).toBe('Confirme a regra.')
    const action = assistant.actions[0]
    expect(action).toMatchObject({
      tool: 'CREATE_CATEGORY_RULE',
      status: 'PENDING',
      details: { pattern: 'posto azul', category: 'Fuel' },
    })
    const confirmed = await call(confirmAction, 'POST', {
      params: { id: action.id },
      body: {},
    })
    expect(confirmed.body.data).toMatchObject({
      status: 'CONFIRMED',
      result: { updated: 1 },
    })
    const cancelled = await call(cancelAction, 'POST', {
      params: { id: action.id },
    })
    expect(cancelled.body.data.status).toBe('CONFIRMED')
    const threads = await call(listThreads, 'GET', { query: '?limit=5' })
    expect(threads.body).toMatchObject({
      data: [{ id: threadId, title: 'Posto Azul é combustível' }],
      nextCursor: null,
    })
    const messages = await call(listMessages, 'GET', {
      params: { id: threadId },
    })
    expect(messages.body.data).toHaveLength(2)
  })

  it('validates the input and answers 429 once the quota is used', async () => {
    vi.stubEnv('CHAT_DAILY_TURN_LIMIT', '1')
    const thread = await call(createThread, 'POST', { body: {} })
    expect(thread.body.data.scope).toBe('ALL')
    const params = { id: thread.body.data.id as string }
    const empty = await call(sendMessage, 'POST', {
      params,
      body: { text: ' ' },
    })
    expect(empty.status).toBe(422)
    const html = await call(sendMessage, 'POST', {
      params,
      body: {
        attachments: [
          { fileName: 'x.html', mimeType: 'text/html', base64: 'eA==' },
        ],
      },
    })
    expect(html.status).toBe(422)
    expect(
      (await call(sendMessage, 'POST', { params, body: { text: 'Oi' } }))
        .status,
    ).toBe(201)
    const limited = await call(sendMessage, 'POST', {
      params,
      body: { text: 'Oi' },
    })
    expect(limited.status).toBe(429)
    expect(limited.body.error.code).toBe('RATE_LIMITED')
    const missing = await call(listMessages, 'GET', { params: { id: 'nope' } })
    expect(missing.status).toBe(404)
  })

  it('reads the chat settings from the environment', () => {
    expect(chatConfig(readEnv({}))).toMatchObject({
      enabled: true,
      dailyTurnLimit: 100,
      dailyCostLimitMillicents: 200_000,
      maxRounds: 6,
      turnBudgetMs: 25_000,
    })
    const tuned = chatConfig(
      readEnv({
        CHAT_ENABLED: 'false',
        CHAT_DAILY_TURN_LIMIT: '5',
        CHAT_DAILY_COST_LIMIT_CENTS: '50',
        CHAT_MAX_ROUNDS: '40',
        CHAT_TURN_BUDGET_MS: '',
      }),
    )
    expect(tuned).toMatchObject({
      enabled: false,
      dailyTurnLimit: 5,
      dailyCostLimitMillicents: 50_000,
      maxRounds: 12,
      turnBudgetMs: 25_000,
    })
    expect(() => readEnv({ CHAT_MAX_ROUNDS: 'many' })).toThrow()
    expect(
      buildContainer(readEnv({ CHAT_ENABLED: 'false' })).chat,
    ).toBeDefined()
  })
})
