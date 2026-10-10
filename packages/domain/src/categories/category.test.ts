import { describe, expect, it } from 'vitest'
import {
  type CategoryRule,
  createCategoryRule,
  DEFAULT_CATEGORIES,
  findRule,
  normalizeDescription,
  ruleMatches,
} from '@/categories/category'
import { categorize, createTransaction, withNote } from '@/entities/transaction'
import { Money } from '@/money/money'

const NOW = new Date('2026-10-08T12:00:00Z')
const PAYEE = '11144477735'

const subject = (description: string, counterparty: string | null = null) => ({
  description,
  counterparty,
})

function rule(overrides: Partial<CategoryRule> & { id: string }): CategoryRule {
  return createCategoryRule({
    tenantId: 't1',
    entityId: null,
    pattern: 'Mercado Sol',
    categoryId: 'groceries',
    createdAt: NOW,
    ...overrides,
  })
}

describe('normalizeDescription', () => {
  it('keeps the merchant words without accents, digits or bank noise', () => {
    expect(
      normalizeDescription('PIX ENVIADO 12/10 Padaria São João LTDA *123'),
    ).toBe('padaria sao joao')
    expect(normalizeDescription('  ')).toBe('')
    expect(normalizeDescription('pix key transfer')).toBe('')
  })
})

describe('category rules', () => {
  it('ships a built-in category list with unique keys', () => {
    const keys = DEFAULT_CATEGORIES.map(category => category.key)
    expect(new Set(keys).size).toBe(keys.length)
  })

  it('normalizes the pattern and defaults the priority', () => {
    const created = rule({ id: 'r1', pattern: 'COMPRA Mercado Sol 0042' })
    expect(created).toMatchObject({ pattern: 'mercado sol', priority: 0 })
    expect(rule({ id: 'r2', priority: 3 }).priority).toBe(3)
  })

  it('rejects a pattern with nothing left after normalizing', () => {
    expect(() => rule({ id: 'r1', pattern: 'PIX 123' })).toThrow(
      'A rule needs a merchant or description.',
    )
    expect(() => rule({ id: 'r1', categoryId: ' ' })).toThrow(
      'Category must not be empty.',
    )
  })

  it('matches whole words only', () => {
    const market = rule({ id: 'r1' })
    expect(
      ruleMatches(market, subject('Compra cartao MERCADO SOL centro')),
    ).toBe(true)
    expect(ruleMatches(market, subject('Supermercado Solar'))).toBe(false)
  })

  it('prefers an entity rule, then priority, then the longer pattern', () => {
    const global = rule({ id: 'global', categoryId: 'shopping' })
    const own = rule({ id: 'own', entityId: 'pf', categoryId: 'groceries' })
    const other = rule({ id: 'other', entityId: 'pj', categoryId: 'fees' })
    const urgent = rule({ id: 'urgent', pattern: 'sol', priority: 5 })
    const longer = rule({ id: 'longer', pattern: 'mercado sol centro' })
    const description = subject('Mercado Sol Centro')
    expect(findRule([global, own, other], description, 'pf')?.id).toBe('own')
    expect(findRule([global, other], description, 'pf')?.id).toBe('global')
    expect(findRule([global, urgent], description, 'pf')?.id).toBe('urgent')
    expect(findRule([global, longer], description, 'pf')?.id).toBe('longer')
    expect(findRule([global], subject('Posto Azul'), 'pf')).toBeNull()
  })

  it('matches a counterparty rule by the document alone', () => {
    const payee = rule({
      id: 'payee',
      pattern: 'pix key transfer',
      counterparty: '111.444.777-35',
      categoryId: 'restaurants',
    })
    expect(payee).toMatchObject({ pattern: '', counterparty: PAYEE })
    expect(ruleMatches(payee, subject('pix key transfer', PAYEE))).toBe(true)
    expect(ruleMatches(payee, subject('Mercado Sol', '11222333000181'))).toBe(
      false,
    )
    const market = rule({ id: 'market' })
    expect(
      findRule([market, payee], subject('Mercado Sol', PAYEE), 'pf')?.id,
    ).toBe('payee')
    expect(() =>
      rule({ id: 'masked', pattern: 'pix', counterparty: '***452308**' }),
    ).toThrow('A rule needs a merchant or description.')
  })
})

describe('transaction categorization', () => {
  const tx = createTransaction({
    id: 'tx1',
    tenantId: 't1',
    accountId: 'a1',
    amount: Money.of(-1500),
    bookedOn: '2026-10-05',
    description: 'Mercado Sol',
  })

  it('starts uncategorized with no note', () => {
    expect(tx).toMatchObject({
      note: null,
      categorizedBy: null,
      categoryConfidence: null,
    })
  })

  it('records who chose the category and how sure it was', () => {
    const ai = categorize(tx, { categoryId: 'c1', by: 'AI', confidence: 0.7 })
    expect(ai).toMatchObject({
      categoryId: 'c1',
      categorizedBy: 'AI',
      categoryConfidence: 0.7,
    })
    expect(
      categorize(ai, { categoryId: null, by: 'USER', confidence: 1 }),
    ).toMatchObject({
      categoryId: null,
      categorizedBy: 'USER',
      categoryConfidence: null,
    })
    expect(() =>
      categorize(tx, { categoryId: 'c1', by: 'AI', confidence: 1.2 }),
    ).toThrow('Confidence must be between 0 and 1.')
    expect(() =>
      categorize(tx, { categoryId: 'c1', by: 'AI', confidence: -0.1 }),
    ).toThrow('Confidence must be between 0 and 1.')
  })

  it('trims a note, clears a blank one and caps the length', () => {
    expect(withNote(tx, '  lunch  ').note).toBe('lunch')
    expect(withNote(tx, '   ').note).toBeNull()
    expect(withNote(tx, null).note).toBeNull()
    expect(() => withNote(tx, 'x'.repeat(501))).toThrow(
      'A note has at most 500 characters.',
    )
  })
})
