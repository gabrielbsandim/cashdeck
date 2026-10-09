import { daysBetween } from '@/calendar/local-date'
import { type AccountType } from '@/entities/account'
import { type Transaction } from '@/entities/transaction'

export type FlowKind = 'INCOME' | 'EXPENSE' | 'NEUTRAL'

export type FlowLine = {
  readonly transaction: Transaction
  readonly accountType: AccountType
  readonly categoryKey: string | null
}

const NEUTRAL_CATEGORIES = new Set(['transfers', 'investments'])

const PAYMENT_WORDS = new Set(['pagamento', 'pagto', 'pgto', 'pag', 'pago'])

const INVESTMENT_WORDS = new Set(['cdb', 'lci', 'lca', 'rdb', 'tesouro'])

// Two legs of one move between own accounts land within this many days.
const OWN_TRANSFER_DAYS = 2

export type FlowContext = {
  // The tenant's own entity names: a Pix to or from one moves money between
  // own accounts, even when the other account is not connected.
  readonly ownNames: readonly string[]
}

const NO_CONTEXT: FlowContext = { ownNames: [] }

function wordsOf(text: string): string[] {
  return text
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .split(/[^a-z]+/)
    .filter(word => word.length > 0)
}

// Paying the card bill from checking would count every purchase twice.
export function isCardBillPayment(description: string): boolean {
  const words = wordsOf(description)
  const paying = words.some(word => PAYMENT_WORDS.has(word))
  if (words.includes('fatura')) {
    return paying
  }
  return paying && (words.includes('cartao') || words.includes('recebido'))
}

export function isInvestment(description: string): boolean {
  return wordsOf(description).some(word => INVESTMENT_WORDS.has(word))
}

// A single word could be anyone's first name, so only a full name counts.
export function namesOwner(
  description: string,
  ownNames: readonly string[],
): boolean {
  const text = ` ${wordsOf(description).join(' ')} `
  return ownNames
    .map(wordsOf)
    .filter(words => words.length > 1)
    .some(words => text.includes(` ${words.join(' ')} `))
}

function movesOwnMoney(description: string, context: FlowContext): boolean {
  return (
    isCardBillPayment(description) ||
    isInvestment(description) ||
    namesOwner(description, context.ownNames)
  )
}

function baseKind(line: FlowLine, context: FlowContext): FlowKind {
  const { transaction, accountType, categoryKey } = line
  if (transaction.transferGroupId !== null) {
    return 'NEUTRAL'
  }
  if (categoryKey !== null && NEUTRAL_CATEGORIES.has(categoryKey)) {
    return 'NEUTRAL'
  }
  if (movesOwnMoney(transaction.description, context)) {
    return 'NEUTRAL'
  }
  if (!transaction.amount.isPositive()) {
    return 'EXPENSE'
  }
  // A credit on a card is a payment or a refund, never income.
  return accountType === 'CREDIT_CARD' ? 'NEUTRAL' : 'INCOME'
}

const isOwnLeg = (expense: Transaction, income: Transaction) =>
  expense.accountId !== income.accountId &&
  expense.amount.cents === -income.amount.cents &&
  Math.abs(daysBetween(expense.bookedOn, income.bookedOn)) <= OWN_TRANSFER_DAYS

// Money moved between two own accounts shows as an expense on one and an
// income on the other, so both legs are paired off by amount and date. A card
// bill paid from checking pairs the same way with the credit on the card.
export function classifyFlow(
  lines: readonly FlowLine[],
  context: FlowContext = NO_CONTEXT,
): Map<string, FlowKind> {
  const kinds = new Map<string, FlowKind>()
  for (const line of lines) {
    kinds.set(line.transaction.id, baseKind(line, context))
  }
  const ofKind = (kind: FlowKind) =>
    lines
      .filter(
        line =>
          kinds.get(line.transaction.id) === kind &&
          line.accountType !== 'CREDIT_CARD',
      )
      .map(line => line.transaction)
      .sort((a, b) => a.bookedOn.localeCompare(b.bookedOn))
  const cardCredits = lines
    .filter(
      line =>
        line.accountType === 'CREDIT_CARD' &&
        line.transaction.amount.isPositive(),
    )
    .map(line => line.transaction)
  const legs = [...ofKind('INCOME'), ...cardCredits]
  const paired = new Set<string>()
  for (const expense of ofKind('EXPENSE')) {
    const leg = legs.find(
      income => !paired.has(income.id) && isOwnLeg(expense, income),
    )
    if (!leg) {
      continue
    }
    paired.add(leg.id)
    kinds.set(expense.id, 'NEUTRAL')
    kinds.set(leg.id, 'NEUTRAL')
  }
  return kinds
}
