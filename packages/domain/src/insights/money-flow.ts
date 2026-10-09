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

// Two legs of one move between own accounts land within this many days.
const OWN_TRANSFER_DAYS = 2

// Paying the card bill from checking would count every purchase twice.
export function isCardBillPayment(description: string): boolean {
  const words = description
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .split(/[^a-z]+/)
  const paying = words.some(word => PAYMENT_WORDS.has(word))
  if (words.includes('fatura')) {
    return paying
  }
  return paying && (words.includes('cartao') || words.includes('recebido'))
}

function baseKind(line: FlowLine): FlowKind {
  const { transaction, accountType, categoryKey } = line
  if (transaction.transferGroupId !== null) {
    return 'NEUTRAL'
  }
  if (categoryKey !== null && NEUTRAL_CATEGORIES.has(categoryKey)) {
    return 'NEUTRAL'
  }
  if (isCardBillPayment(transaction.description)) {
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
// income on the other, so both legs are paired off by amount and date.
export function classifyFlow(
  lines: readonly FlowLine[],
): Map<string, FlowKind> {
  const kinds = new Map<string, FlowKind>()
  for (const line of lines) {
    kinds.set(line.transaction.id, baseKind(line))
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
  const incomes = ofKind('INCOME')
  for (const expense of ofKind('EXPENSE')) {
    const leg = incomes.find(
      income => kinds.get(income.id) === 'INCOME' && isOwnLeg(expense, income),
    )
    if (!leg) {
      continue
    }
    kinds.set(expense.id, 'NEUTRAL')
    kinds.set(leg.id, 'NEUTRAL')
  }
  return kinds
}
