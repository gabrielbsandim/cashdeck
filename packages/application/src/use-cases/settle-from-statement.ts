import {
  addDays,
  AUTO_DEBIT_MATCH_AFTER,
  type Bill,
  type BillStatus,
  CASH_ACCOUNT_TYPES,
  markBillPaid,
  matchBillsToStatement,
  STATEMENT_MATCH_WINDOW,
} from '@cashdeck/domain'
import { loadAutoDebit } from '@/use-cases/auto-debit'
import { type Deps } from '@/use-cases/deps'

// A bill already handed to a rail is settled by the rail, not the statement.
const SETTLEABLE: readonly BillStatus[] = [
  'OPEN',
  'NEEDS_CONFIRMATION',
  'ASSISTED',
]
const BILL_PAGE = { limit: 100 }

type SettleDeps = Pick<
  Deps,
  | 'bills'
  | 'accounts'
  | 'transactions'
  | 'documents'
  | 'audit'
  | 'clock'
  | 'ids'
>

const sortedDates = (bills: readonly Bill[]) =>
  bills.map(bill => bill.dueDate).sort()

export function makeSettleFromStatement(deps: SettleDeps) {
  async function unsettled(tenantId: string, entityId: string) {
    const pages = await Promise.all(
      SETTLEABLE.map(status =>
        deps.bills.list(tenantId, { entityId, status }, BILL_PAGE),
      ),
    )
    return pages.flatMap(page => page.items)
  }

  return async function settleFromStatement(
    tenantId: string,
    entityId: string,
  ): Promise<number> {
    const bills = await unsettled(tenantId, entityId)
    if (bills.length === 0) {
      return 0
    }
    const accounts = (
      await deps.accounts.listByEntity(tenantId, entityId)
    ).filter(account => CASH_ACCOUNT_TYPES.includes(account.type))
    const dates = sortedDates(bills)
    const transactions = await deps.transactions.all(tenantId, {
      accountIds: accounts.map(account => account.id),
      from: addDays(dates[0] as string, -STATEMENT_MATCH_WINDOW.before),
      to: addDays(dates.at(-1) as string, AUTO_DEBIT_MATCH_AFTER),
    })
    const at = deps.clock.now()
    const isAutoDebit = await loadAutoDebit(deps, tenantId)
    const matches = matchBillsToStatement(bills, transactions, isAutoDebit)
    for (const { bill, transaction } of matches) {
      await deps.bills.save(markBillPaid(bill, 'USER', at))
      await deps.audit.record({
        id: deps.ids.next(),
        tenantId,
        actor: 'SYSTEM',
        action: 'bill.settled_from_statement',
        subjectId: bill.id,
        rail: null,
        result: 'PAID',
        details: { transactionId: transaction.id },
        at,
      })
    }
    return matches.length
  }
}
