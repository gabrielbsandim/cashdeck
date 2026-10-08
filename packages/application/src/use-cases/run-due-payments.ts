import { addBusinessDays, type BillStatus, toLocalDate } from '@cashdeck/domain'
import { type BillRepository } from '@/ports/repositories'
import { type Clock } from '@/ports/system'
import { type LadderRun } from '@/use-cases/run-payment-ladder'

export type RunDuePaymentsDeps = {
  bills: BillRepository
  clock: Clock
  runLadder: (tenantId: string, billId: string) => Promise<LadderRun>
}

export type DuePaymentsSummary = {
  checked: number
  byStatus: Partial<Record<BillStatus, number>>
}

const PAGE_SIZE = 100

// Bills are worked one business day early so a late submission still settles
// in time. Ids are collected first because running the ladder changes status.
export function makeRunDuePayments(deps: RunDuePaymentsDeps) {
  return async function runDuePayments(
    tenantId: string,
  ): Promise<DuePaymentsSummary> {
    const horizon = addBusinessDays(toLocalDate(deps.clock.now()), 1)
    const dueIds: string[] = []
    let cursor: string | null = null
    do {
      const page = await deps.bills.list(
        tenantId,
        { status: 'OPEN' },
        { cursor, limit: PAGE_SIZE },
      )
      dueIds.push(
        ...page.items
          .filter(bill => bill.dueDate <= horizon)
          .map(bill => bill.id),
      )
      cursor = page.nextCursor
    } while (cursor !== null)
    const summary: DuePaymentsSummary = { checked: 0, byStatus: {} }
    for (const billId of dueIds) {
      const { bill } = await deps.runLadder(tenantId, billId)
      summary.checked += 1
      summary.byStatus[bill.status] = (summary.byStatus[bill.status] ?? 0) + 1
    }
    return summary
  }
}
