import {
  type Bill,
  type BillStatus,
  jumpToAssisted,
  markBillPaid,
  type PaymentAttempt,
  transitionBill,
} from '@cashdeck/domain'
import { type RailStatus } from '@/ports/rail-status'
import { type Deps } from '@/use-cases/deps'
import { allPages } from '@/use-cases/shared'

type ReconcileDeps = Pick<
  Deps,
  'bills' | 'payments' | 'railStatus' | 'audit' | 'clock' | 'ids'
>

export type ReconcileResult = {
  checked: number
  paid: number
  failed: number
  failures: Array<{ billId: string; reason: string }>
}

const WAITING: readonly BillStatus[] = ['PROCESSING', 'AWAITING_BANK_APPROVAL']

const isOpenAttempt = (attempt: PaymentAttempt) =>
  (attempt.outcome === 'SUBMITTED' || attempt.outcome === 'PENDING_APPROVAL') &&
  attempt.externalId !== null

// Asks the rail that took each waiting payment for its final state. A payment
// the rail reports as failed goes to assisted, never to another rail.
export function makeReconcilePayments(deps: ReconcileDeps) {
  async function waitingBills(tenantId: string): Promise<Bill[]> {
    const bills: Bill[] = []
    for (const status of WAITING) {
      bills.push(
        ...(await allPages(page =>
          deps.bills.list(tenantId, { status }, page),
        )),
      )
    }
    return bills
  }

  async function record(
    tenantId: string,
    from: PaymentAttempt,
    outcome: PaymentAttempt['outcome'],
    reason: string | null,
  ): Promise<void> {
    const at = deps.clock.now()
    await deps.payments.addAttempt(tenantId, {
      ...from,
      id: deps.ids.next(),
      outcome,
      reason,
      at,
    })
    await deps.audit.record({
      id: deps.ids.next(),
      tenantId,
      actor: 'SYSTEM',
      action: 'payment.reconciled',
      subjectId: from.billId,
      rail: from.rail,
      result: outcome,
      details: { externalId: from.externalId, reason },
      at,
    })
  }

  async function settle(
    tenantId: string,
    bill: Bill,
    attempt: PaymentAttempt,
    status: RailStatus,
  ): Promise<'PAID' | 'FAILED' | null> {
    if (status.outcome === 'PAID') {
      await record(tenantId, attempt, 'PAID', null)
      const paidAt = status.settledAt
        ? new Date(status.settledAt)
        : deps.clock.now()
      await deps.bills.save(markBillPaid(bill, 'RAIL', paidAt))
      return 'PAID'
    }
    if (status.outcome !== 'FAILED') {
      return null
    }
    await record(tenantId, attempt, 'FAILED', status.reason ?? 'RAIL_FAILED')
    const plan = await deps.payments.findPlan(tenantId, bill.id)
    if (plan) {
      await deps.payments.savePlan(tenantId, jumpToAssisted(plan))
    }
    await deps.bills.save(transitionBill(bill, 'ASSISTED'))
    return 'FAILED'
  }

  async function reconcileBill(tenantId: string, bill: Bill) {
    const attempts = await deps.payments.listAttempts(tenantId, bill.id)
    const open = attempts.filter(isOpenAttempt).at(-1)
    const reader = open ? deps.railStatus.get(open.rail) : undefined
    if (!open || !reader) {
      return null
    }
    const status = await reader.status(open.externalId as string, {
      tenantId,
      entityId: bill.entityId,
    })
    return settle(tenantId, bill, open, status)
  }

  return async function reconcilePayments(
    tenantId: string,
  ): Promise<ReconcileResult> {
    const result: ReconcileResult = {
      checked: 0,
      paid: 0,
      failed: 0,
      failures: [],
    }
    for (const bill of await waitingBills(tenantId)) {
      result.checked += 1
      try {
        const outcome = await reconcileBill(tenantId, bill)
        result.paid += outcome === 'PAID' ? 1 : 0
        result.failed += outcome === 'FAILED' ? 1 : 0
      } catch (error) {
        result.failures.push({ billId: bill.id, reason: String(error) })
      }
    }
    return result
  }
}
