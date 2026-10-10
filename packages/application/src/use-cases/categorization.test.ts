import { describe, expect, it } from 'vitest'
import { createCategoryRule, Money, ValidationError } from '@cashdeck/domain'
import { listTransactionsQuerySchema } from '@/dtos/finance'
import { NotFoundError } from '@/errors/errors'
import { LlmProviderError } from '@/ports/llm-provider'
import { account, fullDeps, transaction } from '@/testing/deps.test-helpers'
import { NOW, TENANT } from '@/testing/scenario.test-helpers'
import {
  categorizeAfterSync,
  ensureCategories,
  makeCategorizeTransactions,
  makeCreateCategoryRule,
  makeListCategories,
  makeUpdateTransaction,
} from '@/use-cases/categorization'
import { makeListTransactions } from '@/use-cases/finance'

const PAYEE = '11144477735'
const OTHER = '52998224725'

async function seeded() {
  const deps = fullDeps()
  await deps.accounts.save(account({ id: 'pf-1', entityId: 'pf' }))
  await deps.accounts.save(account({ id: 'pj-1', entityId: 'pj' }))
  const categories = await ensureCategories(deps, TENANT)
  const id = (key: string) =>
    categories.find(category => category.key === key)?.id as string
  return { deps, id }
}

describe('categories', () => {
  it('creates the built-in list once and lists it by name', async () => {
    const deps = fullDeps()
    const list = makeListCategories(deps)
    const first = await list(TENANT)
    const second = await list(TENANT)
    expect(first.length).toBe(20)
    expect(second.map(c => c.id)).toEqual(first.map(c => c.id))
    expect(first[0]).toMatchObject({ name: 'Bank fees', key: 'fees' })
    expect(first[0]).toEqual({
      id: expect.any(String),
      key: 'fees',
      name: 'Bank fees',
      icon: 'fees',
      parentId: null,
    })
  })
})

describe('updating a transaction', () => {
  it('sets a note without touching the category', async () => {
    const { deps } = await seeded()
    await deps.transactions.save(transaction({ id: 't1', accountId: 'pf-1' }))
    const result = await makeUpdateTransaction(deps)(TENANT, 't1', {
      note: ' lunch with the team ',
      applyToSimilar: false,
    })
    expect(result).toMatchObject({
      similarUpdated: 0,
      transaction: { note: 'lunch with the team', categoryId: null },
    })
    expect(await deps.categories.listRules(TENANT)).toEqual([])
  })

  it('learns a rule from a correction and applies it to similar ones on request', async () => {
    const { deps, id } = await seeded()
    const market = (txId: string, accountId: string, extra = {}) =>
      transaction({
        id: txId,
        accountId,
        description: `COMPRA MERCADO SOL ${txId}`,
        ...extra,
      })
    await deps.transactions.save(market('t1', 'pf-1'))
    await deps.transactions.save(market('t2', 'pf-1'))
    await deps.transactions.save(
      market('t3', 'pf-1', {
        categoryId: id('shopping'),
        categorizedBy: 'USER',
      }),
    )
    await deps.transactions.save(market('t4', 'pj-1'))
    await deps.transactions.save(market('t5', 'pf-1', { transferGroupId: 'g' }))
    const update = makeUpdateTransaction(deps)
    const first = await update(TENANT, 't1', {
      categoryId: id('groceries'),
      applyToSimilar: true,
    })
    expect(first.similarUpdated).toBe(1)
    expect(first.transaction).toMatchObject({
      categoryId: id('groceries'),
      categorizedBy: 'USER',
      categoryConfidence: 1,
    })
    const stored = async (txId: string) =>
      deps.transactions.findById(TENANT, txId)
    expect(await stored('t2')).toMatchObject({ categorizedBy: 'RULE' })
    expect((await stored('t3'))?.categoryId).toBe(id('shopping'))
    expect((await stored('t4'))?.categoryId).toBeNull()
    expect((await stored('t5'))?.categoryId).toBeNull()
    const rules = await deps.categories.listRules(TENANT)
    expect(rules).toEqual([
      expect.objectContaining({ entityId: 'pf', pattern: 'mercado sol' }),
    ])

    const second = await update(TENANT, 't2', {
      categoryId: id('restaurants'),
      applyToSimilar: false,
    })
    expect(second.similarUpdated).toBe(0)
    const updated = await deps.categories.listRules(TENANT)
    expect(updated).toEqual([
      expect.objectContaining({
        id: rules[0]?.id,
        categoryId: id('restaurants'),
      }),
    ])
  })

  it('learns a counterparty rule from a bare Pix', async () => {
    const { deps, id } = await seeded()
    const pix = (txId: string, counterparty: string | null, cents: number) =>
      transaction({
        id: txId,
        accountId: 'pf-1',
        description: 'pix key transfer',
        amount: Money.of(cents),
        counterparty,
      })
    await deps.transactions.save(pix('t1', PAYEE, -18700))
    await deps.transactions.save(pix('t2', PAYEE, -5100))
    await deps.transactions.save(pix('t3', OTHER, -18700))
    await deps.transactions.save(pix('t4', null, -18700))
    const update = makeUpdateTransaction(deps)
    const first = await update(TENANT, 't1', {
      categoryId: id('restaurants'),
      applyToSimilar: true,
    })
    expect(first.similarUpdated).toBe(1)
    const stored = async (txId: string) =>
      (await deps.transactions.findById(TENANT, txId))?.categoryId
    expect(await stored('t2')).toBe(id('restaurants'))
    expect(await stored('t3')).toBeNull()
    expect(await stored('t4')).toBeNull()
    const rules = await deps.categories.listRules(TENANT)
    expect(rules).toEqual([
      expect.objectContaining({
        entityId: 'pf',
        pattern: '',
        counterparty: PAYEE,
      }),
    ])
    await update(TENANT, 't2', {
      categoryId: id('groceries'),
      applyToSimilar: false,
    })
    expect(await deps.categories.listRules(TENANT)).toEqual([
      expect.objectContaining({
        id: rules[0]?.id,
        categoryId: id('groceries'),
      }),
    ])
    await deps.transactions.save(pix('t5', '10573521000191', -2100))
    await update(TENANT, 't5', {
      categoryId: id('restaurants'),
      applyToSimilar: true,
    })
    expect(await deps.categories.listRules(TENANT)).toHaveLength(1)
  })

  it('learns by the payee document even when the description names a bank', async () => {
    const { deps, id } = await seeded()
    const boleto = (txId: string, counterparty: string) =>
      transaction({
        id: txId,
        accountId: 'pf-1',
        description: 'Pagamento Boleto BANCO AZUL S.A.',
        counterparty,
      })
    await deps.transactions.save(boleto('b1', '11222333000181'))
    await deps.transactions.save(boleto('b2', '11444777000161'))
    await makeUpdateTransaction(deps)(TENANT, 'b1', {
      categoryId: id('transfers'),
      applyToSimilar: true,
    })
    expect(await deps.categories.listRules(TENANT)).toEqual([
      expect.objectContaining({ pattern: '', counterparty: '11222333000181' }),
    ])
    expect(
      (await deps.transactions.findById(TENANT, 'b2'))?.categoryId,
    ).toBeNull()
  })

  it('clears a category, skips a rule without merchant words and checks ids', async () => {
    const { deps, id } = await seeded()
    await deps.transactions.save(
      transaction({ id: 't1', accountId: 'pf-1', description: 'PIX 0042' }),
    )
    const update = makeUpdateTransaction(deps)
    const set = await update(TENANT, 't1', {
      categoryId: id('other'),
      applyToSimilar: true,
    })
    expect(set.similarUpdated).toBe(0)
    expect(await deps.categories.listRules(TENANT)).toEqual([])
    const cleared = await update(TENANT, 't1', {
      categoryId: null,
      applyToSimilar: false,
    })
    expect(cleared.transaction).toMatchObject({
      categoryId: null,
      categorizedBy: 'USER',
    })
    await expect(
      update(TENANT, 't1', { categoryId: 'nope', applyToSimilar: false }),
    ).rejects.toThrow(NotFoundError)
    await expect(
      update(TENANT, 'missing', { applyToSimilar: false }),
    ).rejects.toThrow(NotFoundError)
    await deps.transactions.save(transaction({ id: 'orphan', accountId: 'x' }))
    await expect(
      update(TENANT, 'orphan', { applyToSimilar: false }),
    ).rejects.toThrow(NotFoundError)
    await deps.accounts.save(account({ id: 'ghost', entityId: 'ghost' }))
    await deps.transactions.save(transaction({ id: 'g1', accountId: 'ghost' }))
    await expect(
      update(TENANT, 'g1', { applyToSimilar: false }),
    ).rejects.toThrow(NotFoundError)
  })

  it('filters the list by category, uncategorized and text', async () => {
    const { deps, id } = await seeded()
    await deps.transactions.save(
      transaction({
        id: 't1',
        accountId: 'pf-1',
        description: 'Posto Azul',
        categoryId: id('fuel'),
      }),
    )
    await deps.transactions.save(
      transaction({ id: 't2', accountId: 'pf-1', note: 'Gift for Ana' }),
    )
    const list = makeListTransactions(deps)
    const ids = async (query: Parameters<typeof list>[1]) =>
      (await list(TENANT, query)).items.map(item => item.id)
    expect(await ids({ limit: 10, categoryId: id('fuel') })).toEqual(['t1'])
    expect(await ids({ limit: 10, uncategorized: true })).toEqual(['t2'])
    expect(await ids({ limit: 10, search: 'gift' })).toEqual(['t2'])
    expect(await ids({ limit: 10, search: 'AZUL' })).toEqual(['t1'])
    expect(
      listTransactionsQuerySchema.parse({ uncategorized: 'true' })
        .uncategorized,
    ).toBe(true)
    expect(
      listTransactionsQuerySchema.parse({ uncategorized: 'false' })
        .uncategorized,
    ).toBe(false)
  })
})

describe('categorization rules', () => {
  it('creates an entity rule and applies it to existing transactions', async () => {
    const { deps, id } = await seeded()
    await deps.transactions.save(
      transaction({ id: 't1', accountId: 'pj-1', description: 'Cloud Host' }),
    )
    await deps.transactions.save(
      transaction({ id: 't2', accountId: 'pf-1', description: 'Cloud Host' }),
    )
    const create = makeCreateCategoryRule(deps)
    const company = await create(TENANT, {
      pattern: 'cloud host',
      categoryId: id('services'),
      entity: 'PJ',
    })
    expect(company).toMatchObject({ updated: 1, rule: { entityId: 'pj' } })
    const both = await create(TENANT, {
      pattern: 'cloud host',
      categoryId: id('services'),
      entity: null,
    })
    expect(both).toMatchObject({ updated: 1, rule: { entityId: null } })
    await expect(
      create(TENANT, {
        pattern: '123',
        categoryId: id('services'),
        entity: null,
      }),
    ).rejects.toThrow(ValidationError)
    await expect(
      create(TENANT, { pattern: 'x', categoryId: 'nope', entity: null }),
    ).rejects.toThrow(NotFoundError)
  })
})

describe('automatic categorization', () => {
  it('applies rules first, then asks the model in batches', async () => {
    const { deps, id } = await seeded()
    await deps.categories.saveRule(
      createCategoryRule({
        id: 'r1',
        tenantId: TENANT,
        entityId: null,
        pattern: 'Posto Azul',
        categoryId: id('fuel'),
        createdAt: NOW,
      }),
    )
    await deps.transactions.save(
      transaction({
        id: 'fuel',
        accountId: 'pf-1',
        description: 'POSTO AZUL 12',
      }),
    )
    for (const n of [1, 2, 3]) {
      await deps.transactions.save(
        transaction({
          id: `m${n}`,
          accountId: 'pj-1',
          description: `Shop ${n}`,
        }),
      )
    }
    await deps.transactions.save(
      transaction({ id: 'moved', accountId: 'pf-1', transferGroupId: 'g' }),
    )
    await deps.transactions.save(
      transaction({ id: 'old', accountId: 'pf-1', bookedOn: '2026-01-01' }),
    )
    const categories = await deps.categories.list(TENANT)
    const code = (key: string) =>
      `c${categories.findIndex(category => category.key === key) + 1}`
    deps.llm.enqueueObject({
      items: [
        { ref: 't1', category: code('shopping'), confidence: 0.9 },
        { ref: 't2', category: code('shopping'), confidence: 0.2 },
        { ref: 't3', category: 'c999', confidence: 0.9 },
        { ref: 't9', category: code('shopping'), confidence: 0.9 },
      ],
    })
    const summary = await makeCategorizeTransactions(deps)(TENANT)
    expect(summary).toEqual({ byRule: 1, byAi: 1, left: 2 })
    expect(await deps.transactions.findById(TENANT, 'fuel')).toMatchObject({
      categoryId: id('fuel'),
      categorizedBy: 'RULE',
    })
    expect(await deps.transactions.findById(TENANT, 'm1')).toMatchObject({
      categorizedBy: 'AI',
      categoryConfidence: 0.9,
    })
    const prompt = deps.llm.calls[0]?.messages[0]?.content ?? ''
    expect(prompt).toContain('t1|-50.00|Shop 1')
    expect(deps.llm.calls[0]?.responseSchema).toBeDefined()
  })

  it('shows the model the merchant and bank label, never offering Other', async () => {
    const { deps } = await seeded()
    await deps.transactions.save(
      transaction({
        id: 'pix',
        accountId: 'pf-1',
        description: 'pix key transfer',
        merchant: 'Padaria Azul Ltda',
        bankCategory: 'Eating out',
      }),
    )
    await deps.transactions.save(
      transaction({ id: 'bare', accountId: 'pf-1', description: 'Shop' }),
    )
    deps.llm.enqueueObject({ items: [] })
    await makeCategorizeTransactions(deps)(TENANT)
    const prompt = deps.llm.calls[0]?.messages[0]?.content ?? ''
    expect(prompt).toContain('|pix key transfer|Padaria Azul Ltda|Eating out')
    expect(prompt).toContain('|Shop||')
    expect(prompt).not.toMatch(/\|Other$/m)
  })

  it('leaves the rest for later when the model fails or answers badly', async () => {
    const { deps } = await seeded()
    for (let n = 0; n < 45; n += 1) {
      await deps.transactions.save(
        transaction({
          id: `m${n}`,
          accountId: 'pf-1',
          description: `Shop ${n}`,
        }),
      )
    }
    deps.llm.enqueueObject({ wrong: true })
    deps.llm.chat = async () => {
      if (deps.llm.calls.length > 0) {
        throw new LlmProviderError('down', 'chat_failed')
      }
      deps.llm.calls.push({} as never)
      return {
        text: '',
        toolCalls: [],
        usage: { inputTokens: 0, outputTokens: 0, costMillicents: 0 },
        stopReason: 'end',
        object: { wrong: true },
      }
    }
    const summary = await makeCategorizeTransactions(deps)(TENANT)
    expect(summary).toEqual({ byRule: 0, byAi: 0, left: 45 })
  })

  it('does not call the model when rules cover everything, and rethrows bugs', async () => {
    const { deps } = await seeded()
    const empty = await makeCategorizeTransactions(deps)(TENANT)
    expect(empty).toEqual({ byRule: 0, byAi: 0, left: 0 })
    expect(deps.llm.calls).toEqual([])
    await deps.transactions.save(transaction({ id: 't1', accountId: 'pf-1' }))
    deps.llm.chat = async () => {
      throw new TypeError('bug')
    }
    await expect(makeCategorizeTransactions(deps)(TENANT)).rejects.toThrow(
      'bug',
    )
  })

  it('categorizes after a sync without failing it', async () => {
    const calls: string[] = []
    const openFinance = {
      sync: async (_tenant: string, id: string) => {
        calls.push(`sync:${id}`)
        return { id }
      },
      syncAll: async (_tenant: string) => {
        calls.push('syncAll')
        return { all: true }
      },
      other: 1,
    }
    let fail = false
    const wrapped = categorizeAfterSync(openFinance, async tenantId => {
      calls.push(`categorize:${tenantId}`)
      if (fail) {
        throw new Error('down')
      }
      return { byRule: 0, byAi: 0, left: 0 }
    })
    expect(await wrapped.sync(TENANT, 'c1')).toEqual({ id: 'c1' })
    fail = true
    expect(await wrapped.syncAll(TENANT)).toEqual({ all: true })
    expect(wrapped.other).toBe(1)
    expect(calls).toEqual([
      'sync:c1',
      `categorize:${TENANT}`,
      'syncAll',
      `categorize:${TENANT}`,
    ])
  })
})
