import { describe, expect, it } from 'vitest'
import {
  createCategoryRule,
  Money,
  type Transaction,
  ValidationError,
} from '@cashdeck/domain'
import { NotFoundError } from '@/errors/errors'
import { account, fullDeps, transaction } from '@/testing/deps.test-helpers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { makeCategoryReview } from '@/use-cases/category-review'
import { makeCategoryRules } from '@/use-cases/category-rules'

type Deps = ReturnType<typeof fullDeps>

const CATEGORIES = ['groceries', 'restaurants', 'transport', 'shopping']

async function setup() {
  const deps = fullDeps()
  for (const id of CATEGORIES) {
    await deps.categories.save({
      id,
      tenantId: TENANT,
      key: id,
      name: id,
      parentId: null,
      icon: null,
    })
  }
  await deps.accounts.save(account({ id: 'checking', entityId: 'pf' }))
  await deps.accounts.save(account({ id: 'company', entityId: 'pj' }))
  return {
    deps,
    review: makeCategoryReview(deps),
    rules: makeCategoryRules(deps),
  }
}

async function save(
  deps: Deps,
  rows: Array<Partial<Transaction> & { id: string }>,
) {
  for (const row of rows) {
    await deps.transactions.save(
      transaction({ accountId: 'checking', bookedOn: '2026-10-01', ...row }),
    )
  }
}

const ai = (categoryId: string, confidence: number) => ({
  categoryId,
  categorizedBy: 'AI' as const,
  categoryConfidence: confidence,
})

const user = (categoryId: string | null) => ({
  categoryId,
  categorizedBy: 'USER' as const,
  categoryConfidence: categoryId ? 1 : null,
})

describe('category review queue', () => {
  it('groups what needs a look by entity, direction and description words', async () => {
    const { deps, review } = await setup()
    await save(deps, [
      {
        id: 'm1',
        description: 'COMPRA MERCADO SOL 01',
        bookedOn: '2026-10-03',
      },
      { id: 'm2', description: 'MERCADO SOL 02', ...ai('groceries', 0.6) },
      { id: 'm3', description: 'Mercado Sol', ...ai('groceries', 0.95) },
      { id: 'r1', description: 'Restaurante Lua', ...user('restaurants') },
      { id: 'r2', description: 'Restaurante Lua', ...ai('shopping', 0.9) },
      { id: 'r3', description: 'Restaurante Lua', ...ai('restaurants', 0.9) },
      { id: 'ok', description: 'Posto Azul', ...ai('transport', 0.9) },
      { id: 'cleared', description: 'Loja Fechada', ...user(null) },
      { id: 'refund', description: 'Mercado Sol', amount: Money.of(900) },
      {
        id: 'pix1',
        description: 'PIX ENVIADO',
        counterparty: '11222333000181',
        amount: Money.of(-20000),
      },
      {
        id: 'pix2',
        description: 'PIX',
        counterparty: '11222333000181',
        amount: Money.of(-30000),
      },
      { id: 'bare', description: 'PIX ENVIADO' },
      { id: 'moved', description: 'Mercado Sol', transferGroupId: 'g1' },
      { id: 'draft', description: 'Mercado Sol', provisional: true },
      { id: 'ancient', description: 'Mercado Sol', bookedOn: '2026-01-01' },
      {
        id: 'pj1',
        accountId: 'company',
        description: 'Mercado Sol',
      },
    ])

    const queue = await review.queue(TENANT)

    expect(queue.pending).toBe(8)
    expect(queue.suggestions).toEqual([])
    expect(queue.groups.map(group => [group.id, group.transactionIds])).toEqual(
      [
        ['pf|OUT#11222333000181', ['pix1', 'pix2']],
        ['pf|OUT:mercado sol', ['m1', 'm2']],
        ['pj|OUT:mercado sol', ['pj1']],
        ['pf|OUT@bare', ['bare']],
        ['pf|OUT:restaurante lua', ['r2']],
        ['pf|IN:mercado sol', ['refund']],
      ],
    )
    expect(queue.groups[1]).toEqual({
      id: 'pf|OUT:mercado sol',
      entityKind: 'PF',
      merchant: 'COMPRA MERCADO SOL 01',
      pattern: 'mercado sol',
      counterparty: null,
      direction: 'OUT',
      count: 2,
      total: { cents: 10000, currency: 'BRL' },
      reasons: ['UNCATEGORIZED', 'LOW_CONFIDENCE'],
      suggestedCategoryId: 'groceries',
      confidence: 0.95,
      canCreateRule: true,
      lastBookedOn: '2026-10-03',
      transactionIds: ['m1', 'm2'],
    })
    expect(queue.groups[0]).toMatchObject({
      merchant: 'PIX ENVIADO',
      total: { cents: 50000, currency: 'BRL' },
      pattern: '',
      counterparty: '11222333000181',
      canCreateRule: true,
      suggestedCategoryId: null,
      confidence: null,
    })
    expect(queue.groups[3]).toMatchObject({ canCreateRule: false })
    expect(queue.groups[2]).toMatchObject({ entityKind: 'PJ' })
    expect(queue.groups[4]).toMatchObject({
      reasons: ['INCONSISTENT'],
      suggestedCategoryId: 'restaurants',
      confidence: 1,
    })
    expect((await review.queue(TENANT, 'PJ')).pending).toBe(1)
  })

  it('takes the category most of a group carries when the user chose none', async () => {
    const { deps, review } = await setup()
    await save(deps, [
      {
        id: 't1',
        description: 'Loja Mista',
        bookedOn: '2026-10-05',
        ...ai('groceries', 0.9),
      },
      {
        id: 't2',
        description: 'Loja Mista',
        bookedOn: '2026-10-04',
        categoryId: 'shopping',
        categorizedBy: 'RULE',
        categoryConfidence: 1,
      },
      {
        id: 't3',
        description: 'Loja Mista',
        bookedOn: '2026-10-03',
        categoryId: 'shopping',
        categorizedBy: 'RULE',
      },
      {
        id: 't4',
        description: 'Loja Mista',
        bookedOn: '2026-10-02',
        categoryId: 'transport',
        categorizedBy: 'AI',
      },
    ])
    const [group] = (await review.queue(TENANT)).groups
    expect(group).toMatchObject({
      transactionIds: ['t1', 't4'],
      reasons: ['INCONSISTENT', 'LOW_CONFIDENCE'],
      suggestedCategoryId: 'shopping',
      confidence: 1,
    })
  })

  it('answers an empty queue for an entity without accounts', async () => {
    const deps = fullDeps()
    expect(await makeCategoryReview(deps).queue(TENANT, 'PF')).toEqual({
      pending: 0,
      groups: [],
      suggestions: [],
    })
  })

  it('labels a whole group and learns one rule for the merchant', async () => {
    const { deps, review } = await setup()
    await save(deps, [
      { id: 'm1', description: 'MERCADO SOL CENTRO 01' },
      { id: 'm2', description: 'MERCADO SOL CENTRO 02' },
      {
        id: 'later',
        description: 'Mercado Sol Centro',
        bookedOn: '2026-10-07',
      },
      { id: 'mine', description: 'Mercado Sol Centro', ...user('shopping') },
      { id: 'moved', description: 'Mercado Sol Centro', transferGroupId: 'g1' },
    ])

    const result = await review.categorizeGroup(TENANT, {
      transactionIds: ['m1', 'm2', 'm2', 'moved'],
      categoryId: 'groceries',
      createRule: true,
    })

    expect(result).toMatchObject({
      updated: 2,
      similarUpdated: 1,
      rule: {
        entityKind: 'PF',
        pattern: 'mercado sol centro',
        counterparty: null,
        direction: 'OUT',
        categoryId: 'groceries',
      },
    })
    expect(await deps.transactions.findById(TENANT, 'm1')).toMatchObject({
      categoryId: 'groceries',
      categorizedBy: 'USER',
    })
    expect(await deps.transactions.findById(TENANT, 'later')).toMatchObject({
      categoryId: 'groceries',
      categorizedBy: 'RULE',
    })
    expect(await deps.transactions.findById(TENANT, 'mine')).toMatchObject({
      categoryId: 'shopping',
    })
    expect((await review.queue(TENANT)).pending).toBe(0)
  })

  it('labels without a rule when asked or when no rule fits', async () => {
    const { deps, review } = await setup()
    await save(deps, [
      { id: 'a', description: 'Padaria Lua' },
      { id: 'b', description: 'PIX ENVIADO' },
      { id: 'c', description: 'Posto Azul' },
    ])

    expect(
      await review.categorizeGroup(TENANT, {
        transactionIds: ['a'],
        categoryId: 'groceries',
        createRule: false,
      }),
    ).toEqual({ updated: 1, similarUpdated: 0, rule: null })
    expect(
      await review.categorizeGroup(TENANT, {
        transactionIds: ['b'],
        categoryId: 'groceries',
        createRule: true,
      }),
    ).toEqual({ updated: 1, similarUpdated: 0, rule: null })
    expect(await deps.categories.listRules(TENANT)).toEqual([])
  })

  it('refuses a rule across entities or directions and unknown ids', async () => {
    const { deps, review } = await setup()
    await save(deps, [
      { id: 'a', description: 'Padaria Lua' },
      { id: 'b', description: 'Padaria Lua', accountId: 'company' },
      { id: 'c', description: 'Padaria Lua', amount: Money.of(100) },
      { id: 'd', description: 'Padaria Lua', accountId: 'nowhere' },
    ])
    const input = { categoryId: 'groceries', createRule: true }

    await expect(
      review.categorizeGroup(TENANT, { ...input, transactionIds: ['a', 'b'] }),
    ).rejects.toBeInstanceOf(ValidationError)
    await expect(
      review.categorizeGroup(TENANT, { ...input, transactionIds: ['a', 'c'] }),
    ).rejects.toBeInstanceOf(ValidationError)
    expect(await deps.transactions.findById(TENANT, 'a')).toMatchObject({
      categoryId: null,
    })
    await expect(
      review.categorizeGroup(TENANT, { ...input, transactionIds: ['zz'] }),
    ).rejects.toBeInstanceOf(NotFoundError)
    await expect(
      review.categorizeGroup(TENANT, { ...input, transactionIds: ['d'] }),
    ).rejects.toBeInstanceOf(NotFoundError)
    await expect(
      review.categorizeGroup(TENANT, {
        ...input,
        categoryId: 'nope',
        transactionIds: ['a'],
      }),
    ).rejects.toBeInstanceOf(NotFoundError)
  })
})

describe('rule suggestions', () => {
  async function chosenTwice() {
    const context = await setup()
    await save(context.deps, [
      {
        id: 'u1',
        description: 'MERCADO SOL UNIDADE CENTRO',
        merchant: 'Mercado Sol',
        ...user('groceries'),
      },
      {
        id: 'u2',
        description: 'MERCADO SOL UNIDADE NORTE',
        merchant: 'Mercado Sol',
        bookedOn: '2026-10-02',
        ...user('groceries'),
      },
      {
        id: 'u3',
        description: 'Mercado Sol Unidade Sul',
        merchant: 'Mercado Sol',
        bookedOn: '2026-10-04',
      },
      { id: 'once', description: 'Padaria Lua', ...user('groceries') },
      {
        id: 'split1',
        description: 'Uber Trip',
        merchant: 'Uber',
        ...user('transport'),
      },
      {
        id: 'split2',
        description: 'Uber Eats',
        merchant: 'Uber',
        ...user('restaurants'),
      },
      { id: 'same1', description: 'Posto Azul', ...user('transport') },
      { id: 'same2', description: 'Posto Azul', ...user('transport') },
      {
        id: 'odd1',
        description: 'Alfa Store',
        merchant: 'Grupo',
        ...user('shopping'),
      },
      {
        id: 'odd2',
        description: 'Beta Shop',
        merchant: 'Grupo',
        ...user('shopping'),
      },
      { id: 'pix', description: 'PIX ENVIADO', ...user('shopping') },
    ])
    await context.deps.categories.saveRule(
      createCategoryRule({
        id: 'posto',
        tenantId: TENANT,
        entityId: null,
        pattern: 'Posto Azul',
        categoryId: 'transport',
        createdAt: new Date('2026-10-01T00:00:00Z'),
      }),
    )
    return context
  }

  const ID = 'pf|OUT|mercado sol unidade|groceries'

  it('suggests a rule after two matching choices for one merchant', async () => {
    const { review } = await chosenTwice()
    const queue = await review.queue(TENANT)
    expect(queue.suggestions).toEqual([
      {
        id: ID,
        entityKind: 'PF',
        merchant: 'Mercado Sol',
        pattern: 'mercado sol unidade',
        counterparty: null,
        direction: 'OUT',
        categoryId: 'groceries',
        count: 2,
      },
    ])
  })

  it('accepts a suggestion into a rule that relabels the rest', async () => {
    const { deps, review } = await chosenTwice()
    const accepted = await review.acceptSuggestion(TENANT, ID)
    expect(accepted).toMatchObject({
      updated: 0,
      similarUpdated: 1,
      rule: { pattern: 'mercado sol unidade', direction: 'OUT' },
    })
    expect(await deps.transactions.findById(TENANT, 'u3')).toMatchObject({
      categoryId: 'groceries',
      categorizedBy: 'RULE',
    })
    expect((await review.queue(TENANT)).suggestions).toEqual([])
    await expect(review.acceptSuggestion(TENANT, ID)).rejects.toBeInstanceOf(
      NotFoundError,
    )
  })

  it('suggests from a shared payee document or a repeated description', async () => {
    const { deps, review } = await setup()
    await save(deps, [
      {
        id: 'g1',
        description: 'PIX ENVIADO',
        merchant: 'Academia Forte',
        counterparty: '11222333000181',
        ...user('shopping'),
      },
      {
        id: 'g2',
        description: 'PIX',
        merchant: 'Academia Forte',
        counterparty: '11222333000181',
        ...user('shopping'),
      },
      { id: 'p1', description: 'Padaria Lua', ...user('groceries') },
      { id: 'p2', description: 'Padaria Lua', ...user('groceries') },
    ])
    const { suggestions } = await review.queue(TENANT)
    expect(suggestions.map(item => [item.id, item.merchant])).toEqual([
      ['pf|OUT|#11222333000181|shopping', 'Academia Forte'],
      ['pf|OUT|padaria lua|groceries', 'Padaria Lua'],
    ])
    expect(
      (await review.acceptSuggestion(TENANT, 'pf|OUT|#11222333000181|shopping'))
        .rule,
    ).toMatchObject({ pattern: '', counterparty: '11222333000181' })
  })

  it('remembers a dismissed suggestion', async () => {
    const { review } = await chosenTwice()
    expect(await review.dismissSuggestion(TENANT, ID)).toEqual({ id: ID })
    expect((await review.queue(TENANT)).suggestions).toEqual([])
    await expect(review.dismissSuggestion(TENANT, ID)).rejects.toBeInstanceOf(
      NotFoundError,
    )
  })
})

describe('category rules', () => {
  async function withRules() {
    const context = await setup()
    const rule = (id: string, extra: Record<string, unknown>) =>
      createCategoryRule({
        id,
        tenantId: TENANT,
        entityId: 'pf',
        pattern: '',
        categoryId: 'groceries',
        createdAt: new Date('2026-10-01T00:00:00Z'),
        ...extra,
      })
    await context.deps.categories.saveRule(
      rule('words', { pattern: 'Mercado Sol' }),
    )
    await context.deps.categories.saveRule(
      rule('doc', { counterparty: '11222333000181', entityId: null }),
    )
    await context.deps.categories.saveRule(
      rule('ghost', { pattern: 'Loja', entityId: 'gone' }),
    )
    return context
  }

  it('lists rules with their entity, by what they match', async () => {
    const { rules } = await withRules()
    expect(await rules.list(TENANT)).toEqual([
      expect.objectContaining({
        id: 'doc',
        entityKind: null,
        counterparty: '11222333000181',
      }),
      expect.objectContaining({ id: 'ghost', entityKind: null }),
      {
        id: 'words',
        entityKind: 'PF',
        pattern: 'mercado sol',
        counterparty: null,
        direction: null,
        categoryId: 'groceries',
        priority: 0,
        createdAt: '2026-10-01T00:00:00.000Z',
      },
    ])
  })

  it('edits a rule and relabels what it now matches', async () => {
    const { deps, rules } = await withRules()
    await save(deps, [
      { id: 'a', description: 'Padaria Lua Centro' },
      { id: 'b', description: 'Padaria Lua', ...user('shopping') },
      { id: 'c', description: 'Padaria Lua', amount: Money.of(500) },
    ])
    const edited = await rules.update(TENANT, 'doc', {
      pattern: 'Padaria Lua',
      categoryId: 'restaurants',
      direction: 'OUT',
    })
    expect(edited).toEqual({
      rule: expect.objectContaining({
        pattern: 'padaria lua',
        counterparty: null,
        direction: 'OUT',
        categoryId: 'restaurants',
      }),
      updated: 1,
    })
    const kept = await rules.update(TENANT, 'words', {})
    expect(kept.rule).toMatchObject({ pattern: 'mercado sol' })
    const doc = await rules.update(TENANT, 'doc', { direction: null })
    expect(doc.rule.direction).toBeNull()
    await expect(
      rules.update(TENANT, 'doc', { categoryId: 'nope' }),
    ).rejects.toBeInstanceOf(NotFoundError)
    await expect(
      rules.update(TENANT, 'words', { pattern: 'PIX' }),
    ).rejects.toBeInstanceOf(ValidationError)
  })

  it('deletes a rule', async () => {
    const { deps, rules } = await withRules()
    expect(await rules.remove(TENANT, 'words')).toEqual({ id: 'words' })
    expect(
      (await deps.categories.listRules(TENANT)).map(rule => rule.id),
    ).toEqual(['doc', 'ghost'])
    await expect(rules.remove(TENANT, 'words')).rejects.toBeInstanceOf(
      NotFoundError,
    )
  })
})
