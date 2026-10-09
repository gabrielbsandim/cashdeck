import {
  addBusinessDays,
  type Bill,
  type BillStatus,
  toLocalDate,
} from '@cashdeck/domain'
import { type BillRepository } from '@/ports/repositories'
import { type Clock } from '@/ports/system'
import { type FundingSummary } from '@/use-cases/reserve-funding'
import { type LadderRun } from '@/use-cases/run-payment-ladder'

export type RunDuePaymentsDeps = {
  bills: BillRepository
  clock: Clock
  runLadder: (tenantId: string, billId: string) => Promise<LadderRun>
  prepareFunding: (
    tenantId: string,
    bills: readonly Bill[],
  ) => Promise<FundingSummary>
}

export type DuePaymentsSummary = {
  checked: number
  byStatus: Partial<Record<BillStatus, number>>
  funding: FundingSummary
}

const PAGE_SIZE = 100

// Bills are worked one business day early so a late submission still settles
// in time. They are collected first because running the ladder changes status,
// and the reserve is funded for all of them before the first one is paid.
export function makeRunDuePayments(deps: RunDuePaymentsDeps) {
  return async function runDuePayments(
    tenantId: string,
  ): Promise<DuePaymentsSummary> {
    const horizon = addBusinessDays(toLocalDate(deps.clock.now()), 1)
    const due: Bill[] = []
    let cursor: string | null = null
    do {
      const page = await deps.bills.list(
        tenantId,
        { status: 'OPEN' },
        { cursor, limit: PAGE_SIZE },
      )
      due.push(...page.items.filter(bill => bill.dueDate <= horizon))
      cursor = page.nextCursor
    } while (cursor !== null)
    const funding = await deps.prepareFunding(tenantId, due)
    const summary: DuePaymentsSummary = { checked: 0, byStatus: {}, funding }
    for (const { id } of due) {
      const { bill } = await deps.runLadder(tenantId, id)
      summary.checked += 1
      summary.byStatus[bill.status] = (summary.byStatus[bill.status] ?? 0) + 1
    }
    return summary
  }
}
