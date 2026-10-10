import { type Transaction, toCounterparty } from '@/entities/transaction'
import { ValidationError } from '@/shared/domain-error'
import { guard } from '@/shared/guard'

export type Category = {
  readonly id: string
  readonly tenantId: string
  // Stable slug of a built-in category, so a client can localize its name.
  readonly key: string | null
  readonly name: string
  readonly parentId: string | null
  readonly icon: string | null
}

export const DEFAULT_CATEGORIES = [
  { key: 'groceries', name: 'Groceries' },
  { key: 'restaurants', name: 'Restaurants' },
  { key: 'transport', name: 'Transport' },
  { key: 'fuel', name: 'Fuel' },
  { key: 'housing', name: 'Housing' },
  { key: 'utilities', name: 'Utilities' },
  { key: 'health', name: 'Health' },
  { key: 'education', name: 'Education' },
  { key: 'leisure', name: 'Leisure' },
  { key: 'shopping', name: 'Shopping' },
  { key: 'subscriptions', name: 'Subscriptions' },
  { key: 'travel', name: 'Travel' },
  { key: 'taxes', name: 'Taxes' },
  { key: 'fees', name: 'Bank fees' },
  { key: 'salary', name: 'Salary' },
  { key: 'income', name: 'Other income' },
  { key: 'investments', name: 'Investments' },
  { key: 'transfers', name: 'Transfers' },
  { key: 'services', name: 'Services' },
  { key: 'other', name: 'Other' },
] as const

export type CategoryRule = {
  readonly id: string
  readonly tenantId: string
  // Null applies to every entity; an entity rule wins over a global one.
  readonly entityId: string | null
  // Empty on a counterparty rule, which matches the document instead.
  readonly pattern: string
  readonly counterparty: string | null
  readonly categoryId: string
  readonly priority: number
  readonly createdAt: Date
}

// Words every bank prints around the merchant; matching on them would make a
// rule catch unrelated transactions.
const NOISE = new Set([
  'pix',
  'enviado',
  'enviada',
  'recebido',
  'recebida',
  'compra',
  'debito',
  'credito',
  'cartao',
  'pagamento',
  'pgto',
  'pag',
  'transf',
  'transferencia',
  'transfer',
  'key',
  'ted',
  'doc',
  'boleto',
  'ltda',
  'eireli',
  'com',
  'www',
  'br',
])

export function normalizeDescription(text: string): string {
  return text
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z]+/g, ' ')
    .split(' ')
    .filter(word => word.length >= 3 && !NOISE.has(word))
    .join(' ')
}

export type CreateCategoryRuleInput = Omit<
  CategoryRule,
  'priority' | 'counterparty'
> & {
  priority?: number
  counterparty?: string | null
}

export function createCategoryRule(
  input: CreateCategoryRuleInput,
): CategoryRule {
  const counterparty = toCounterparty(input.counterparty ?? null)
  const pattern = counterparty ? '' : normalizeDescription(input.pattern)
  if (pattern === '' && counterparty === null) {
    throw new ValidationError('A rule needs a merchant or description.')
  }
  return {
    ...input,
    pattern,
    counterparty,
    categoryId: guard.notEmpty(input.categoryId, 'Category'),
    priority: input.priority ?? 0,
  }
}

// Acquirers and wallets settle Pix for many unrelated merchants, so their
// CNPJ root says nothing of who was paid.
const PAYMENT_PROCESSORS = new Set([
  '01027058',
  '01425787',
  '08561701',
  '10440482',
  '10573521',
  '16501555',
  '18189547',
  '22896431',
  '44815065',
])

export function learnableCounterparty(value: string | null): string | null {
  const document = toCounterparty(value)
  const processor =
    document?.length === 14 && PAYMENT_PROCESSORS.has(document.slice(0, 8))
  return processor ? null : document
}

export type RuleSubject = Pick<Transaction, 'description' | 'counterparty'>

export function ruleMatches(rule: CategoryRule, subject: RuleSubject): boolean {
  if (rule.counterparty !== null) {
    return rule.counterparty === subject.counterparty
  }
  const normalized = normalizeDescription(subject.description)
  return ` ${normalized} `.includes(` ${rule.pattern} `)
}

const precedence = (a: CategoryRule, b: CategoryRule) =>
  Number(b.entityId !== null) - Number(a.entityId !== null) ||
  Number(b.counterparty !== null) - Number(a.counterparty !== null) ||
  b.priority - a.priority ||
  b.pattern.length - a.pattern.length

export function findRule(
  rules: readonly CategoryRule[],
  subject: RuleSubject,
  entityId: string,
): CategoryRule | null {
  const candidates = rules.filter(
    rule =>
      (rule.entityId === null || rule.entityId === entityId) &&
      ruleMatches(rule, subject),
  )
  return candidates.sort(precedence)[0] ?? null
}
