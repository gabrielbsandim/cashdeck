import { type Bill } from '@/bills/bill'
import { daysBetween } from '@/calendar/local-date'
import { type Transaction } from '@/entities/transaction'

export const STATEMENT_MATCH_WINDOW = { before: 10, after: 7 } as const

export type StatementMatch = { bill: Bill; transaction: Transaction }

type Candidate = StatementMatch & { distance: number }

function candidateOf(bill: Bill, transaction: Transaction): Candidate | null {
  const offset = daysBetween(bill.dueDate, transaction.bookedOn)
  const inWindow =
    offset >= -STATEMENT_MATCH_WINDOW.before &&
    offset <= STATEMENT_MATCH_WINDOW.after
  const paysIt =
    transaction.amount.currency === bill.amount.currency &&
    transaction.amount.cents === -bill.amount.cents
  if (!inWindow || !paysIt) {
    return null
  }
  return { bill, transaction, distance: Math.abs(offset) }
}

// An outgoing transaction of exactly the bill amount near its due date pays
// it; each side is used once, the closest date first.
export function matchBillsToStatement(
  bills: readonly Bill[],
  transactions: readonly Transaction[],
): StatementMatch[] {
  const candidates = bills
    .flatMap(bill => transactions.map(tx => candidateOf(bill, tx)))
    .filter((candidate): candidate is Candidate => candidate !== null)
    .sort((a, b) => a.distance - b.distance)
  const usedBills = new Set<string>()
  const usedTransactions = new Set<string>()
  const matches: StatementMatch[] = []
  for (const { bill, transaction } of candidates) {
    if (usedBills.has(bill.id) || usedTransactions.has(transaction.id)) {
      continue
    }
    usedBills.add(bill.id)
    usedTransactions.add(transaction.id)
    matches.push({ bill, transaction })
  }
  return matches
}
